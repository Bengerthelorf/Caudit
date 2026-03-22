import Foundation

struct SessionDetail: Sendable {
    let sessionId: String
    let messages: [SessionMessage]
}

struct SessionMessage: Identifiable, Sendable {
    let id: String
    let role: MessageRole
    let timestamp: Date
    let content: [SessionContentItem]

    enum MessageRole: String, Sendable {
        case user
        case assistant
    }

    var isToolResultOnly: Bool {
        guard role == .user else { return false }
        return content.allSatisfy {
            switch $0 {
            case .toolResult: return true
            default: return false
            }
        }
    }
}

enum SessionContentItem: Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(id: String, content: String, isError: Bool)
}
