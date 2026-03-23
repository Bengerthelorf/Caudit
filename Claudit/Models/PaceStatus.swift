import SwiftUI

/// 6-tier pace projection based on current usage rate vs. time elapsed in the window.
enum PaceStatus: String, Sendable, CaseIterable {
    case comfortable  // projected < 50%
    case onTrack      // 50% - 75%
    case warming      // 75% - 90%
    case pressing     // 90% - 100%
    case critical     // 100% - 120%
    case runaway      // > 120%

    var label: String {
        switch self {
        case .comfortable: return "Comfortable"
        case .onTrack:     return "On Track"
        case .warming:     return "Warming"
        case .pressing:    return "Pressing"
        case .critical:    return "Critical"
        case .runaway:     return "Runaway"
        }
    }

    var color: Color {
        switch self {
        case .comfortable: return .green
        case .onTrack:     return .teal
        case .warming:     return .yellow
        case .pressing:    return .orange
        case .critical:    return .red
        case .runaway:     return .purple
        }
    }
}
