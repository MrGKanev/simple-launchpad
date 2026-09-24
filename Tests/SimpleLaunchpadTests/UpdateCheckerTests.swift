import XCTest
@testable import SimpleLaunchpad

final class UpdateCheckerTests: XCTestCase {
    func testHigherMajorVersionIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9"))
    }

    func testDoubleDigitMinorIsNewerThanSingleDigit() {
        // The whole reason for a numeric compare instead of a string
        // compare: "1.10" > "1.2" numerically, but "1.10" < "1.2" as text.
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.2"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.1", than: "1.2"))
    }

    func testMissingTrailingComponentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.1"))
    }
}
