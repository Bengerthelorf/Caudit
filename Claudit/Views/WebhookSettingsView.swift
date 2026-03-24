import SwiftUI

struct WebhookSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        Form {
            Section {
                Toggle("Enable Webhook", isOn: $state.webhookConfig.enabled)
            } header: {
                Text("Webhook Notifications")
            } footer: {
                Text("Send alerts to external services when quota or budget thresholds are crossed.")
            }

            if appState.webhookConfig.enabled {
                Section("Service") {
                    Picker("Preset", selection: $state.webhookConfig.preset) {
                        ForEach(WebhookPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    switch appState.webhookConfig.preset {
                    case .slack:
                        TextField("Webhook URL", text: $state.webhookConfig.url)
                            .textFieldStyle(.roundedBorder)
                        Text("Create at: api.slack.com/apps → Incoming Webhooks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                    case .discord:
                        TextField("Webhook URL", text: $state.webhookConfig.url)
                            .textFieldStyle(.roundedBorder)
                        Text("Server Settings → Integrations → Webhooks → Copy URL")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                    case .telegram:
                        TextField("Bot Token", text: $state.webhookConfig.telegramBotToken)
                            .textFieldStyle(.roundedBorder)
                        TextField("Chat ID", text: $state.webhookConfig.telegramChatId)
                            .textFieldStyle(.roundedBorder)
                        Text("Create bot via @BotFather, send /start to bot, then use getUpdates API to find chat_id")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                    case .custom:
                        TextField("Webhook URL", text: $state.webhookConfig.url)
                            .textFieldStyle(.roundedBorder)
                        Text("POST with JSON body: {title, body, timestamp, source}")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    Button("Send Test") {
                        WebhookService.shared.send(
                            title: "Claudit Test",
                            body: "Webhook is working correctly!",
                            config: appState.webhookConfig
                        )
                    }
                    .disabled(!isConfigValid)
                } footer: {
                    Text("Sends a test message to verify your webhook configuration.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var isConfigValid: Bool {
        let cfg = appState.webhookConfig
        switch cfg.preset {
        case .telegram:
            return !cfg.telegramBotToken.isEmpty && !cfg.telegramChatId.isEmpty
        default:
            return !cfg.url.isEmpty
        }
    }
}
