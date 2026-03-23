import Foundation

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "Month"
    case allTime = "All Time"

    var id: String { rawValue }

    var filterStart: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        switch self {
        case .today: return startOfToday
        case .week: return calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        case .month: return calendar.date(byAdding: .day, value: -30, to: startOfToday)!
        case .allTime: return .distantPast
        }
    }
}

struct DashboardFilter: Equatable {
    var timeRange: TimeRange = .month
    var selectedSources: Set<String> = []
}
