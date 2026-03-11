import SwiftUI

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: SessionInfo

    @State private var detail: SessionDetail?
    @State private var isLoading = true
    private let service = SessionDetailService()

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: { appState.selectedSessionForDetail = nil }) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Divider().frame(height: 16)

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

            // Messages
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading conversation…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail, !detail.messages.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(detail.messages) { message in
                            MessageRow(message: message)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No Messages", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Could not load conversation content."))
            }
        }
        .task {
            isLoading = true
            detail = await service.loadSession(sessionId: session.sessionId, projectDir: session.projectDir)
            isLoading = false
        }
    }
}

// MARK: - Message Row

private struct MessageRow: View {
    let message: SessionMessage
    @State private var isThinkingExpanded = false
    @State private var expandedTools: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Role header
            HStack(spacing: 6) {
                Image(systemName: message.role == .user ? "person.fill" : "sparkle")
                    .foregroundStyle(message.role == .user ? .blue : .purple)
                    .frame(width: 16)
                Text(message.role == .user ? "User" : "Assistant")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(message.role == .user ? .blue : .purple)
                Spacer()
                Text(message.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Content items
            ForEach(message.content) { item in
                contentView(for: item)
            }
        }
        .padding(12)
        .background(
            message.role == .user
                ? Color.blue.opacity(0.04)
                : Color.purple.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    message.role == .user
                        ? Color.blue.opacity(0.1)
                        : Color.purple.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func contentView(for item: SessionContentItem) -> some View {
        switch item {
        case .text(let text):
            Text(text)
                .font(.body)
                .textSelection(.enabled)

        case .thinking(let text):
            DisclosureGroup(
                isExpanded: $isThinkingExpanded,
                content: {
                    Text(text)
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
                    Text(input)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(20)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                }
            } label: {
                Label(name, systemImage: toolIcon(name))
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
                Text(content.prefix(2000))
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

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "Read": return "doc.text"
        case "Write": return "square.and.pencil"
        case "Edit": return "pencil.line"
        case "Bash": return "terminal"
        case "Glob": return "doc.text.magnifyingglass"
        case "Grep": return "magnifyingglass"
        case "Agent": return "person.2"
        default: return "wrench"
        }
    }
}
