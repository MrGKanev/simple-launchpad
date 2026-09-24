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
}
