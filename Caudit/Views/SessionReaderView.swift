import SwiftUI

struct SessionReaderView: View {
    @Environment(AppState.self) private var appState
    let session: SessionInfo

    @State private var detail: SessionDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    private let service = SessionDetailService()

    private var filteredMessages: [SessionMessage] {
        guard let detail else { return [] }
        guard !searchText.isEmpty else { return detail.messages }
        return detail.messages.filter { message in
            message.content.contains { item in
                switch item {
                case .text(let text):
                    text.localizedCaseInsensitiveContains(searchText)
                case .thinking(let text):
                    text.localizedCaseInsensitiveContains(searchText)
                case .toolUse(_, let name, let input):
                    name.localizedCaseInsensitiveContains(searchText) ||
                    input.localizedCaseInsensitiveContains(searchText)
                case .toolResult(_, let content, _):
                    content.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
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
                    matchCount: searchText.isEmpty ? nil : filteredMessages.count
                ) {
                    isSearching = false
                    searchText = ""
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
            } else if !filteredMessages.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredMessages) { message in
                            MessageRow(message: message)
                        }
                    }
                    .padding(16)
                }
            } else if searchText.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(loadError ?? "Could not load conversation content.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No messages match \"\(searchText)\"")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress(characters: CharacterSet(charactersIn: "f")) { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            isSearching = true
            isSearchFieldFocused = true
            return .handled
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
