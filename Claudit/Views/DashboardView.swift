import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case activity = "Activity"
    case sessions = "Sessions"
    case projects = "Projects"
    case models = "Models"
    case tools = "Tools"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .activity: "chart.dots.scatter"
        case .sessions: "bubble.left.and.bubble.right"
        case .projects: "folder"
        case .models: "cpu"
        case .tools: "wrench.and.screwdriver"
        }
    }
}

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    // MARK: - Back/Forward History

    @State private var backStack: [(tab: DashboardTab?, session: SessionInfo?)] = []
    @State private var forwardStack: [(tab: DashboardTab?, session: SessionInfo?)] = []
    @State private var isNavigating = false

    private func pushHistory() {
        backStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        forwardStack.removeAll()
    }

    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        isNavigating = true
        forwardStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        appState.selectedTab = previous.tab
        appState.selectedSessionForDetail = previous.session
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        isNavigating = true
        backStack.append((tab: appState.selectedTab, session: appState.selectedSessionForDetail))
        appState.selectedTab = next.tab
        appState.selectedSessionForDetail = next.session
    }

    private var tabBinding: Binding<DashboardTab?> {
        Binding(
            get: { appState.selectedTab },
            set: { newTab in
                guard newTab != appState.selectedTab else { return }
                pushHistory()
                appState.selectedTab = newTab
                appState.selectedSessionForDetail = nil
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(DashboardTab.allCases, selection: tabBinding) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Claudit")
            .frame(minWidth: 200, idealWidth: 300)
        } detail: {
            NavigationStack {
                Group {
                    if let session = appState.selectedSessionForDetail {
                        SessionDetailView(session: session)
                            .id(session.sessionId)
                            .navigationTitle(session.displayName)
                            .navigationSubtitle(
                                "\(session.project) · \(ClauditFormatter.duration(session.duration)) · \(ClauditFormatter.costDetail(session.totalCost)) · \(ClauditFormatter.tokensWithUnit(session.totalTokens))"
                            )
                    } else {
                        tabContent
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        ControlGroup {
                            Button(action: goBack) {
                                Label("Back", systemImage: "chevron.left")
                            }
                            .disabled(backStack.isEmpty)

                            Button(action: goForward) {
                                Label("Forward", systemImage: "chevron.right")
                            }
                            .disabled(forwardStack.isEmpty)
                        }
                        .controlGroupStyle(.navigation)
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Export as JSON") {
                                let content = ExportService.exportRecords(appState.filteredRecords, format: .json)
                                ExportService.saveToFile(content: content, format: .json)
                            }
                            Button("Export as CSV") {
                                let content = ExportService.exportRecords(appState.filteredRecords, format: .csv)
                                ExportService.saveToFile(content: content, format: .csv)
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .help("Export usage data")
                    }

                    if appState.selectedSessionForDetail != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                if let session = appState.selectedSessionForDetail {
                                    AppDelegate.shared.openSessionWindow(session: session)
                                }
                            } label: {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .help("Open in separate window")
                        }
                    }
                }
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .onChange(of: appState.selectedSessionForDetail) { oldValue, newValue in
            if isNavigating {
                isNavigating = false
                return
            }
            guard oldValue != newValue, newValue != nil else { return }
            backStack.append((tab: appState.selectedTab, session: oldValue))
            forwardStack.removeAll()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch appState.selectedTab {
        case .overview, .none:
            OverviewPage()
                .navigationTitle("Overview")
        case .activity:
            ActivityPage()
                .navigationTitle("Activity")
        case .sessions:
            SessionsPage()
                .navigationTitle("Sessions")
        case .projects:
            ProjectsPage()
                .navigationTitle("Projects")
        case .models:
            ModelsPage()
                .navigationTitle("Models")
        case .tools:
            ToolsPage()
                .navigationTitle("Tools")
        }
    }
}
