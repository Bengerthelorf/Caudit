import SwiftUI

struct StatuslineSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var enabled: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Usage Cache", isOn: $enabled)
            } header: {
                Text("Claude Code Integration")
            } footer: {
                Text("Writes quota data to a cache file that your statusline script can read. Does not modify your existing statusline configuration.")
            }

            if enabled {
                Section {
                    HStack {
                        Text("Cache File")
                        Spacer()
                        Text("~/.claude/.statusline-usage-cache")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if appState.statuslineService.cacheExists {
                        Label("Cache active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Status")
                }

                Section("Cache Format") {
                    VStack(alignment: .leading, spacing: 6) {
                        formatRow("session", "5h window usage %")
                        formatRow("weekly", "7-day window usage %")
                        formatRow("reset", "Reset time (ISO 8601)")
                        formatRow("pace", "Pace label")
                        formatRow("updated", "Timestamp (Unix epoch)")
                    }
                    .font(.system(.caption, design: .monospaced))
                }

                Section {
                    Text(sampleContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.8)))
                } header: {
                    Text("Example")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { enabled = appState.statuslineService.isEnabled }
        .onChange(of: enabled) { _, newValue in
            appState.statuslineService.setEnabled(newValue)
        }
    }

    private func formatRow(_ key: String, _ desc: String) -> some View {
        HStack {
            Text("\(key)=…")
                .foregroundStyle(.primary)
            Spacer()
            Text(desc)
                .foregroundStyle(.secondary)
        }
    }

    private var sampleContent: String {
        """
        session=42
        weekly=28
        reset=2026-03-23T18:30:00Z
        pace=On Track
        updated=1774565400
        """
    }
}
