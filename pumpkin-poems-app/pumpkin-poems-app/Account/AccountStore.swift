import Foundation
import Observation

/// The parent account (L08). Children never sign in: a parent registers an account ID + password in 家长区域 and
/// manages child profiles there. Learning without an account always works; the guest store stays on the device.
///
/// The server keeps no e-mail or phone, so a forgotten password cannot be reset; the UI says so before registering.
@Observable
final class AccountStore {
    static let shared = AccountStore()

    private enum Key {
        static let token = "accessToken"
        static let parentID = "account.parentID"
        static let accountID = "account.accountID"
        static let profiles = "account.profiles"
    }

    private(set) var parentID: String?
    private(set) var accountID: String?
    private(set) var profiles: [ChildProfile]
    /// Server error code of the last failed call (`invalid_credentials`, `account_id_taken`, …) for the UI to translate.
    private(set) var lastErrorCode: String?
    private(set) var lastError: String?
    private(set) var isWorking = false

    @ObservationIgnored private var token: String?

    private init() {
        token = Keychain.read(Key.token)
        parentID = UserDefaults.standard.string(forKey: Key.parentID)
        accountID = UserDefaults.standard.string(forKey: Key.accountID)
        profiles = (UserDefaults.standard.data(forKey: Key.profiles))
            .flatMap { try? JSONDecoder().decode([ChildProfile].self, from: $0) } ?? []
        if token == nil { parentID = nil }
    }

    var isSignedIn: Bool { token != nil && parentID != nil }

    var client: APIClient { APIClient(token: token) }

    func profile(_ id: String?) -> ChildProfile? { profiles.first { $0.id == id } }

    // MARK: Sign-in

    private struct AuthResponse: Decodable {
        let accessToken: String
        let parentID: String
        let accountID: String
    }

    /// Creates the account and signs in. Errors: `invalid_account_id`, `weak_password`, `account_id_taken`.
    func register(accountID: String, password: String) async {
        await authenticate {
            try await APIClient().send("POST", "/v1/auth/register", body: Credentials(accountID: accountID, password: password))
        }
    }

    /// Errors: `invalid_credentials` (unknown account or wrong password), `too_many_attempts`.
    func signIn(accountID: String, password: String) async {
        await authenticate {
            try await APIClient().send("POST", "/v1/auth/login", body: Credentials(accountID: accountID, password: password))
        }
    }

    private func authenticate(_ call: () async throws -> AuthResponse) async {
        await run {
            let response = try await call()
            token = response.accessToken
            parentID = response.parentID
            accountID = response.accountID
            Keychain.write(Key.token, response.accessToken)
            UserDefaults.standard.set(response.parentID, forKey: Key.parentID)
            UserDefaults.standard.set(response.accountID, forKey: Key.accountID)
            try await refreshProfiles()
        }
    }

    /// Changes the password; every other device is signed out by the server. Errors: `wrong_password`, `weak_password`.
    func changePassword(current: String, new: String) async -> Bool {
        struct Body: Encodable { let currentPassword: String; let newPassword: String }
        var changed = false
        await run {
            try await client.send("POST", "/v1/auth/password", body: Body(currentPassword: current, newPassword: new))
            changed = true
        }
        return changed
    }

    /// Signs out on this device: the token is revoked (best effort), the account's profile stores are removed
    /// locally (their data is in the account) and the app returns to the guest, so the next person cannot see them.
    func signOut() {
        let revoke = client
        Task { try? await revoke.post("/v1/auth/logout") }
        for profile in profiles {
            ProfileManager.shared.deleteLocalStore(for: profile.id)
        }
        ProfileManager.shared.switchTo(nil)
        token = nil
        parentID = nil
        profiles = []
        Keychain.write(Key.token, nil)
        UserDefaults.standard.removeObject(forKey: Key.parentID)
        UserDefaults.standard.removeObject(forKey: Key.profiles)
    }

    /// Deletes the parent account with every profile and all cloud data, then signs out.
    func deleteAccount() async -> Bool {
        var deleted = false
        await run {
            try await client.delete("/v1/account")
            deleted = true
        }
        if deleted { signOut() }
        return deleted
    }

    // MARK: Profiles

    private struct ProfileList: Decodable { let profiles: [ChildProfile] }

    func refreshProfiles() async throws {
        let list: ProfileList = try await client.get("/v1/profiles")
        setProfiles(list.profiles)
    }

    @discardableResult
    func createProfile(nickname: String, stage: String?) async -> ChildProfile? {
        struct Body: Encodable { let id: String; let nickname: String; let stage: String? }
        var created: ChildProfile?
        await run {
            let body = Body(id: UUID().uuidString.lowercased(), nickname: nickname, stage: stage)
            let profile: ChildProfile = try await client.send("POST", "/v1/profiles", body: body)
            setProfiles(profiles.filter { $0.id != profile.id } + [profile])
            created = profile
        }
        return created
    }

    func renameProfile(_ id: String, nickname: String) async {
        struct Body: Encodable { let nickname: String }
        await run {
            let profile: ChildProfile = try await client.send("PATCH", "/v1/profiles/\(id)", body: Body(nickname: nickname))
            setProfiles(profiles.map { $0.id == id ? profile : $0 })
        }
    }

    /// Deletes the profile and all its cloud records, then its local store.
    func deleteProfile(_ id: String) async {
        await run {
            try await client.delete("/v1/profiles/\(id)")
            ProfileManager.shared.deleteLocalStore(for: id)
            setProfiles(profiles.filter { $0.id != id })
        }
    }

    func clearError() {
        lastError = nil
        lastErrorCode = nil
    }

    /// A 401 means the token expired or the account is gone: back to "not signed in", local data kept.
    func handleUnauthorized() {
        token = nil
        Keychain.write(Key.token, nil)
        parentID = nil
        UserDefaults.standard.removeObject(forKey: Key.parentID)
    }

    private func setProfiles(_ list: [ChildProfile]) {
        profiles = list
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: Key.profiles)
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        lastError = nil
        lastErrorCode = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch APIError.unauthorized {
            // A 401 on sign-in is "wrong account or password"; anywhere else the token has expired.
            if isSignedIn {
                handleUnauthorized()
                lastErrorCode = "unauthorized"
            } else {
                lastErrorCode = "invalid_credentials"
            }
            lastError = lastErrorCode
        } catch APIError.server(_, let code, let message) {
            lastErrorCode = code
            lastError = message.isEmpty ? code : message
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// Request body of `/v1/auth/register` and `/v1/auth/login`. File scope keeps the conformance out of the main actor.
private struct Credentials: Encodable {
    let accountID: String
    let password: String
}
