import XCTest
@testable import SimpleLaunchpad

final class AppSearchTests: XCTestCase {
    private func app(_ name: String) -> AppInfo {
        AppInfo(bundleIdentifier: "com.\(name)", name: name, path: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testFilterMatchesCaseInsensitiveSubstring() {
        let apps = [app("Safari"), app("Terminal"), app("Xcode")]

        let result = AppSearch.filter(apps, query: "sa")

        XCTAssertEqual(result.map(\.name), ["Safari"])
    }

    func testFilterReturnsEmptyForEmptyQuery() {
        let apps = [app("Safari")]

        XCTAssertTrue(AppSearch.filter(apps, query: "   ").isEmpty)
    }

    func testFilterSortsMatchesAlphabetically() {
        let apps = [app("Zterm"), app("Aterm")]

        let result = AppSearch.filter(apps, query: "term")

        XCTAssertEqual(result.map(\.name), ["Aterm", "Zterm"])
    }
}
