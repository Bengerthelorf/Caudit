import SwiftUI

struct ShortcutSettingsView: View {
    @State private var recordingAction: ShortcutAction?
    @State private var bindings: [ShortcutAction: KeyCombo] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    HStack {
                        Text(action.rawValue)
                        Spacer()
                        if recordingAction == action {
                            Text("Press shortcut...")
                                .foregroundStyle(.secondary)
                                .italic()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).stroke(.blue))
                        } else if let combo = bindings[action] {
                            HStack(spacing: 4) {
                                Text(combo.displayString)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
                                Button {
                                    ShortcutService.shared.removeBinding(for: action)
                                    bindings.removeValue(forKey: action)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Button("Record") {
                                recordingAction = action
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Shortcuts work even when Claudit is in the background. Click \"Record\" then press your desired key combination.")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshBindings() }
        .background(ShortcutRecorderHelper(recordingAction: $recordingAction, onRecord: { action, combo in
            ShortcutService.shared.setBinding(combo, for: action)
            refreshBindings()
        }))
    }

    private func refreshBindings() {
        var result: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            result[action] = ShortcutService.shared.binding(for: action)
        }
        bindings = result
    }
}

/// Invisible NSView-based helper that captures key events for shortcut recording.
struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var recordingAction: ShortcutAction?
    let onRecord: (ShortcutAction, KeyCombo) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onKeyDown = { event in
            guard let action = recordingAction else { return }
            guard event.modifierFlags.intersection([.command, .option, .control, .shift]) != [] else { return }
            let combo = KeyCombo.fromNSEvent(event)
            onRecord(action, combo)
            recordingAction = nil
        }
        view.onCancel = {
            recordingAction = nil
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.isRecording = recordingAction != nil
        if recordingAction != nil {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

class ShortcutRecorderNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var onCancel: (() -> Void)?
    var isRecording = false

    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            if event.keyCode == 53 { // Escape
                onCancel?()
            } else {
                onKeyDown?(event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
