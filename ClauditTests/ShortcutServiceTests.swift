import XCTest
import Carbon.HIToolbox
@testable import Claudit

final class ShortcutServiceTests: XCTestCase {

    // MARK: - KeyCombo

    func testKeyComboDisplayStringCommandKey() {
        let combo = KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey))
        XCTAssertEqual(combo.displayString, "⌘A")
    }

    func testKeyComboDisplayStringMultipleModifiers() {
        let combo = KeyCombo(keyCode: 1, modifiers: UInt32(controlKey) | UInt32(shiftKey) | UInt32(cmdKey))
        XCTAssertEqual(combo.displayString, "⌃⇧⌘S")
    }

    func testKeyComboDisplayStringOptionKey() {
        let combo = KeyCombo(keyCode: 49, modifiers: UInt32(optionKey))
        XCTAssertEqual(combo.displayString, "⌥Space")
    }

    func testKeyComboEquality() {
        let a = KeyCombo(keyCode: 12, modifiers: UInt32(cmdKey))
        let b = KeyCombo(keyCode: 12, modifiers: UInt32(cmdKey))
        let c = KeyCombo(keyCode: 12, modifiers: UInt32(optionKey))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testKeyComboEncodeDecode() throws {
        let original = KeyCombo(keyCode: 15, modifiers: UInt32(cmdKey) | UInt32(shiftKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testKeyComboAllModifiers() {
        let combo = KeyCombo(
            keyCode: 3,
            modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘F")
    }

    func testKeyComboNoModifiers() {
        let combo = KeyCombo(keyCode: 12, modifiers: 0)
        XCTAssertEqual(combo.displayString, "Q")
    }

    // MARK: - NSModifiers to Carbon

    func testNSModifiersToCarbonCommand() {
        let carbon = KeyCombo.nsModifiersToCarbonModifiers(.command)
        XCTAssertEqual(carbon, UInt32(cmdKey))
    }

    func testNSModifiersToCarbonMultiple() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option]
        let carbon = KeyCombo.nsModifiersToCarbonModifiers(flags)
        XCTAssertTrue(carbon & UInt32(cmdKey) != 0)
        XCTAssertTrue(carbon & UInt32(shiftKey) != 0)
        XCTAssertTrue(carbon & UInt32(optionKey) != 0)
        XCTAssertTrue(carbon & UInt32(controlKey) == 0)
    }

    // MARK: - ShortcutAction

    func testAllActionsHaveUniqueIds() {
        let ids = ShortcutAction.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testActionRoundTripFromRawValue() {
        for action in ShortcutAction.allCases {
            XCTAssertEqual(ShortcutAction(rawValue: action.rawValue), action)
        }
    }
}
