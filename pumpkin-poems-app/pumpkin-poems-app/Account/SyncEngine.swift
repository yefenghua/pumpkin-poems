import Foundation
import Observation
import SwiftData

/// Multi-device sync for the current child profile (L09, docs/api/phase2-api.md §4).
/// Learning events go up once and come back from other devices; new remote events are replayed into the derived
/// records. Writing travels as revisioned records: a concurrent edit keeps both versions (冲突副本) and a deletion
/// stays deleted. Everything is saved locally first, so a weak network only shows 待同步.
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?
    /// Local changes not uploaded yet, for the 待同步 badge.
    private(set) var pendingCount = 0
    /// Conflict copies made by the last sync, for a one-time notice.
    private(set) var newConflictCopies = 0

    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .learningRecordsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSync() }
        }
    }

    // MARK: Wire format

    struct WireEvent: Codable {
        var seq: Int?
        let id: String
        let kind: String
        let poemID: String?
        let at: Date
        let deviceID: String
        let payload: JSONValue
    }

    struct DraftData: Codable, Equatable {
        let title: String
        let themeID: String
        let wordIDs: [String]
        let lines: [String]
        let mode: String
        let form: Int
        let status: String
        let exampleLineID: String?
        let createdAt: Date
        let conflictOf: String?
    }

    struct WireDraft: Codable {
        var seq: Int?
        let id: String
        var baseRevision: Int?
        var revision: Int?
        let deleted: Bool
        let updatedAt: Date
        let data: DraftData?
    }

    private struct Request: Encodable {
        let cursor: Int
        let events: [WireEvent]
        let drafts: [WireDraft]
    }

    private struct DraftResult: Decodable {
        let id: String
        let status: String
        let revision: Int
    }

    private struct Response: Decodable {
        let cursor: Int
        let events: [WireEvent]?
        let drafts: [WireDraft]?
        let draftResults: [DraftResult]?
        let hasMore: Bool?
    }

    // MARK: Cursor

    private static func cursorKey(_ profileID: String) -> String { "sync.cursor.\(profileID)" }

    static func forgetCursor(for profileID: String) {
        UserDefaults.standard.removeObject(forKey: cursorKey(profileID))
    }

    // MARK: Triggers

    func scheduleSync() {
        refreshPendingCount()
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func refreshPendingCount() {
        guard !ProfileManager.shared.isGuest else { pendingCount = 0; return }
        let context = ProfileManager.shared.container.mainContext
        let events = (try? context.fetchCount(FetchDescriptor<LearningEvent>(predicate: #Predicate { !$0.isSynced }))) ?? 0
        let drafts = (try? context.fetchCount(FetchDescriptor<PoemDraft>(predicate: #Predicate { $0.isDirty }))) ?? 0
        pendingCount = events + drafts
    }

    /// Syncs the current profile. Guests and signed-out devices do nothing.
    func syncNow() async {
        let account = AccountStore.shared
        guard account.isSignedIn, let profileID = ProfileManager.shared.currentProfileID, status != .syncing else { return }
        status = .syncing
        do {
            newConflictCopies = try await sync(container: ProfileManager.shared.container, profileID: profileID,
                                               client: account.client)
            status = .idle
            lastSyncedAt = Date()
        } catch APIError.unauthorized {
            account.handleUnauthorized()
            status = .failed("unauthorized")
        } catch {
            status = .failed(error.localizedDescription)
            Telemetry.shared.log("sync_failed", ["reason": .string(String(describing: error).prefix(120).description)])
        }
        refreshPendingCount()
    }

    // MARK: Guest migration

    /// What a guest would bring into a profile, shown before the parent confirms.
    static func guestSummary() -> (poems: Int, drafts: Int) {
        let context = ModelContext(ProfileManager.makeContainer(for: nil))
        let poems = ((try? context.fetch(FetchDescriptor<PoemProgress>())) ?? []).filter { $0.step > .notStarted }.count
        let drafts = (try? context.fetchCount(FetchDescriptor<PoemDraft>(predicate: #Predicate { !$0.pendingDeletion }))) ?? 0
        return (poems, drafts)
    }

    /// Uploads the guest's events and writing into `profileID`, switches to that profile and pulls everything,
    /// then empties the guest store. Event IDs are kept, so doing this twice never counts anything twice.
    func migrateGuest(into profileID: String) async -> Bool {
        let account = AccountStore.shared
        guard account.isSignedIn else { return false }
        status = .syncing
        defer { if status == .syncing { status = .idle } }
        do {
            let guest = ProfileManager.makeContainer(for: nil)
            let context = ModelContext(guest)
            ProgressStore(context: context).migrateLegacyRecordsIfNeeded()
            for event in (try? context.fetch(FetchDescriptor<LearningEvent>())) ?? [] { event.isSynced = false }
            for draft in (try? context.fetch(FetchDescriptor<PoemDraft>())) ?? [] {
                draft.isDirty = true
                draft.serverRevision = 0
            }
            try context.save()
            _ = try await push(context: context, profileID: profileID, client: account.client, cursor: Int.max)

            ProfileManager.shared.switchTo(profileID)
            _ = try await sync(container: ProfileManager.shared.container, profileID: profileID, client: account.client)

            ProgressStore(context: context).resetAll()
            lastSyncedAt = Date()
            refreshPendingCount()
            return true
        } catch {
            status = .failed(error.localizedDescription)
            Telemetry.shared.log("sync_failed", ["reason": .string("guest_migration")])
            return false
        }
    }

    // MARK: Core

    /// One full exchange; returns the number of conflict copies created.
    private func sync(container: ModelContainer, profileID: String, client: APIClient) async throws -> Int {
        let context = container.mainContext
        var cursor = UserDefaults.standard.integer(forKey: Self.cursorKey(profileID))
        var copies = 0
        var more = true
        while more {
            let response = try await push(context: context, profileID: profileID, client: client, cursor: cursor)
            copies += merge(response, context: context)
            cursor = response.cursor
            UserDefaults.standard.set(cursor, forKey: Self.cursorKey(profileID))
            more = response.hasMore ?? false
        }
        return copies
    }

    private func push(context: ModelContext, profileID: String, client: APIClient, cursor: Int) async throws -> Response {
        let events = (try? context.fetch(FetchDescriptor<LearningEvent>(predicate: #Predicate { !$0.isSynced },
                                                                        sortBy: [SortDescriptor(\.at)]))) ?? []
        let batch = Array(events.prefix(500))
        let drafts = (try? context.fetch(FetchDescriptor<PoemDraft>(predicate: #Predicate { $0.isDirty }))) ?? []
        let request = Request(
            cursor: cursor == Int.max ? 0 : cursor,
            events: batch.map { event in
                WireEvent(seq: nil, id: event.id, kind: event.kind, poemID: event.poemID, at: event.at, deviceID: event.deviceID,
                          payload: (try? APIClient.decoder.decode(JSONValue.self, from: event.payload)) ?? .object([:]))
            },
            drafts: drafts.map { draft in
                WireDraft(seq: nil, id: draft.id.uuidString.lowercased(), baseRevision: draft.serverRevision, revision: nil,
                          deleted: draft.pendingDeletion, updatedAt: draft.updatedAt,
                          data: draft.pendingDeletion ? nil : Self.data(of: draft))
            })
        let response: Response = try await client.send("POST", "/v1/profiles/\(profileID)/sync", body: request)
        for event in batch { event.isSynced = true }
        try context.save()
        return response
    }

    /// Applies a sync response. Returns how many conflict copies were made.
    private func merge(_ response: Response, context: ModelContext) -> Int {
        let store = ProgressStore(context: context)
        var copies = 0

        // Events from other devices (our own come back too and are skipped by ID).
        var touchedPoems = Set<String>()
        var newGames: [LearningEvent] = []
        for wire in response.events ?? [] {
            let id = wire.id
            let exists = ((try? context.fetchCount(FetchDescriptor<LearningEvent>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
            guard !exists, let kind = LearningEventKind(rawValue: wire.kind) else { continue }
            let event = LearningEvent(id: wire.id, kind: kind, poemID: wire.poemID, at: wire.at, deviceID: wire.deviceID,
                                      payload: (try? APIClient.encoder.encode(wire.payload)) ?? Data("{}".utf8))
            event.isSynced = true
            context.insert(event)
            if let poemID = wire.poemID { touchedPoems.insert(poemID) }
            if kind == .game { newGames.append(event) }
        }
        try? context.save()
        if !touchedPoems.isEmpty {
            // Replaying in time order keeps the review rule's result identical on every device.
            store.rebuild(poemIDs: touchedPoems)
        }
        for event in newGames { store.apply(event) }

        // Our draft uploads.
        let serverDrafts = Dictionary((response.drafts ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for result in response.draftResults ?? [] {
            guard let uuid = UUID(uuidString: result.id), let local = store.draft(uuid) else { continue }
            if result.status == "applied" {
                local.serverRevision = result.revision
                local.isDirty = false
                if local.pendingDeletion { context.delete(local) }
            } else if !local.pendingDeletion, let server = serverDrafts[result.id], server.data != Self.data(of: local) {
                // Both sides changed: keep ours as a separate copy, then take the server's version below.
                let copy = PoemDraft(title: local.title, themeID: local.themeID, wordIDs: local.wordIDs, lines: local.lines,
                                     at: local.updatedAt)
                copy.mode = local.mode
                copy.form = local.form
                copy.status = local.status
                copy.exampleLineID = local.exampleLineID
                copy.conflictOf = local.id
                context.insert(copy)
                copies += 1
            }
        }

        // Server versions of writing.
        for wire in response.drafts ?? [] {
            guard let uuid = UUID(uuidString: wire.id) else { continue }
            let local = store.draft(uuid)
            if wire.deleted {
                if let local { context.delete(local) }
                continue
            }
            guard let data = wire.data else { continue }
            if let local, !local.isDirty || local.serverRevision != (wire.revision ?? 0) {
                Self.apply(data, revision: wire.revision ?? 0, updatedAt: wire.updatedAt, to: local)
            } else if local == nil {
                let created = PoemDraft(title: data.title, themeID: data.themeID, wordIDs: data.wordIDs, lines: data.lines,
                                        at: data.createdAt)
                created.id = uuid
                Self.apply(data, revision: wire.revision ?? 0, updatedAt: wire.updatedAt, to: created)
                context.insert(created)
            }
        }
        try? context.save()
        return copies
    }

    private static func data(of draft: PoemDraft) -> DraftData {
        DraftData(title: draft.title, themeID: draft.themeID, wordIDs: draft.wordIDs, lines: draft.lines, mode: draft.mode,
                  form: draft.form, status: draft.status, exampleLineID: draft.exampleLineID, createdAt: draft.createdAt,
                  conflictOf: draft.conflictOf?.uuidString.lowercased())
    }

    private static func apply(_ data: DraftData, revision: Int, updatedAt: Date, to draft: PoemDraft) {
        draft.title = data.title
        draft.themeID = data.themeID
        draft.wordIDs = data.wordIDs
        draft.lines = data.lines
        draft.mode = data.mode
        draft.form = data.form
        draft.status = data.status
        draft.exampleLineID = data.exampleLineID
        draft.conflictOf = data.conflictOf.flatMap(UUID.init(uuidString:))
        draft.updatedAt = updatedAt
        draft.serverRevision = revision
        draft.isDirty = false
        draft.pendingDeletion = false
    }
}

/// Arbitrary JSON, so event payloads pass through the server unchanged.
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
