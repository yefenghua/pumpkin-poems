import Foundation

/// Anonymous trial statistics (phase-2 §8, L07). Events carry the install ID, content and rule versions and a few
/// flags — never poem drafts, free-text input or identity. Queued on disk and sent in batches; a send that fails
/// stays queued, and the server drops duplicates by event ID.
final class Telemetry {
    static let shared = Telemetry()

    enum Value: Codable, Hashable {
        case string(String), int(Int), bool(Bool)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            case .bool(let value): try container.encode(value)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Int.self) { self = .int(value) }
            else { self = .string(try container.decode(String.self)) }
        }
    }

    struct Event: Codable {
        let id: String
        let name: String
        let at: Date
        let contentVersion: String
        let ruleVersion: Int
        let props: [String: Value]
    }

    private struct Batch: Encodable {
        let installID: String
        let appVersion: String
        let events: [Event]
    }

    private let file = URL.applicationSupportDirectory.appending(path: "telemetry-queue.json")
    private var queue: [Event]
    private var isFlushing = false
    private let maxQueued = 2000

    private init() {
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        queue = (try? APIClient.decoder.decode([Event].self, from: Data(contentsOf: file))) ?? []
    }

    func log(_ name: String, _ props: [String: Value] = [:]) {
        queue.append(Event(id: UUID().uuidString.lowercased(), name: name, at: Date(),
                           contentVersion: PoemLibrary.shared.version, ruleVersion: ReviewScheduler.ruleVersion,
                           props: props))
        if queue.count > maxQueued { queue.removeFirst(queue.count - maxQueued) }
        persist()
    }

    /// `app_day_opened` once per calendar day, with the number of due reviews (for 到期复习参与率).
    func logDayOpened(dueCount: Int) {
        let key = "telemetry.lastDayOpened"
        let today = Calendar.current.startOfDay(for: AppClock.now)
        if let last = UserDefaults.standard.object(forKey: key) as? Date, last >= today { return }
        UserDefaults.standard.set(today, forKey: key)
        log("app_day_opened", ["dueCount": .int(dueCount)])
    }

    func flush() async {
        guard !isFlushing, !queue.isEmpty, ServerConfig.baseURL != nil else { return }
        isFlushing = true
        defer { isFlushing = false }
        let batch = Array(queue.prefix(200))
        do {
            try await APIClient().send("POST", "/v1/events",
                                       body: Batch(installID: ServerConfig.installID, appVersion: ServerConfig.appVersion,
                                                   events: batch))
            let sent = Set(batch.map(\.id))
            queue.removeAll { sent.contains($0.id) }
            persist()
        } catch {
            // Stays queued for the next foreground.
        }
    }

    private func persist() {
        try? APIClient.encoder.encode(queue).write(to: file, options: .atomic)
    }
}
