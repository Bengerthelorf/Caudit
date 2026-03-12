import SwiftUI

struct SessionReaderView: View {
    @Environment(AppState.self) private var appState
    let session: SessionInfo

    @State private var detail: SessionDetail?
    @State private var isLoading = true
    @State private var loadError: String?
    private let service = SessionDetailService()

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
