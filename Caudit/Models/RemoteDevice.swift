import Foundation

struct RemoteDevice: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sshHost: String
    var claudePath: String = "~/.claude"
    var identityFile: String = ""
    var isEnabled: Bool = true
}

enum RemoteDeviceStatus {
    case fetching
    case success(Int)
    case failed(String)
}
