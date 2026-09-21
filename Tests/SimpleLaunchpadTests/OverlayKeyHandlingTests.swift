import XCTest
@testable import SimpleLaunchpad

final class OverlayKeyHandlingTests: XCTestCase {
    func testEscapeKeyClosesOverlay() {
        XCTAssertTrue(OverlayKeyHandling.shouldClose(forKeyCode: 53))
    }

    func testOtherKeysDoNotClose() {
        XCTAssertFalse(OverlayKeyHandling.shouldClose(forKeyCode: 0))
    }
}
