import XCTest
@testable import SimpleLaunchpad

final class LaunchpadStoreTests: XCTestCase {
    private func app(_ id: String, _ name: String) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: name, path: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    private func utilityApp(_ id: String, _ name: String) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: name, path: URL(fileURLWithPath: "/System/Applications/Utilities/\(name).app"))
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

    func testMergeGroupsSystemUtilitiesIntoOtherFolder() {
        let a = app("com.a", "Alpha")
        let terminal = utilityApp("com.apple.terminal", "Terminal")
        let console = utilityApp("com.apple.console", "Console")

        let pages = LaunchpadStore.merge(discoveredApps: [a, terminal, console], savedLayout: nil, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.app(a), .folder(FolderInfo(name: "Other", apps: [console, terminal]))]])
    }

    func testMergePreservesExistingOtherFolderFromSavedLayout() {
        let terminal = utilityApp("com.apple.terminal", "Terminal")
        let savedLayout = LayoutFile(pages: [[.folder(name: "Other", bundleIdentifiers: ["com.apple.terminal"])]])

        let pages = LaunchpadStore.merge(discoveredApps: [terminal], savedLayout: savedLayout, itemsPerPage: 10)

        XCTAssertEqual(pages, [[.folder(FolderInfo(name: "Other", apps: [terminal]))]])
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

    // MARK: - filteredResults / isFiltering / availableCategories

    private func store(pages: [[LaunchpadItem]]) -> LaunchpadStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("layout.json")
        let store = LaunchpadStore(persistenceURL: tempURL)
        store.pages = pages
        return store
    }

    func testIsFilteringIsFalseWithNoQueryAndAllScope() {
        let store = store(pages: [[.app(app("com.a", "Alpha"))]])

        XCTAssertFalse(store.isFiltering)
    }

    func testIsFilteringIsTrueWithTypedQuery() {
        let store = store(pages: [[.app(app("com.a", "Alpha"))]])
        store.searchQuery = "al"

        XCTAssertTrue(store.isFiltering)
    }

    func testIsFilteringIsTrueForNonAllScopeEvenWithoutQuery() {
        let store = store(pages: [[.app(app("com.a", "Alpha"))]])
        store.scope = .recentlyAdded

        XCTAssertTrue(store.isFiltering)
    }

    func testFilteredResultsMatchesSearchQueryAmongTopLevelApps() {
        let alpha = app("com.a", "Alpha")
        let beta = app("com.b", "Beta")
        let store = store(pages: [[.app(alpha), .app(beta)]])
        store.searchQuery = "bet"

        XCTAssertEqual(store.filteredResults, [beta])
    }

    func testFilteredResultsExcludesAppsTuckedInsideFolders() {
        let alpha = app("com.a", "Alpha")
        let beta = app("com.b", "Beta")
        let store = store(pages: [[.app(alpha), .folder(FolderInfo(name: "Stuff", apps: [beta]))]])

        XCTAssertEqual(store.filteredResults, [alpha])
    }

    func testFilteredResultsScopedToCategoryUsesEffectiveOverride() {
        var alpha = app("com.a", "Alpha")
        alpha.category = .productivity
        let beta = app("com.b", "Beta") // defaults to .other
        let store = store(pages: [[.app(alpha), .app(beta)]])
        store.scope = .category(.productivity)

        XCTAssertEqual(store.filteredResults, [alpha])
    }

    func testFilteredResultsRecentlyAddedOrdersByDateDescendingRegardlessOfSort() {
        var older = app("com.a", "Older")
        older.dateAdded = Date(timeIntervalSince1970: 0)
        var newer = app("com.b", "Newer")
        newer.dateAdded = Date(timeIntervalSince1970: 1000)
        let store = store(pages: [[.app(older), .app(newer)]])
        store.scope = .recentlyAdded
        store.sortOption = .name // should be ignored for .recentlyAdded

        XCTAssertEqual(store.filteredResults, [newer, older])
    }

    func testFilteredResultsMostUsedSortOrdersByLaunchCountThenName() {
        let alpha = app("com.a", "Alpha")
        let beta = app("com.b", "Beta")
        let store = store(pages: [[.app(alpha), .app(beta)]])
        store.sortOption = .mostUsed
        store.launchCounts = ["com.b": 3]

        XCTAssertEqual(store.filteredResults, [beta, alpha])
    }

    func testAvailableCategoriesOnlyIncludesCategoriesWithInstalledApps() {
        var alpha = app("com.a", "Alpha")
        alpha.category = .productivity
        let store = store(pages: [[.app(alpha)]])

        XCTAssertEqual(store.availableCategories, [.productivity])
    }

    func testEffectiveCategoryPrefersManualOverride() {
        var alpha = app("com.a", "Alpha")
        alpha.category = .productivity
        let store = store(pages: [[.app(alpha)]])
        store.categoryOverrides = ["com.a": .games]

        XCTAssertEqual(store.effectiveCategory(for: alpha), .games)
    }
}
