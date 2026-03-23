import SwiftUI

struct ClaudeStatus: Sendable {
    enum Indicator: String, Sendable {
        case none
        case minor
        case major
        case critical
        case unknown

        var color: Color {
            switch self {
            case .none:     return .green
            case .minor:    return .yellow
            case .major:    return .orange
            case .critical: return .red
            case .unknown:  return .gray
            }
        }

        var label: String {
            switch self {
            case .none:     return "Operational"
            case .minor:    return "Minor Issues"
            case .major:    return "Major Outage"
            case .critical: return "Critical Outage"
            case .unknown:  return "Unknown"
            }
        }
    }

    let indicator: Indicator
    let description: String
    let updatedAt: Date?
}
