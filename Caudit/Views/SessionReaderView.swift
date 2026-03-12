import SwiftUI

struct SessionReaderView: View {
    @Environment(AppState.self) private var appState
    let session: SessionInfo

    @State private var detail: SessionDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var currentMatchIndex = 0
    @State private var scrollPosition = ScrollPosition()
    @FocusState private var isSearchFieldFocused: Bool
    private let service = SessionDetailService()

    private var allMessages: [SessionMessage] {
        detail?.messages ?? []
    }

    private var matchingIndices: [Int] {
        guard !searchText.isEmpty else { return [] }
        return allMessages.indices.filter { idx in
            allMessages[idx].content.contains { item in
                switch item {
                case .text(let t): t.localizedCaseInsensitiveContains(searchText)
                case .thinking(let t): t.localizedCaseInsensitiveContains(searchText)
                case .toolUse(_, let n, let i):
                    n.localizedCaseInsensitiveContains(searchText) ||
                    i.localizedCaseInsensitiveContains(searchText)
                case .toolResult(_, let c, _): c.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }

    private func gotoNextMatch() {
        guard !matchingIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchingIndices.count
        scrollToCurrentMatch()
    }

    private func gotoPreviousMatch() {
        guard !matchingIndices.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchingIndices.count) % matchingIndices.count
        scrollToCurrentMatch()
    }

    private func scrollToCurrentMatch() {
        guard !matchingIndices.isEmpty else { return }
        let idx = min(currentMatchIndex, matchingIndices.count - 1)
        let messageId = allMessages[matchingIndices[idx]].id
        scrollPosition.scrollTo(id: messageId, anchor: .center)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(session.project)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(CauditFormatter.duration(session.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(CauditFormatter.costDetail(session.totalCost))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(CauditFormatter.tokensWithUnit(session.totalTokens))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Search bar
            if isSearching {
                SessionSearchBar(
                    searchText: $searchText,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    currentMatch: currentMatchIndex,
                    totalMatches: matchingIndices.count,
                    onPrevious: gotoPreviousMatch,
                    onNext: gotoNextMatch
                ) {
                    isSearching = false
                    searchText = ""
                    currentMatchIndex = 0
                }
                Divider()
            }

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(session.source == "Local"
                         ? "Loading conversation…"
                         : "Loading from \(session.source)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !allMessages.isEmpty {
                let matchSet = Set(matchingIndices)
                let currentMessageIndex = matchingIndices.isEmpty ? -1 : matchingIndices[min(currentMatchIndex, matchingIndices.count - 1)]
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(allMessages.enumerated()), id: \.element.id) { index, message in
                            MessageRow(
                                message: message,
                                highlight: matchSet.contains(index) ? searchText : "",
                                isCurrentMatch: index == currentMessageIndex
                            )
                        }
                    }
                    .scrollTargetLayout()
                    .padding(16)
                }
                .scrollPosition($scrollPosition)
            } else {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(loadError ?? "Could not load conversation content.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: searchText) { _, _ in currentMatchIndex = 0 }
        .background {
            Button(action: {
                isSearching = true
                DispatchQueue.main.async { isSearchFieldFocused = true }
            }) { EmptyView() }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .onKeyPress(.escape) {
            if isSearching {
                isSearching = false
                searchText = ""
                return .handled
            }
            return .ignored
        }
        .task {
            await loadSession()
        }
    }

    private func loadSession() async {
        isLoading = true
        loadError = nil

        detail = await service.loadSession(sessionId: session.sessionId, projectDir: session.projectDir)

        if detail == nil && session.source != "Local" {
            if let device = appState.remoteDevices.first(where: { $0.name == session.source }) {
                do {
                    detail = try await service.loadRemoteSession(
                        sessionId: session.sessionId,
                        projectDir: session.projectDir,
                        device: device
                    )
                } catch {
                    loadError = error.localizedDescription
                }
            } else {
                loadError = "Remote device '\(session.source)' not configured."
            }
        }

        isLoading = false
    }
}
