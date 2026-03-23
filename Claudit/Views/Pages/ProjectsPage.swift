import SwiftUI

// MARK: - Projects

struct ProjectsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\ProjectUsage.totalCost, order: .reverse)]
    @State private var selectedProjectId: ProjectUsage.ID?

    private var sortedProjects: [ProjectUsage] {
        appState.projectBreakdown.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading projects…")
        } else if appState.projectBreakdown.isEmpty {
            ContentUnavailableView("No Projects", systemImage: "folder", description: Text("Project data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                UnifiedFilterBar(showTimeRange: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Table(sortedProjects, selection: $selectedProjectId, sortOrder: $sortOrder) {
                    TableColumn("Project", value: \.project) { project in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SourceColor.color(for: project.source, allSources: appState.availableSources))
                                .frame(width: 8, height: 8)
                            Text(project.project)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 150, ideal: 250)

                    TableColumn("Source", value: \.source) { project in
                        Text(project.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Tokens", value: \.totalTokens) { project in
                        Text(ClauditFormatter.tokensWithUnit(project.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { project in
                        Text(ClauditFormatter.costDetail(project.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)

                    TableColumn("Last Active", value: \.lastActive) { project in
                        Text(project.lastActive.formatted(.dateTime.month(.abbreviated).day()))
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)
                }
                .contextMenu(forSelectionType: ProjectUsage.ID.self) { ids in
                    if let id = ids.first,
                       let project = sortedProjects.first(where: { $0.id == id }) {
                        Button("View Sessions") {
                            appState.projectFilter = project.project
                            appState.selectedTab = .sessions
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let project = sortedProjects.first(where: { $0.id == id }) {
                        appState.projectFilter = project.project
                        appState.selectedTab = .sessions
                    }
                }
            }
        }
    }
}
