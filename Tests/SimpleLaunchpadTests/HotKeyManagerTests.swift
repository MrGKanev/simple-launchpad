import XCTest
@testable import SimpleLaunchpad

final class HotKeyManagerTests: XCTestCase {
    func testHandleTriggerInvokesClosure() {
        var triggered = false
        let manager = HotKeyManager { triggered = true }

        manager.handleTrigger()

        XCTAssertTrue(triggered)
    }
}
