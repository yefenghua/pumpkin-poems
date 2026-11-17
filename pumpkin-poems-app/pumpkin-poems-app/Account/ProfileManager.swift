import Foundation
import Observation
import SwiftData

/// A child's profile under the parent account: a nickname and an optional stage, nothing else.
struct ChildProfile: Codable, Hashable, Identifiable {
    let id: String
    var nickname: String
    var stage: String?
    var createdAt: Date?
}

/// Which learner is using the app. Each learner has a separate SwiftData store on disk — the guest uses the
/// phase-1 default store, each child profile its own file — so switching profiles, signing out or handing the
/// device to someone else can never show another learner's records.
@Observable
final class ProfileManager {
    static let shared = ProfileManager()

    private static let currentKey = "profiles.current"

    /// `nil` is the guest (no account), which is always available.
    private(set) var currentProfileID: String?
    private(set) var container: ModelContainer

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.currentKey)
        currentProfileID = stored
        container = Self.makeContainer(for: stored)
        prepare(container)
    }

    var isGuest: Bool { currentProfileID == nil }

    /// Re-creates the view tree when the learner changes, so no screen keeps the previous store's objects.
    var identity: String { currentProfileID ?? "guest" }

    func switchTo(_ profileID: String?) {
        guard profileID != currentProfileID else { return }
        currentProfileID = profileID
        UserDefaults.standard.set(profileID, forKey: Self.currentKey)
        container = Self.makeContainer(for: profileID)
        prepare(container)
    }

    /// Removes a child profile's local store (sign-out, profile deletion). Its data stays in the account.
    func deleteLocalStore(for profileID: String) {
        if profileID == currentProfileID { switchTo(nil) }
        let base = Self.storeURL(for: profileID)
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: base.path + suffix))
        }
        SyncEngine.forgetCursor(for: profileID)
    }

    /// A container for a learner other than the current one (guest migration reads the guest store this way).
    static func makeContainer(for profileID: String?) -> ModelContainer {
        let schema = Schema(ProgressSchema.models)
        let configuration: ModelConfiguration
        if let profileID {
            try? FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: storeURL(for: profileID))
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not open the learning store: \(error)")
        }
    }

    private static var profilesDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Profiles", directoryHint: .isDirectory)
    }

    private static func storeURL(for profileID: String) -> URL {
        profilesDirectory.appending(path: "\(profileID).store")
    }

    private func prepare(_ container: ModelContainer) {
        let store = ProgressStore(context: container.mainContext)
        store.migrateLegacyRecordsIfNeeded()
        store.purgeDeletedDrafts()
    }
}
