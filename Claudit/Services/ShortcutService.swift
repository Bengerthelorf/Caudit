import AppKit
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Claudit", category: "Shortcut")

enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case togglePopover = "Toggle Popover"
    case refresh = "Refresh"
    case openDashboard = "Open Dashboard"
    case openSettings = "Open Settings"

    var id: String { rawValue }
}

struct KeyCombo: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    /// Human-readable description of the key combo.
    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    static func fromNSEvent(_ event: NSEvent) -> KeyCombo {
        let carbonModifiers = Self.nsModifiersToCarbonModifiers(event.modifierFlags)
        return KeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
    }

    static func nsModifiersToCarbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        // Common key codes to human-readable strings
        let map: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 109: "F10", 111: "F12", 103: "F11",
            118: "F4", 120: "F2", 122: "F1",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }
}

/// Manages global keyboard shortcuts using Carbon Hot Key API.
/// Does not require Accessibility permissions.
@MainActor
final class ShortcutService {
    private var registeredHotKeys: [UInt32: (EventHotKeyRef, ShortcutAction)] = [:]
    private var nextHotKeyId: UInt32 = 1
    private var bindings: [ShortcutAction: KeyCombo] = [:]
    var actionHandler: ((ShortcutAction) -> Void)?

    static let shared = ShortcutService()

    private init() {
        loadBindings()
        installEventHandler()
        registerAllBindings()
    }

    // MARK: - Binding Management

    func setBinding(_ combo: KeyCombo, for action: ShortcutAction) {
        unregisterAction(action)
        bindings[action] = combo
        registerAction(action, combo: combo)
        saveBindings()
    }

    func removeBinding(for action: ShortcutAction) {
        unregisterAction(action)
        bindings.removeValue(forKey: action)
        saveBindings()
    }

    func binding(for action: ShortcutAction) -> KeyCombo? {
        bindings[action]
    }

    // MARK: - Carbon Hot Key Registration

    private func registerAction(_ action: ShortcutAction, combo: KeyCombo) {
        let hotKeyId = nextHotKeyId
        nextHotKeyId += 1

        let eventHotKeyID = EventHotKeyID(signature: OSType(0x434C4454), id: hotKeyId) // "CLDT"
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            registeredHotKeys[hotKeyId] = (ref, action)
            logger.info("Registered hotkey \(combo.displayString) for \(action.rawValue)")
        } else {
            logger.warning("Failed to register hotkey for \(action.rawValue): \(status)")
        }
    }

    private func unregisterAction(_ action: ShortcutAction) {
        for (id, entry) in registeredHotKeys where entry.1 == action {
            let status = UnregisterEventHotKey(entry.0)
            if status != noErr {
                logger.warning("Failed to unregister hotkey for \(action.rawValue): \(status)")
            }
            registeredHotKeys.removeValue(forKey: id)
        }
    }

    private func registerAllBindings() {
        for (action, combo) in bindings {
            registerAction(action, combo: combo)
        }
    }

    // MARK: - Carbon Event Handler

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                Task { @MainActor in
                    ShortcutService.shared.handleHotKey(id: hotKeyID.id)
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }

    private func handleHotKey(id: UInt32) {
        guard let (_, action) = registeredHotKeys[id] else { return }
        logger.info("Hotkey triggered: \(action.rawValue)")
        actionHandler?(action)
    }

    // MARK: - Persistence

    private func saveBindings() {
        let encodable = bindings.map { (key: $0.key.rawValue, value: $0.value) }
        let dict = Dictionary(uniqueKeysWithValues: encodable)
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "shortcutBindings")
        }
    }

    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: "shortcutBindings"),
              let dict = try? JSONDecoder().decode([String: KeyCombo].self, from: data) else { return }
        for (rawAction, combo) in dict {
            if let action = ShortcutAction(rawValue: rawAction) {
                bindings[action] = combo
            }
        }
    }
}
