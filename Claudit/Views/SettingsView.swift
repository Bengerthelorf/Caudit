import SwiftUI
import Sparkle

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case notifications = "Notifications"
    case shortcuts = "Shortcuts"
    case statusline = "Statusline"
    case devices = "Devices"
    case debug = "Debug"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .shortcuts: "keyboard"
        case .statusline: "terminal"
        case .devices: "desktopcomputer"
        case .debug: "ant.circle"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    let updater: SPUUpdater
    @State private var selectedTab: SettingsTab? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsView()
                    .navigationTitle("General")
            case .notifications:
                NotificationSettingsView()
                    .navigationTitle("Notifications")
            case .shortcuts:
                ShortcutSettingsView()
                    .navigationTitle("Shortcuts")
            case .statusline:
                StatuslineSettingsView()
                    .navigationTitle("Statusline")
            case .devices:
                DeviceSettingsView()
                    .navigationTitle("Devices")
            case .debug:
                DebugLogView()
                    .navigationTitle("Debug")
            case .about:
                AboutSettingsView(updater: updater)
                    .navigationTitle("About")
            case .none:
                GeneralSettingsView()
                    .navigationTitle("General")
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showBrowserSignIn = false

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("Menu Bar") {
                Picker("Display", selection: $state.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Usage Refresh", selection: $state.usageRefreshInterval) {
                    Text("30 seconds").tag(30.0 as TimeInterval)
                    Text("1 minute").tag(60.0 as TimeInterval)
                    Text("2 minutes").tag(120.0 as TimeInterval)
                    Text("5 minutes").tag(300.0 as TimeInterval)
                }

                Picker("Quota Refresh", selection: $state.quotaRefreshInterval) {
                    Text("1 minute").tag(60.0 as TimeInterval)
                    Text("2 minutes").tag(120.0 as TimeInterval)
                    Text("5 minutes").tag(300.0 as TimeInterval)
                    Text("10 minutes").tag(600.0 as TimeInterval)
                }
            }

            Section {
                Picker("Quota Source", selection: $state.quotaSource) {
                    ForEach(QuotaSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }

                if appState.quotaSource == .claudeSession {
                    if SessionCredentialStore.shared.isConfigured {
                        if SessionCredentialStore.shared.isExpired {
                            Label("Session expired", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Button("Sign In Again") { showBrowserSignIn = true }
                        } else {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Button("Sign Out") {
                                SessionCredentialStore.shared.clear()
                            }
                        }
                    } else {
                        Button("Sign In to Claude.ai") { showBrowserSignIn = true }
                    }
                }
            } header: {
                Text("Quota")
            } footer: {
                switch appState.quotaSource {
                case .rateLimitHeaders:
                    Text("Sends a minimal API call and reads quota from response headers. Low overhead, no extra login needed.")
                case .oauthAPI:
                    Text("Calls the OAuth usage endpoint directly. May be rate limited under heavy use.")
                case .claudeSession:
                    Text("Uses Claude.ai session cookie for full quota data including per-model breakdown.")
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
            }

            Section("Data") {
                LabeledContent("Pricing Source") {
                    Text("LiteLLM (auto-updated)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showBrowserSignIn) {
            BrowserSignInSheet()
        }
    }
}

// MARK: - Browser Sign-In Sheet

struct BrowserSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status: String = "Sign in to your Claude.ai account"
    @State private var organizations: [(id: String, name: String)] = []
    @State private var sessionKey: String?
    @State private var expiryDate: Date?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if let sessionKey, !organizations.isEmpty {
                // Organization selection
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Signed in successfully")
                        .font(.headline)
                    Text("Select your organization:")
                        .foregroundStyle(.secondary)

                    ForEach(organizations, id: \.id) { org in
                        Button {
                            SessionCredentialStore.shared.save(
                                sessionKey: sessionKey,
                                organizationId: org.id,
                                expiryDate: expiryDate
                            )
                            dismiss()
                        } label: {
                            Text(org.name)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(30)
            } else if isLoading {
                ProgressView("Fetching organizations...")
                    .padding(30)
            } else {
                // Browser
                VStack(spacing: 8) {
                    HStack {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    BrowserSignInView(
                        onSessionKey: { key, expiry in
                            self.sessionKey = key
                            self.expiryDate = expiry
                            self.status = "Session key obtained, fetching organizations..."
                            self.isLoading = true
                            fetchOrganizations(key: key)
                        },
                        onCancel: { dismiss() }
                    )
                }
            }
        }
        .frame(width: 500, height: 600)
    }

    private func fetchOrganizations(key: String) {
        Task {
            do {
                // Temporarily store key to fetch orgs
                SessionCredentialStore.shared.save(sessionKey: key, organizationId: "", expiryDate: expiryDate)
                let orgs = try await SessionCredentialStore.shared.fetchOrganizations()
                await MainActor.run {
                    organizations = orgs
                    isLoading = false
                    if orgs.count == 1 {
                        // Auto-select single org
                        SessionCredentialStore.shared.save(
                            sessionKey: key,
                            organizationId: orgs[0].id,
                            expiryDate: expiryDate
                        )
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    status = "Failed to fetch organizations: \(error.localizedDescription)"
                    isLoading = false
                    SessionCredentialStore.shared.clear()
                }
            }
        }
    }
}
