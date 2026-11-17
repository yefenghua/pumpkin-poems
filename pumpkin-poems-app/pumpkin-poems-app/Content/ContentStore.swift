import CryptoKit
import Foundation
import Observation

/// One theme pack as listed in the published manifest (docs/api/phase2-api.md §1).
struct ContentPackInfo: Codable, Hashable, Identifiable {
    let id: String
    let version: String
    let title: LocalizedText
    let summary: LocalizedText
    let poemCount: Int
    let size: Int
    let sha256: String
    let url: String
}

struct ContentManifest: Codable {
    let release: String
    let formatVersion: Int
    let packs: [ContentPackInfo]
    let withdrawnQuestions: [String]
}

extension LocalizedText: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hant, forKey: .hant)
        try container.encode(hans, forKey: .hans)
    }
}

/// Downloaded packs and the library built from them. The bundled base pack is always loaded; a pack is
/// switched in only after its size and SHA-256 match the manifest and it decodes, so a failed or
/// interrupted download leaves the previous version in place. Removing a pack frees its file only:
/// learning records, favourites and writing are keyed by stable IDs and stay.
@Observable
final class ContentStore {
    static let shared = ContentStore()

    enum PackState: Equatable {
        case notDownloaded
        case downloading(Double)
        case installed(version: String)
        case updateAvailable(installed: String)
        case failed(String)
    }

    private struct InstalledPack: Codable {
        let version: String
        let file: String
        let size: Int
    }

    private(set) var library: PoemLibrary
    private(set) var manifest: ContentManifest?
    /// Set while the manifest cannot be fetched; the cached manifest and installed packs keep working.
    private(set) var manifestError: String?
    private(set) var isRefreshing = false
    private var downloads: [String: Double] = [:]
    private var failures: [String: String] = [:]

    @ObservationIgnored private let base: PoemContent
    @ObservationIgnored private var installed: [String: InstalledPack]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        let root = directory ?? URL.applicationSupportDirectory.appending(path: "ContentPacks", directoryHint: .isDirectory)
        self.directory = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        base = PoemLibrary.loadBundledContent()
        installed = (try? JSONDecoder().decode([String: InstalledPack].self,
                                               from: Data(contentsOf: root.appending(path: "installed.json")))) ?? [:]
        manifest = try? JSONDecoder().decode(ContentManifest.self, from: Data(contentsOf: root.appending(path: "manifest.json")))
        library = PoemLibrary(content: base)
        rebuild()
    }

    // MARK: Queries

    /// Packs to show in 诗库: everything in the manifest, plus installed packs the manifest no longer lists.
    var packs: [ContentPackInfo] {
        manifest?.packs ?? []
    }

    var installedPackIDs: [String] { installed.keys.sorted() }

    func state(of pack: ContentPackInfo) -> PackState {
        if let progress = downloads[pack.id] { return .downloading(progress) }
        if let failure = failures[pack.id] { return .failed(failure) }
        guard let local = installed[pack.id] else { return .notDownloaded }
        return local.version == pack.version ? .installed(version: local.version) : .updateAvailable(installed: local.version)
    }

    func isInstalled(_ packID: String) -> Bool { packID == "base" || installed[packID] != nil }

    /// Free space for the "空间提示" before downloading.
    var availableCapacity: Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: Actions

    func refreshManifest() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fetched: ContentManifest = try await APIClient().get("/v1/content/manifest")
            manifest = fetched
            manifestError = nil
            try? JSONEncoder().encode(fetched).write(to: directory.appending(path: "manifest.json"), options: .atomic)
            rebuild()
        } catch {
            manifestError = error.localizedDescription
        }
    }

    /// Downloads (or updates) a pack, verifies it, then switches it in. Failures keep the old version.
    func download(_ pack: ContentPackInfo) async {
        guard downloads[pack.id] == nil else { return }
        failures[pack.id] = nil
        downloads[pack.id] = 0
        defer { downloads[pack.id] = nil }
        do {
            let data = try await fetch(pack)
            guard data.count == pack.size else { throw PackError.sizeMismatch }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == pack.sha256.lowercased() else { throw PackError.checksumMismatch }
            let content = try JSONDecoder().decode(PoemContent.self, from: data)
            guard content.packID == pack.id, content.formatVersion == 2 else { throw PackError.wrongPack }

            let file = "\(pack.id)-\(pack.version).json"
            try data.write(to: directory.appending(path: file), options: .atomic)
            let previous = installed[pack.id]
            installed[pack.id] = InstalledPack(version: pack.version, file: file, size: data.count)
            try saveIndex()
            if let previous, previous.file != file {
                try? fileManager.removeItem(at: directory.appending(path: previous.file))
            }
            rebuild()
            Telemetry.shared.log("content_pack_installed", ["packID": .string(pack.id), "packVersion": .string(pack.version)])
        } catch {
            failures[pack.id] = (error as? PackError)?.message ?? error.localizedDescription
            Telemetry.shared.log("content_download_failed", ["packID": .string(pack.id), "reason": .string(String(describing: error))])
        }
    }

    func remove(packID: String) {
        guard let local = installed.removeValue(forKey: packID) else { return }
        try? saveIndex()
        try? fileManager.removeItem(at: directory.appending(path: local.file))
        rebuild()
    }

    func clearFailure(_ packID: String) { failures[packID] = nil }

    // MARK: Private

    private enum PackError: Error {
        case sizeMismatch, checksumMismatch, wrongPack

        var message: String {
            switch self {
            case .sizeMismatch: "size mismatch"
            case .checksumMismatch: "checksum mismatch"
            case .wrongPack: "unexpected pack"
            }
        }
    }

    private func fetch(_ pack: ContentPackInfo) async throws -> Data {
        let url = try APIClient().url(pack.url)
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.invalidResponse }
        var data = Data()
        data.reserveCapacity(pack.size)
        for try await byte in bytes {
            data.append(byte)
            if data.count % 16_384 == 0 {
                downloads[pack.id] = min(0.99, Double(data.count) / Double(max(pack.size, 1)))
            }
        }
        return data
    }

    private func saveIndex() throws {
        try JSONEncoder().encode(installed).write(to: directory.appending(path: "installed.json"), options: .atomic)
    }

    private func rebuild() {
        var packs = [base]
        for (packID, local) in installed.sorted(by: { $0.key < $1.key }) {
            guard let data = try? Data(contentsOf: directory.appending(path: local.file)),
                  let content = try? JSONDecoder().decode(PoemContent.self, from: data) else {
                // A damaged file is dropped from the index; the learner can download it again.
                installed[packID] = nil
                try? saveIndex()
                continue
            }
            packs.append(content)
        }
        library = PoemLibrary(packs: packs, withdrawnQuestions: Set(manifest?.withdrawnQuestions ?? []))
    }
}
