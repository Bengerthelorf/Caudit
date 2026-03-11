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
}

enum SessionContentItem: Identifiable, Sendable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: String)
    case toolResult(id: String, content: String, isError: Bool)

    var id: String {
        switch self {
        case .text(let s): return "text-\(s.prefix(20).hashValue)"
        case .thinking(let s): return "think-\(s.prefix(20).hashValue)"
        case .toolUse(let id, _, _): return "tool-\(id)"
        case .toolResult(let id, _, _): return "result-\(id)"
        }
    }
}
