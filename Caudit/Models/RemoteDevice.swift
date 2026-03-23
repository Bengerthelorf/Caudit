import Foundation

struct RemoteDevice: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sshHost: String
    var claudePath: String = "~/.claude"
    var openClawPaths: [String] = ["~/.openclaw"]
    var identityFile: String = ""
    var usePassword: Bool = false
    var isEnabled: Bool = true
}

/// Store and retrieve SSH passwords in the macOS Keychain, keyed by device ID.
enum SSHPasswordStore {
    private static let service = "homes.snaix.Caudit.ssh"

    static func save(password: String, for deviceId: UUID) {
        let account = deviceId.uuidString
        delete(for: deviceId)
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(for deviceId: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for deviceId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum RemoteDeviceStatus {
    case fetching
    case success(Int)
    case failed(String)
}
