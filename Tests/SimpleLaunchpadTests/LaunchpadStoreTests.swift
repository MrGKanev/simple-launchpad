import XCTest
@testable import SimpleLaunchpad

final class LaunchpadStoreTests: XCTestCase {
    private func app(_ id: String, _ name: String) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: name, path: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testMergePreservesSavedOrderForKnownApps() {
        let a = app("com.a", "Alpha")
        let b = app("com.b", "Beta")
        let savedLayout = LayoutFile(pages: [[.app(bundleIdentifier: "com.b"), .app(bundleIdentifier: "com.a")]])

        let pages = LaunchpadStore.merge(discoveredApps: [a, b], savedLayout: savedLayout, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(b), .app(a)]])
    }

    func testMergeAppendsNewAppsAlphabeticallyAfterSavedItems() {
        let a = app("com.a", "Alpha")
        let newApp = app("com.z", "Zebra")
        let savedLayout = LayoutFile(pages: [[.app(bundleIdentifier: "com.a")]])

        let pages = LaunchpadStore.merge(discoveredApps: [a, newApp], savedLayout: savedLayout, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(a), .app(newApp)]])
    }

    func testMergeDropsAppsNoLongerOnDisk() {
        let a = app("com.a", "Alpha")
        let savedLayout = LayoutFile(pages: [[.app(bundleIdentifier: "com.a"), .app(bundleIdentifier: "com.gone")]])

        let pages = LaunchpadStore.merge(discoveredApps: [a], savedLayout: savedLayout, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(a)]])
    }

    func testMergeDropsFoldersThatBecomeEmpty() {
        let a = app("com.a", "Alpha")
        let savedLayout = LayoutFile(pages: [[
            .app(bundleIdentifier: "com.a"),
            .folder(name: "Empty", bundleIdentifiers: ["com.gone1", "com.gone2"])
        ]])

        let pages = LaunchpadStore.merge(discoveredApps: [a], savedLayout: savedLayout, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(a)]])
    }

    func testMergeWithNoSavedLayoutSortsAlphabetically() {
        let z = app("com.z", "Zebra")
        let a = app("com.a", "Alpha")

        let pages = LaunchpadStore.merge(discoveredApps: [z, a], savedLayout: nil, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(a), .app(z)]])
    }

    func testMergeSplitsIntoPagesOfGivenSize() {
        let apps = (0..<5).map { app("com.\($0)", "App\($0)") }

        let pages = LaunchpadStore.merge(discoveredApps: apps, savedLayout: nil, itemsPerPage: 2)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].count, 2)
        XCTAssertEqual(pages[2].count, 1)
    }

    func testMergingIntoFolderCombinesTwoApps() {
        let a = app("com.a", "Alpha")
        let b = app("com.b", "Beta")
        let items: [LaunchpadItem] = [.app(a), .app(b)]

        let result = LaunchpadStore.mergingIntoFolder(sourceIndex: 0, targetIndex: 1, items: items)

        XCTAssertEqual(result, [.folder(FolderInfo(name: "Folder", apps: [b, a]))])
    }

    func testMergingIntoFolderAddsAppToExistingFolder() {
        let a = app("com.a", "Alpha")
        let b = app("com.b", "Beta")
        let folder = FolderInfo(name: "Utilities", apps: [b])
        let items: [LaunchpadItem] = [.app(a), .folder(folder)]

        let result = LaunchpadStore.mergingIntoFolder(sourceIndex: 0, targetIndex: 1, items: items)

        XCTAssertEqual(result, [.folder(FolderInfo(name: "Utilities", apps: [b, a]))])
    }

    func testMergingIntoFolderIsNoOpForInvalidIndices() {
        let a = app("com.a", "Alpha")
        let items: [LaunchpadItem] = [.app(a)]

        let result = LaunchpadStore.mergingIntoFolder(sourceIndex: 0, targetIndex: 5, items: items)

        XCTAssertEqual(result, items)
    }
}
