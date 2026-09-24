import XCTest
import AppKit
@testable import SimpleLaunchpad

final class OverlayKeyHandlingTests: XCTestCase {
    @MainActor
    func testReopeningDuringFadeKeepsWindowVisible() {
        _ = NSApplication.shared
        let controller = OverlayWindowController(
            store: LaunchpadStore(), preferences: AppPreferences(), onLaunch: { _ in }
        )
        controller.show()
        controller.hide()
        controller.toggle()

        let finished = expectation(description: "Fade completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            XCTAssertTrue(controller.window?.isVisible == true)
            XCTAssertEqual(controller.window?.alphaValue ?? 0, 1, accuracy: 0.01)
            controller.hide()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
    }

    func testEscapeKeyClosesOverlay() {
        XCTAssertTrue(OverlayKeyHandling.shouldClose(forKeyCode: 53))
    }

    func testOtherKeysDoNotClose() {
        XCTAssertFalse(OverlayKeyHandling.shouldClose(forKeyCode: 0))
    }

    func testPlainLetterIsTypable() {
        XCTAssertTrue(OverlayKeyHandling.isTypableCharacter("a", modifierFlags: []))
    }

    func testShiftedLetterIsTypable() {
        XCTAssertTrue(OverlayKeyHandling.isTypableCharacter("A", modifierFlags: .shift))
    }

    func testCommandShortcutIsNotTypable() {
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter("q", modifierFlags: .command))
    }

    func testControlShortcutIsNotTypable() {
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter("c", modifierFlags: .control))
    }

    func testArrowFunctionKeyIsNotTypable() {
        let upArrow = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter(upArrow, modifierFlags: .function))
    }

    func testEmptyCharactersAreNotTypable() {
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter("", modifierFlags: []))
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter(nil, modifierFlags: []))
    }

    func testDeleteCharacterIsNotTypable() {
        XCTAssertFalse(OverlayKeyHandling.isTypableCharacter("\u{7F}", modifierFlags: []))
    }
}
