import SwiftUI

// MARK: - Models

struct ModelsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ModelUsageEntry.totalCost, order: .reverse)]

    private var sortedModels: [ModelUsageEntry] {
        appState.modelBreakdown.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading models…")
        } else if appState.modelBreakdown.isEmpty {
            ContentUnavailableView("No Models", systemImage: "cpu", description: Text("Model data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                UnifiedFilterBar(showTimeRange: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedModels, sortOrder: $sortOrder) {
                    TableColumn("Model", value: \.model) { entry in
                        Text(entry.model)
                            .fontWeight(.medium)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Input", value: \.inputTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.inputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Output", value: \.outputTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.outputTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cache", value: \.cacheTokens) { entry in
                        Text(ClauditFormatter.tokens(entry.cacheTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Cost", value: \.totalCost) { entry in
                        Text(ClauditFormatter.costDetail(entry.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)
                }
            }
        }
    }
}
