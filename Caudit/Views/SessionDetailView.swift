import SwiftUI

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: SessionInfo

    @State private var detail: SessionDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    private let service = SessionDetailService()

    var body: some View {
        VStack(spacing: 0) {
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
                    Text(session.source == "Local"
                         ? "Loading conversation…"
                         : "Loading from \(session.source)…")
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
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(loadError ?? "Could not load conversation content.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    AppDelegate.shared.openSessionWindow(session: session)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open in separate window")
            }
        }
        .task {
            await loadSession()
        }
    }

    private func loadSession() async {
        isLoading = true
        loadError = nil

        // Try local first
        detail = await service.loadSession(sessionId: session.sessionId, projectDir: session.projectDir)

        // If local failed and this is a remote session, try SSH
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

// MARK: - Message Row

struct MessageRow: View {
    let message: SessionMessage
    @State private var isThinkingExpanded = false
    @State private var expandedTools: Set<String> = []

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
            // Role header
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

            // Content items
            ForEach(message.content) { item in
                contentView(for: item)
            }
        }
        .padding(12)
        .background(roleBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(roleBorder, lineWidth: 1)
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
