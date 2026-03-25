import SwiftUI

// MARK: - Profile Picker for Popover

struct ProfilePopoverPicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            ForEach(appState.profileManager.profiles) { profile in
                Button {
                    appState.profileManager.switchTo(profile.id)
                    appState.refresh()
                } label: {
                    HStack {
                        Text(profile.name)
                        if profile.isActive {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11))
                Text(appState.profileManager.activeProfile?.name ?? "Profile")
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Profile Settings View

struct ProfileSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedProfileId: UUID?
    @State private var showAddSheet = false
    @State private var newProfileName = ""
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: UUID?

    private var profileManager: ProfileManager {
        appState.profileManager
    }

    var body: some View {
        Form {
            Section("Profiles") {
                List(profileManager.profiles, selection: $selectedProfileId) { profile in
                    HStack {
                        if profile.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                        Text(profile.name)
                            .lineLimit(1)
                        Spacer()
                        if profile.autoSwitchOnLimit {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .help("Auto-switch on limit")
                        }
                    }
                    .tag(profile.id)
                    .contextMenu {
                        Button("Switch to") {
                            profileManager.switchTo(profile.id)
                            appState.refresh()
                        }
                        .disabled(profile.isActive)
                        Divider()
                        Button("Delete", role: .destructive) {
                            profileToDelete = profile.id
                            showDeleteConfirmation = true
                        }
                        .disabled(profileManager.profiles.count <= 1)
                    }
                }
                .frame(minHeight: 120)

                HStack {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .controlSize(.small)

                    Spacer()

                    if let selectedId = selectedProfileId,
                       profileManager.profiles.count > 1 {
                        Button(role: .destructive) {
                            profileToDelete = selectedId
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .controlSize(.small)
                    }
                }
            }

            if let selectedId = selectedProfileId,
               let profile = profileManager.profiles.first(where: { $0.id == selectedId }) {
                ProfileDetailSection(profile: profile)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedProfileId = profileManager.activeProfileId
        }
        .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let id = profileToDelete {
                    profileManager.deleteProfile(id)
                    selectedProfileId = profileManager.activeProfileId
                    appState.refresh()
                }
            }
        } message: {
            Text("This will permanently delete the profile and its stored credentials.")
        }
        .sheet(isPresented: $showAddSheet) {
            AddProfileSheet { name in
                let profile = profileManager.addProfile(name: name)
                selectedProfileId = profile.id
            }
        }
    }
}

// MARK: - Profile Detail Section

struct ProfileDetailSection: View {
    @Environment(AppState.self) private var appState
    let profile: Profile
    @State private var editedName: String = ""
    @State private var autoSwitch: Bool = false

    private var profileManager: ProfileManager {
        appState.profileManager
    }

    var body: some View {
        Section("Profile: \(profile.name)") {
            TextField("Name", text: $editedName)
                .onSubmit {
                    profileManager.renameProfile(profile.id, to: editedName)
                }

            Toggle("Auto-switch when at limit", isOn: $autoSwitch)
                .onChange(of: autoSwitch) { _, newValue in
                    var updated = profile
                    updated.autoSwitchOnLimit = newValue
                    profileManager.updateProfile(updated)
                }

            if !profile.isActive {
                Button("Switch to this Profile") {
                    profileManager.switchTo(profile.id)
                    appState.refresh()
                }
            } else {
                Label("Active Profile", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            LabeledContent("Config Dir") {
                Text("~/.claude")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .onAppear {
            editedName = profile.name
            autoSwitch = profile.autoSwitchOnLimit
        }
        .onChange(of: profile.id) { _, _ in
            editedName = profile.name
            autoSwitch = profile.autoSwitchOnLimit
        }
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onAdd: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Profile")
                .font(.headline)
            TextField("Profile Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onAdd(name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
