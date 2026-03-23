import SwiftUI

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

struct DeviceStatusBadge: View {
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

struct DeviceFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var device: RemoteDevice
    var onSave: (RemoteDevice) -> Void

    @State private var password: String = ""
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

                Section("Authentication") {
                    Toggle("Use Password", isOn: $device.usePassword)

                    if device.usePassword {
                        SecureField("Password", text: $password, prompt: Text("SSH password"))
                    } else {
                        TextField("SSH Key Path", text: $device.identityFile, prompt: Text("Optional, e.g. ~/.ssh/id_ed25519"))
                    }
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
                    if device.usePassword && !password.isEmpty {
                        SSHPasswordStore.save(password: password, for: device.id)
                    } else if !device.usePassword {
                        SSHPasswordStore.delete(for: device.id)
                    }
                    onSave(device)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(device.name.isEmpty || device.sshHost.isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 460)
        .onAppear {
            if device.usePassword {
                password = SSHPasswordStore.load(for: device.id) ?? ""
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        // Save password to Keychain before testing so SSHService can read it
        if device.usePassword && !password.isEmpty {
            SSHPasswordStore.save(password: password, for: device.id)
        }
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
