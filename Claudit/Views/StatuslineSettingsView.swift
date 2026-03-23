import SwiftUI

struct StatuslineSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var config: StatuslineService.Config = .init()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Terminal Statusline", isOn: $config.enabled)
            } header: {
                Text("Claude Code Integration")
            } footer: {
                Text("Installs a shell script at ~/.claude/statusline-command.sh that displays usage data in your terminal.")
            }

            if config.enabled {
                Section("Display Components") {
                    Toggle("Usage Percentage", isOn: $config.showUsagePercent)
                    Toggle("Progress Bar", isOn: $config.showProgressBar)
                    Toggle("Reset Time", isOn: $config.showResetTime)
                    Toggle("Pace Label", isOn: $config.showPaceLabel)
                    Toggle("24-Hour Time", isOn: $config.use24HourTime)

                    if config.showProgressBar {
                        Stepper("Bar Segments: \(config.barSegments)", value: $config.barSegments, in: 5...20)
                    }
                }

                Section("Preview") {
                    Text(previewText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.8)))
                        .foregroundStyle(.green)
                }

                Section {
                    HStack {
                        Text("Script Path")
                        Spacer()
                        Text("~/.claude/statusline-command.sh")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if appState.statuslineService.isInstalled {
                        Label("Script installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { config = appState.statuslineService.currentConfig }
        .onChange(of: config) { _, newConfig in
            appState.statuslineService.updateConfig(newConfig)
        }
    }

    private var previewText: String {
        StatuslineService.formatCacheContent(
            sessionPercent: 65,
            weeklyPercent: 42,
            config: config
        )
    }
}
