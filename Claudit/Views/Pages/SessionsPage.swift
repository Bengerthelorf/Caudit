import SwiftUI

// MARK: - Sessions

struct SessionsPage: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder = [KeyPathComparator(\SessionInfo.lastTimestamp, order: .reverse)]
    @State private var selectedSessionId: SessionInfo.ID?

    private var filteredSessions: [SessionInfo] {
        var sessions = appState.sessionBreakdown
        if let project = appState.projectFilter {
            sessions = sessions.filter { $0.project == project }
        }
        return sessions.sorted(using: sortOrder)
    }

    var body: some View {
        if !appState.hasLoadedUsage {
            LoadingPlaceholder(message: "Loading sessions…")
        } else if appState.sessionBreakdown.isEmpty {
            ContentUnavailableView("No Sessions", systemImage: "bubble.left.and.bubble.right", description: Text("Session data will appear here once usage is recorded."))
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let project = appState.projectFilter {
                        Button {
                            appState.projectFilter = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text(project)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    UnifiedFilterBar(showTimeRange: false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Table(filteredSessions, selection: $selectedSessionId, sortOrder: $sortOrder) {
                    TableColumn("Session", value: \.slug) { session in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(SourceColor.color(for: session.source, allSources: appState.availableSources))
                                .frame(width: 8, height: 8)
                            Text(session.displayName)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 120, ideal: 200)

                    TableColumn("Project", value: \.project) { session in
                        Text(session.project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(ideal: 120)

                    TableColumn("Duration", value: \.duration) { session in
                        Text(ClauditFormatter.duration(session.duration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 80)

                    TableColumn("Calls", value: \.messageCount) { session in
                        Text("\(session.messageCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 60)

                    TableColumn("Tokens", value: \.totalTokens) { session in
                        Text(ClauditFormatter.tokensWithUnit(session.totalTokens))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 90)

                    TableColumn("Cost", value: \.totalCost) { session in
                        Text(ClauditFormatter.costDetail(session.totalCost))
                            .monospacedDigit()
                            .fontWeight(.medium)
                    }
                    .width(ideal: 80)

                    TableColumn("Last Active", value: \.lastTimestamp) { session in
                        Text(session.lastTimestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                            .foregroundStyle(.secondary)
                    }
                    .width(ideal: 120)
                }
                .onKeyPress(.return) {
                    if let id = selectedSessionId,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        appState.selectedSessionForDetail = session
                        return .handled
                    }
                    return .ignored
                }
                .contextMenu(forSelectionType: SessionInfo.ID.self) { ids in
                    if let id = ids.first,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        Button("View Conversation") {
                            appState.selectedSessionForDetail = session
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first,
                       let session = filteredSessions.first(where: { $0.id == id }) {
                        appState.selectedSessionForDetail = session
                    }
                }
            }
        }
    }
}
