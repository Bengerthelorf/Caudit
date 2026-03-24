import Foundation
import Security

/// Stores console.anthropic.com session key in Keychain and organization ID.
/// Follows the same pattern as SessionCredentialStore but for the API console.
final class ConsoleCredentialStore: @unchecked Sendable {
    static let shared = ConsoleCredentialStore()

    private static let keychainService = "cc.ffitch.Claudit.console"
    private static let keychainAccount = "consoleSessionKey"

    private let lock = NSLock()
    private var _sessionKey: String?
    private var _organizationId: String?
    private var _expiryDate: Date?

    private init() {
        _sessionKey = Self.readKeychain()
        _organizationId = UserDefaults.standard.string(forKey: "consoleOrganizationId")
        if let ts = UserDefaults.standard.object(forKey: "consoleSessionExpiry") as? TimeInterval, ts > 0 {
            _expiryDate = Date(timeIntervalSince1970: ts)
        }
    }

    var sessionKey: String? {
        lock.lock()
        defer { lock.unlock() }
        if let expiry = _expiryDate, expiry < Date() { return nil }
        return _sessionKey
    }

    var organizationId: String? {
        lock.lock()
        defer { lock.unlock() }
        return _organizationId
    }

    var expiryDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _expiryDate
    }

    var isConfigured: Bool {
        sessionKey != nil && organizationId != nil
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date()
    }

    func save(sessionKey: String, organizationId: String, expiryDate: Date?) {
        lock.lock()
        _sessionKey = sessionKey
        _organizationId = organizationId
        _expiryDate = expiryDate
        lock.unlock()

        Self.writeKeychain(sessionKey)
        UserDefaults.standard.set(organizationId, forKey: "consoleOrganizationId")
        if let expiry = expiryDate {
            UserDefaults.standard.set(expiry.timeIntervalSince1970, forKey: "consoleSessionExpiry")
        } else {
            UserDefaults.standard.removeObject(forKey: "consoleSessionExpiry")
        }
    }

    func clear() {
        lock.lock()
        _sessionKey = nil
        _organizationId = nil
        _expiryDate = nil
        lock.unlock()

        Self.deleteKeychain()
        UserDefaults.standard.removeObject(forKey: "consoleOrganizationId")
        UserDefaults.standard.removeObject(forKey: "consoleSessionExpiry")
    }

    // MARK: - Keychain

    private static func writeKeychain(_ value: String) {
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: value.data(using: .utf8)!
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Fetch organizations from console.anthropic.com using the stored session key.
    func fetchOrganizations() async throws -> [(id: String, name: String)] {
        guard let key = sessionKey else { throw ConsoleBillingError.noCredentials }

        let url = URL(string: "https://console.anthropic.com/api/organizations")!
        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ConsoleBillingError.sessionExpired
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ConsoleBillingError.invalidResponse
        }

        // Response could be an array of orgs or an object with a "data" key
        let orgs: [[String: Any]]
        if let array = json as? [[String: Any]] {
            orgs = array
        } else if let dict = json as? [String: Any], let data = dict["data"] as? [[String: Any]] {
            orgs = data
        } else {
            throw ConsoleBillingError.invalidResponse
        }

        return orgs.compactMap { org in
            guard let id = org["id"] as? String ?? org["uuid"] as? String,
                  let name = org["name"] as? String else { return nil }
            return (id: id, name: name)
        }
    }
}

// MARK: - Errors

enum ConsoleBillingError: LocalizedError, Equatable {
    case noCredentials
    case sessionExpired
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No console credentials. Sign in via Settings."
        case .sessionExpired:
            return "Console session expired. Sign in again via Settings."
        case .invalidResponse:
            return "Invalid console API response."
        case .httpError(let code):
            return "Console API HTTP \(code)"
        }
    }
}
