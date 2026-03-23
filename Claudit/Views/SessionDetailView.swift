import SwiftUI

struct SessionDetailView: View {
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

            SessionMessageList(
                messages: allMessages,
                isLoading: isLoading,
                loadError: loadError,
                loadingSource: session.source,
                searchText: searchText,
                matchingIndices: matchingIndices,
                currentMatchIndex: currentMatchIndex,
                scrollPosition: $scrollPosition
            )
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

// MARK: - Shared Message List

struct SessionMessageList: View {
    let messages: [SessionMessage]
    let isLoading: Bool
    let loadError: String?
    let loadingSource: String
    let searchText: String
    let matchingIndices: [Int]
    let currentMatchIndex: Int
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(loadingSource == "Local"
                     ? "Loading conversation…"
                     : "Loading from \(loadingSource)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !messages.isEmpty {
            let matchSet = Set(matchingIndices)
            let currentMessageIndex = matchingIndices.isEmpty ? -1 : matchingIndices[min(currentMatchIndex, matchingIndices.count - 1)]
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
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
}

// MARK: - Message Row

struct MessageRow: View {
    let message: SessionMessage
    var highlight: String = ""
    var isCurrentMatch: Bool = false
    @State private var isThinkingExpanded = false
    @State private var expandedTools: Set<String> = []

    private func highlighted(_ content: String) -> AttributedString {
        var attributed = AttributedString(content)
        guard !highlight.isEmpty else { return attributed }
        let highlightColor: Color = isCurrentMatch
            ? Color(nsColor: .findHighlightColor)
            : .yellow.opacity(0.25)
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex,
              let range = attributed[searchStart..<attributed.endIndex]
                .range(of: highlight, options: .caseInsensitive) {
            attributed[range].backgroundColor = highlightColor
            if isCurrentMatch {
                attributed[range].foregroundColor = .black
            }
            searchStart = range.upperBound
        }
        return attributed
    }

    private var displayRole: DisplayRole {
        if message.isToolResultOnly {
            return .toolResult
        }
        return message.role == .user ? .user : .assistant
    }

    private enum DisplayRole {
        case user, assistant, toolResult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: roleIcon)
                    .foregroundStyle(roleColor)
                    .frame(width: 16)
                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(roleColor)
                Spacer()
                Text(message.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(Array(message.content.enumerated()), id: \.offset) { _, item in
                contentView(for: item)
            }
        }
        .padding(12)
        .background(roleBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isCurrentMatch ? Color.accentColor : roleBorder,
                    lineWidth: isCurrentMatch ? 2 : 1
                )
        )
    }

    private var roleIcon: String {
        switch displayRole {
        case .user: return "person.fill"
        case .assistant: return "sparkle"
        case .toolResult: return "gearshape.arrow.triangle.2.circlepath"
        }
    }

    private var roleLabel: String {
        switch displayRole {
        case .user: return "User"
        case .assistant: return "Assistant"
        case .toolResult: return "Tool Results"
        }
    }

    private var roleColor: Color {
        switch displayRole {
        case .user: return .blue
        case .assistant: return .purple
        case .toolResult: return .green
        }
    }

    private var roleBackground: Color {
        switch displayRole {
        case .user: return Color.blue.opacity(0.04)
        case .assistant: return Color.purple.opacity(0.04)
        case .toolResult: return Color.green.opacity(0.04)
        }
    }

    private var roleBorder: Color {
        switch displayRole {
        case .user: return Color.blue.opacity(0.1)
        case .assistant: return Color.purple.opacity(0.1)
        case .toolResult: return Color.green.opacity(0.1)
        }
    }

    @ViewBuilder
    private func contentView(for item: SessionContentItem) -> some View {
        switch item {
        case .text(let text):
            Text(highlighted(text))
                .font(.body)
                .textSelection(.enabled)

        case .thinking(let text):
            DisclosureGroup(
                isExpanded: $isThinkingExpanded,
                content: {
                    Text(highlighted(text))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(50)
                        .padding(.top, 4)
                },
                label: {
                    Label("Thinking", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )

        case .toolUse(let id, let name, let input):
            let isExpanded = Binding(
                get: { expandedTools.contains(id) },
                set: { if $0 { expandedTools.insert(id) } else { expandedTools.remove(id) } }
            )
            DisclosureGroup(isExpanded: isExpanded) {
                if !input.isEmpty {
                    Text(highlighted(input))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(20)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                }
            } label: {
                Label(name, systemImage: ClauditFormatter.toolIcon(name))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }

        case .toolResult(let id, let content, let isError):
            let isExpanded = Binding(
                get: { expandedTools.contains(id) },
                set: { if $0 { expandedTools.insert(id) } else { expandedTools.remove(id) } }
            )
            DisclosureGroup(isExpanded: isExpanded) {
                Text(highlighted(String(content.prefix(2000))))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isError ? .red : .secondary)
                    .textSelection(.enabled)
                    .lineLimit(20)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
            } label: {
                Label(
                    isError ? "Error" : "Result",
                    systemImage: isError ? "xmark.circle" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(isError ? .red : .green)
            }
        }
    }

}

// MARK: - Search Bar

struct SessionSearchBar: View {
    @Binding var searchText: String
    var isSearchFieldFocused: FocusState<Bool>.Binding
    var currentMatch: Int
    var totalMatches: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search messages…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(isSearchFieldFocused)
                .onSubmit { onNext() }

            if !searchText.isEmpty {
                Text("\(totalMatches > 0 ? currentMatch + 1 : 0) / \(totalMatches)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                ControlGroup {
                    Button(action: onPrevious) {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .disabled(totalMatches == 0)

                    Button(action: onNext) {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .disabled(totalMatches == 0)
                }
                .controlGroupStyle(.navigation)
            }

            Button("Done", action: onDismiss)
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
