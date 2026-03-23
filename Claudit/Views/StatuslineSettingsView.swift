import SwiftUI

struct StatuslineSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var config: StatuslineService.Config = .init()

    var body: some View {
        Form {
            Section {
                Toggle("Write Usage Cache", isOn: $config.enabled)
            } header: {
                Text("Claude Code Integration")
            } footer: {
                Text("Writes quota data to a cache file that your statusline script can read. Does not modify your existing statusline configuration.")
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
                        .foregroundStyle(.green)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.8)))
                }

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
                    Text("Integration")
                } footer: {
                    Text("Read this file from your statusline script. Each line is key=value (usage, bar, reset, pace, weekly, updated).")
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
