import Foundation

/// Where the Go service lives. Empty means "no server": everything keeps working offline.
/// Debug builds default to a service on this Mac (`DEV_AUTH=1 go run ./cmd/server` in pumpkin-poems-backend).
enum ServerConfig {
    static let baseURLKey = "server.baseURL"

    static var baseURL: URL? {
        let stored = UserDefaults.standard.string(forKey: baseURLKey)
        #if DEBUG
        let value = stored ?? "http://127.0.0.1:8080"
        #else
        let value = stored ?? ""
        #endif
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    /// Anonymous ID for trial statistics, created on first launch; never tied to a real identity.
    static var installID: String {
        let key = "telemetry.installID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    /// Identifies this device in synced learning events.
    static var deviceID: String {
        let key = "sync.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: key)
        return created
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case server(status: Int, code: String, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Server not configured"
        case .unauthorized: "Unauthorized"
        case .server(let status, let code, let message): "\(status) \(code): \(message)"
        case .invalidResponse: "Invalid response"
        }
    }
}

/// Small JSON client for the API in docs/api/phase2-api.md.
struct APIClient {
    var baseURL: URL? = ServerConfig.baseURL
    var token: String?
    var session: URLSession = .shared

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Fractional seconds keep the replay order of learning events identical on every device.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.withFractions.string(from: date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = ISO8601DateFormatter.withFractions.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(text)")
        }
        return decoder
    }()

    func url(_ path: String) throws -> URL {
        guard let baseURL else { throw APIError.notConfigured }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw APIError.invalidResponse }
        return url
    }

    func get<Response: Decodable>(_ path: String, as type: Response.Type = Response.self) async throws -> Response {
        try await send(request(path, method: "GET"))
    }

    func send<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body,
                                                    as type: Response.Type = Response.self) async throws -> Response {
        var request = try request(path, method: method)
        request.httpBody = try Self.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    /// For endpoints that answer with no useful body (204, `{}`).
    func send<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        let _: Empty = try await send(method, path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: Empty = try await send(request(path, method: "DELETE"))
    }

    /// POST without a body, e.g. logout.
    func post(_ path: String) async throws {
        let _: Empty = try await send(request(path, method: "POST"))
    }

    /// Raw bytes, e.g. a content pack, so the caller can verify size and checksum before decoding.
    func data(_ path: String) async throws -> Data {
        let (data, response) = try await session.data(for: request(path, method: "GET"))
        try check(response, data: data)
        return data
    }

    private func request(_ path: String, method: String) throws -> URLRequest {
        var request = URLRequest(url: try url(path), timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try check(response, data: data)
        if Response.self == Empty.self { return Empty() as! Response }
        return try Self.decoder.decode(Response.self, from: data)
    }

    private func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let body = try? Self.decoder.decode(ErrorBody.self, from: data)
            throw APIError.server(status: http.statusCode, code: body?.error.code ?? "http_\(http.statusCode)",
                                  message: body?.error.message ?? "")
        }
    }

    struct Empty: Codable {}

    private struct ErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
        }
        let error: Detail
    }
}

extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
