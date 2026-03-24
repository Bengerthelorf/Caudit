import SwiftUI

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    private let availableThresholds = [50, 60, 70, 75, 80, 90, 95]

    var body: some View {
        @Bindable var state = appState
        Form {
            Section {
                Toggle("5h Quota Threshold Alerts", isOn: $state.notifyOnQuotaThreshold)

                if appState.notifyOnQuotaThreshold {
                    ForEach(availableThresholds, id: \.self) { threshold in
                        Toggle("\(threshold)%", isOn: thresholdBinding(threshold))
                    }
                    .padding(.leading, 8)
                }
            } header: {
                Text("5-Hour Window")
            } footer: {
                Text("Sends a notification when your 5-hour usage crosses any enabled threshold.")
            }

            Section {
                Toggle("Session Reset Notification", isOn: $state.notifyOnSessionReset)
            } footer: {
                Text("Notifies when your 5-hour quota window resets to 0%.")
            }

            Section {
                Toggle("7-Day Quota Threshold Alerts", isOn: $state.notifyOnWeeklyThreshold)
            } header: {
                Text("Weekly")
            } footer: {
                Text("Uses the same thresholds as 5-hour alerts for the 7-day window.")
            }
            Section {
                Toggle("Budget Alerts", isOn: $state.notifyOnBudget)

                if appState.notifyOnBudget {
                    HStack {
                        Text("Daily Budget")
                        Spacer()
                        TextField("$", value: $state.dailyBudget, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Monthly Budget")
                        Spacer()
                        TextField("$", value: $state.monthlyBudget, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Spending")
            } footer: {
                Text("Alerts when your daily or monthly spend crosses the configured thresholds as a percentage of the budget. Set to $0 to disable.")
            }
        }
        .formStyle(.grouped)
    }

    private func thresholdBinding(_ threshold: Int) -> Binding<Bool> {
        Binding(
            get: { appState.enabledNotificationThresholds.contains(threshold) },
            set: { enabled in
                if enabled {
                    appState.enabledNotificationThresholds.insert(threshold)
                } else {
                    appState.enabledNotificationThresholds.remove(threshold)
                }
            }
        )
    }
}
