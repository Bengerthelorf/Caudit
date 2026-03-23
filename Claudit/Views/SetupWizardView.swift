import SwiftUI

struct SetupWizardView: View {
    @Environment(AppState.self) private var appState
    @State private var step = 0
    @State private var verifyStatus: String?
    @State private var isVerifying = false
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i <= step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer()

            switch step {
            case 0:
                welcomeStep
            case 1:
                credentialsStep
            case 2:
                verifyStep
            default:
                EmptyView()
            }

            Spacer()

            // Navigation buttons
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(.borderless)
                }
                Spacer()
                if step < 2 {
                    Button("Next") { step += 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Finish") {
                        UserDefaults.standard.set(true, forKey: "setupWizardCompleted")
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)

            Button("Skip Setup") {
                UserDefaults.standard.set(true, forKey: "setupWizardCompleted")
                onComplete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .font(.caption)
            .padding(.bottom, 12)
        }
        .frame(width: 420, height: 360)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Claudit")
                .font(.title2.bold())
            Text("Track your Claude API usage, quota, and costs from the menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
        }
    }

    private var credentialsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Connect Your Account")
                .font(.title3.bold())
            Text("Claudit reads credentials from Claude Code. Run this command in your terminal if you haven't already:")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)

            Text("claude auth login")
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                .textSelection(.enabled)

            Text("Or choose a quota source in Settings > General after setup.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var verifyStep: some View {
        VStack(spacing: 16) {
            if isVerifying {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Verifying connection...")
                    .foregroundStyle(.secondary)
            } else if let status = verifyStatus {
                Image(systemName: status.contains("Success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(status.contains("Success") ? .green : .orange)
                Text(status)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                if !status.contains("Success") {
                    Button("Retry") { verify() }
                        .buttonStyle(.bordered)
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                Text("Verify Connection")
                    .font(.title3.bold())
                Text("Check that Claudit can read your usage data.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 300)

                Button("Verify") { verify() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func verify() {
        isVerifying = true
        verifyStatus = nil

        let service = appState.quotaService
        let source = appState.quotaSource
        Task.detached {
            do {
                let info = try await service.fetchQuota(source: source)
                await MainActor.run {
                    verifyStatus = "Success! 5h usage: \(Int(info.fiveHourUtilization))%, 7d: \(Int(info.sevenDayUtilization))%"
                    isVerifying = false
                }
            } catch {
                await MainActor.run {
                    verifyStatus = "Could not connect: \(error.localizedDescription)\n\nYou can still use Claudit for local usage tracking."
                    isVerifying = false
                }
            }
        }
    }
}
