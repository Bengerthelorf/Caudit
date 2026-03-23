import SwiftUI

// MARK: - Tools

struct ToolsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ToolUsageEntry.usageCount, order: .reverse)]

    private var sortedTools: [ToolUsageEntry] {
        appState.toolBreakdown.sorted(using: sortOrder)
    }

    private var totalCalls: Int {
        appState.toolBreakdown.reduce(0) { $0 + $1.usageCount }
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading tool data…")
        } else if appState.toolBreakdown.isEmpty {
            ContentUnavailableView("No Tool Data", systemImage: "wrench.and.screwdriver", description: Text("Tool usage data will appear here once recorded."))
        } else {
            VStack(spacing: 0) {
                UnifiedFilterBar(showTimeRange: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedTools, sortOrder: $sortOrder) {
                    TableColumn("Tool", value: \.name) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: ClauditFormatter.toolIcon(entry.name))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(entry.name)
                                .fontWeight(.medium)
                        }
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Usage Count", value: \.usageCount) { entry in
                        Text("\(entry.usageCount)")
                            .monospacedDigit()
                    }
                    .width(ideal: 100)

                    TableColumn("Percentage") { entry in
                        let pct = totalCalls > 0 ? Double(entry.usageCount) / Double(totalCalls) * 100 : 0
                        HStack(spacing: 8) {
                            ProgressView(value: Double(entry.usageCount), total: Double(max(totalCalls, 1)))
                                .frame(width: 80)
                            Text(String(format: "%.1f%%", pct))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    .width(ideal: 160)
                }
            }
        }
    }
}
