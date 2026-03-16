import SwiftUI
import Sparkle
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Caudit", category: "Settings")

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case notifications = "Notifications"
    case devices = "Devices"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .devices: "desktopcomputer"
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
            case .devices:
                DeviceSettingsView()
                    .navigationTitle("Devices")
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
    }
}

// MARK: - Notifications

struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        Form {
            Section {
                Toggle("Quota Threshold Alert", isOn: $state.notifyOnQuotaThreshold)

                if appState.notifyOnQuotaThreshold {
                    Picker("Alert when 5h usage exceeds", selection: $state.quotaNotificationThreshold) {
                        Text("50%").tag(50.0)
                        Text("60%").tag(60.0)
                        Text("70%").tag(70.0)
                        Text("80%").tag(80.0)
                        Text("90%").tag(90.0)
                    }
                }
            } header: {
                Text("Quota")
            } footer: {
                Text("Sends a system notification when your 5-hour quota window crosses the threshold.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Devices

struct DeviceSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var editingDevice: RemoteDevice?
    @State private var showAddSheet = false

    var body: some View {
        @Bindable var state = appState
        Form {
            Section {
                if appState.remoteDevices.isEmpty {
                    Text("No remote devices configured")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($state.remoteDevices) { $device in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading) {
                                HStack(spacing: 6) {
                                    Text(device.name)
                                        .fontWeight(.medium)
                                    DeviceStatusBadge(status: appState.remoteDeviceStatus[device.id]) {
                                        appState.refresh()
                                    }
                                }
                                Text(device.sshHost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $device.isEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()

                            Button {
                                editingDevice = device
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)

                            Button {
                                let idToRemove = device.id
                                DispatchQueue.main.async {
                                    appState.remoteDevices.removeAll { $0.id == idToRemove }
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Remote Devices")
            } footer: {
                Text("Aggregate Claude Code and OpenClaw usage from other machines via SSH.")
            }

            Section {
                Button("Add Device…") {
                    showAddSheet = true
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showAddSheet) {
            DeviceFormSheet(device: RemoteDevice(name: "", sshHost: "")) { newDevice in
                appState.remoteDevices.append(newDevice)
            }
        }
        .sheet(item: $editingDevice) { device in
            DeviceFormSheet(device: device) { updated in
                if let idx = appState.remoteDevices.firstIndex(where: { $0.id == updated.id }) {
                    appState.remoteDevices[idx] = updated
                }
            }
        }
    }
}

private struct DeviceStatusBadge: View {
    let status: RemoteDeviceStatus?
    var onRetry: (() -> Void)? = nil

    var body: some View {
        switch status {
        case .fetching:
            ProgressView()
                .controlSize(.mini)
        case .success(let count):
            Text("\(count) records")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed(let msg):
            Button {
                onRetry?()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.borderless)
            .help("Error: \(msg) — Click to retry")
        case nil:
            EmptyView()
        }
    }
}

private struct DeviceFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var device: RemoteDevice
    var onSave: (RemoteDevice) -> Void

    @State private var isTesting = false
    @State private var testResult: (success: Bool, message: String)?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Connection") {
                    TextField("Name", text: $device.name, prompt: Text("e.g. My Server"))
                    TextField("SSH Host", text: $device.sshHost, prompt: Text("e.g. user@192.168.1.100 or ssh-alias"))
                }

                Section("Paths") {
                    TextField("Claude Config Path", text: $device.claudePath, prompt: Text("~/.claude"))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("OpenClaw Paths")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                            Spacer()
                            Button {
                                device.openClawPaths.append("")
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                        }

                        ForEach(device.openClawPaths.indices, id: \.self) { index in
                            HStack(spacing: 4) {
                                TextField("Path", text: $device.openClawPaths[index], prompt: Text("~/.openclaw"))
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    device.openClawPaths.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Options") {
                    TextField("SSH Key Path", text: $device.identityFile, prompt: Text("Optional, e.g. ~/.ssh/id_ed25519"))
                }
            }
            .formStyle(.grouped)

            if let result = testResult {
                Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? .green : .red)
                    .font(.callout)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(device.sshHost.isEmpty || isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if device.claudePath.isEmpty { device.claudePath = "~/.claude" }
                    device.openClawPaths = device.openClawPaths.filter { !$0.isEmpty }
                    onSave(device)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(device.name.isEmpty || device.sshHost.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 420)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            let service = RemoteUsageService()
            var testDevice = device
            if testDevice.claudePath.isEmpty { testDevice.claudePath = "~/.claude" }
            testDevice.openClawPaths = testDevice.openClawPaths.filter { !$0.isEmpty }
            let result = await service.testConnection(testDevice)
            testResult = result
            isTesting = false
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private let updater: SPUUpdater
    @State private var avatarImage: NSImage?
    @State private var fetchTask: Task<Void, Never>?
    private static var memoryCache: NSImage?

    init(updater: SPUUpdater) {
        self.updater = updater
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)

                if let avatarImage {
                    Image(nsImage: avatarImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(radius: 2)
                        .rotationEffect(.degrees(20))
                        .offset(x: 6, y: 6)
                }
            }

            Text("Caudit")
                .font(.title.bold())

            Text("Version \(appVersion) (\(buildNumber))")
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/Bengerthelorf/Caudit")!)
            }
            .font(.callout)

            CheckForUpdatesView(updater: updater)
                .padding(.top, 4)

            Spacer()

            Text("Made by Bengerthelorf")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadAvatar()
        }
        .onDisappear {
            fetchTask?.cancel()
            fetchTask = nil
        }
    }

    // MARK: - Avatar Caching (memory + disk + bundled asset)

    private static let avatarCacheURL: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("avatar.png")
    }()

    private static let cacheMaxAge: TimeInterval = 86400

    private func loadAvatar() {
        if let cached = Self.memoryCache {
            avatarImage = cached
            if Self.isDiskCacheStale {
                fetchTask = Task { await fetchAndCacheAvatar() }
            }
            return
        }

        let cacheURL = Self.avatarCacheURL
        if FileManager.default.fileExists(atPath: cacheURL.path),
           let data = try? Data(contentsOf: cacheURL),
           let image = NSImage(data: data) {
            Self.memoryCache = image
            avatarImage = image
            if Self.isDiskCacheStale {
                fetchTask = Task { await fetchAndCacheAvatar() }
            }
            return
        }

        if let bundled = NSImage(named: "AuthorAvatar") {
            avatarImage = bundled
        }

        fetchTask = Task { await fetchAndCacheAvatar() }
    }

    private static var isDiskCacheStale: Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: avatarCacheURL.path),
              let modified = attrs[.modificationDate] as? Date else {
            return true
        }
        return Date().timeIntervalSince(modified) >= cacheMaxAge
    }

    private func fetchAndCacheAvatar() async {
        guard let url = URL(string: "https://github.com/Bengerthelorf.png?size=64") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()
            if let image = NSImage(data: data) {
                Self.memoryCache = image
                try? data.write(to: Self.avatarCacheURL, options: .atomic)
                avatarImage = image
            }
        } catch is CancellationError {
            return
        } catch {
            logger.debug("Failed to fetch avatar: \(error.localizedDescription)")
        }
    }
}
