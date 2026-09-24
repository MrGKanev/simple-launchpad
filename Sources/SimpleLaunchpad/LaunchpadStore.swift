import Foundation
import Combine
import AppKit

struct FolderInfo: Equatable {
    var name: String
    var apps: [AppInfo]
}

enum LaunchpadItem: Equatable {
    case app(AppInfo)
    case folder(FolderInfo)
}

final class LaunchpadStore: ObservableObject {
    @Published var pages: [[LaunchpadItem]] = []

    // Owned here (rather than as view-local state) so `OverlayWindowController`
    // can also drive page navigation directly from its window-level scroll and
    // arrow-key monitors, alongside the SwiftUI views.
    @Published var currentPage: Int = 0 {
        didSet {
            selectedIndex = 0
            hasKeyboardSelection = false
        }
    }
    @Published var searchQuery: String = "" {
        didSet {
            selectedIndex = 0
            hasKeyboardSelection = false
        }
    }
    // Which pill is selected in the bar under the search field (`.all` ==
    // "All"). Combines with `searchQuery` in `filteredResults` rather than
    // being mutually exclusive with it, so typing a query while a category
    // is active narrows within that category instead of replacing it.
    @Published var scope: LaunchpadScope = .all {
        didSet {
            selectedIndex = 0
            hasKeyboardSelection = false
        }
    }
    // How `filteredResults` orders whatever `scope` narrows down to —
    // "Name" (default) or "Most Used". Exposed as a small control next to
    // the category bar; irrelevant (and hidden) while `scope == .recentlyAdded`.
    @Published var sortOption: LaunchpadSortOption = .name {
        didSet {
            selectedIndex = 0
            hasKeyboardSelection = false
        }
    }
    // Manual category reassignments (drag an icon onto a different pill),
    // keyed by bundle identifier — overrides whatever `AppInfo.category` was
    // auto-detected from Info.plist. Persisted separately from `pages` since
    // it's keyed by app identity, not by grid position.
    @Published var categoryOverrides: [String: AppCategory] = [:]
    // Launch counts per bundle identifier, driving the "Most Used" sort.
    @Published var launchCounts: [String: Int] = [:]
    // Set by `CategoryFilterBar`'s `.onHover` while the pointer is over the
    // pill row — lets `OverlayWindowController.handleScroll` step aside so a
    // horizontal trackpad swipe there scrolls the pills instead of also
    // flipping the current Launchpad page (its own global scroll-wheel
    // monitor otherwise sees the exact same horizontal delta).
    @Published var isHoveringCategoryBar: Bool = false
    // Set by `SearchField` when its underlying `NSSearchField` is created —
    // lets `OverlayWindowController`'s key monitor redirect focus there the
    // moment the user starts typing, without the field needing to already
    // be first responder. Weak since the view (and its NSView) can outlive
    // or be torn down independently of the store.
    weak var searchField: NSSearchField?
    // Set by `OverlayWindowController.handleScroll` when a *plain* mouse
    // wheel (vertical-only, no horizontal axis) scrolls while hovering the
    // category bar — `ScrollView(.horizontal)` only ever reacts to a
    // horizontal delta on its own, so a mouse with no horizontal wheel
    // could otherwise never move the row at all. `CategoryFilterBar` steps
    // itself by a few pills each time this changes (a fresh id every time,
    // so repeated same-direction nudges keep firing).
    @Published var categoryBarScrollNudge: CategoryBarScrollNudge?

    // Index of the keyboard-highlighted icon within whatever's currently
    // visible (the current page's items, or `filteredResults` while
    // searching/category-filtering) — driven by `OverlayWindowController`'s
    // arrow-key monitor.
    @Published var selectedIndex: Int = 0
    // Whether an arrow key has actually been pressed since the current page
    // (or search) became active. `selectedIndex` starts at 0 by default, but
    // the highlight it drives should stay hidden until the user has really
    // started navigating with the keyboard — otherwise the first icon always
    // looks selected even on a plain hover-and-click.
    @Published var hasKeyboardSelection: Bool = false
    // Which folder popup is open, if any. Lives here (rather than as
    // view-local state in `PageView`) so pressing Return on a
    // keyboard-selected folder can open it from `OverlayWindowController`,
    // outside the SwiftUI view tree.
    @Published var openFolder: FolderInfo?
    // Set while a folder's name is being edited in place, so
    // `OverlayWindowController` knows to let Return/arrow keys behave like
    // normal text editing instead of driving icon selection/launch.
    @Published var isEditingFolderName: Bool = false
    // Cmd/Shift-click toggles membership here for bulk "Remove"/"Move to
    // Trash" — keyed by bundle identifier since an `AppInfo` itself isn't
    // Hashable-friendly as a Set element across separate lookups.
    @Published var selectedBundleIdentifiers: Set<String> = []

    private let itemsPerPage: Int
    private let persistenceURL: URL
    private var categoryOverridesURL: URL {
        persistenceURL.deletingLastPathComponent().appendingPathComponent("categoryOverrides.json")
    }
    private var launchCountsURL: URL {
        persistenceURL.deletingLastPathComponent().appendingPathComponent("launchCounts.json")
    }

    init(itemsPerPage: Int = 35, persistenceURL: URL = LayoutPersistence.defaultURL()) {
        self.itemsPerPage = itemsPerPage
        self.persistenceURL = persistenceURL
    }

    func load(discoveredApps: [AppInfo] = AppDiscoveryService.scan()) {
        let savedLayout = LayoutPersistence.load(from: persistenceURL)
        pages = Self.merge(discoveredApps: discoveredApps, savedLayout: savedLayout, itemsPerPage: itemsPerPage)
        currentPage = 0
        searchQuery = ""
        scope = .all
        categoryOverrides = LayoutPersistence.loadDictionary(AppCategory.self, from: categoryOverridesURL)
        launchCounts = LayoutPersistence.loadDictionary(Int.self, from: launchCountsURL)
    }

    // The category a given app should actually be filtered/grouped under —
    // a manual override (dragged onto a different pill) if one exists,
    // otherwise whatever was auto-detected from Info.plist.
    func effectiveCategory(for app: AppInfo) -> AppCategory {
        categoryOverrides[app.bundleIdentifier] ?? app.category
    }

    // Called when the user drags an app icon onto a category pill in
    // `CategoryFilterBar` — reassigns it there from then on, independent of
    // whatever the app itself declares.
    func setCategoryOverride(_ category: AppCategory, forBundleIdentifier bundleIdentifier: String) {
        categoryOverrides[bundleIdentifier] = category
        try? LayoutPersistence.saveDictionary(categoryOverrides, to: categoryOverridesURL)
    }

    // Called by `AppDelegate` right before actually opening an app, so
    // "Most Used" reflects real usage instead of just grid position.
    func recordLaunch(_ app: AppInfo) {
        launchCounts[app.bundleIdentifier, default: 0] += 1
        try? LayoutPersistence.saveDictionary(launchCounts, to: launchCountsURL)
    }

    // Rebuilds the grid from scratch, alphabetically, exactly like a
    // first-ever launch — discards custom folders/ordering. Used by
    // Settings' "Reset Layout" (which confirms before calling this, since
    // it's a one-way trip for any manual organizing).
    func resetLayout(discoveredApps: [AppInfo] = AppDiscoveryService.scan()) {
        pages = Self.merge(discoveredApps: discoveredApps, savedLayout: nil, itemsPerPage: itemsPerPage)
        currentPage = 0
        save()
    }

    func save() {
        try? LayoutPersistence.save(Self.encode(pages: pages), to: persistenceURL)
    }

    // Bundles the grid layout together with manual category overrides —
    // everything a user would expect "their Launchpad setup" to mean —
    // into one file for Settings' Export/Import. Launch counts are left out
    // deliberately: usage history from one Mac isn't something you'd want
    // silently overwriting another's when importing.
    func exportLayout(to url: URL) throws {
        let bundle = LayoutExportBundle(layout: Self.encode(pages: pages), categoryOverrides: categoryOverrides)
        let data = try JSONEncoder().encode(bundle)
        try data.write(to: url, options: .atomic)
    }

    // Applies an exported bundle against whatever's actually installed on
    // *this* Mac — same reconciliation `load()` does against a saved
    // layout, so an app the export references but this machine doesn't
    // have is simply dropped rather than left as a dangling icon.
    func importLayout(from url: URL, discoveredApps: [AppInfo] = AppDiscoveryService.scan()) throws {
        let data = try Data(contentsOf: url)
        let bundle = try JSONDecoder().decode(LayoutExportBundle.self, from: data)
        pages = Self.merge(discoveredApps: discoveredApps, savedLayout: bundle.layout, itemsPerPage: itemsPerPage)
        categoryOverrides = bundle.categoryOverrides
        currentPage = 0
        searchQuery = ""
        scope = .all
        save()
        try? LayoutPersistence.saveDictionary(categoryOverrides, to: categoryOverridesURL)
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // True whenever the grid should switch from the normal paged view to
    // the flat, filtered one below — either a search is active, a category
    // (or "Recently Added") pill is selected, or both.
    var isFiltering: Bool {
        !trimmedSearchQuery.isEmpty || scope != .all
    }

    // Every app across every page/folder, flattened once — the base list
    // both `filteredResults` and `availableCategories` filter/derive from.
    private var allApps: [AppInfo] {
        pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
    }

    // The categories to actually show as pills: only ones that have at
    // least one installed app (checking `effectiveCategory`, so a manual
    // override can make a pill appear/disappear too), in stable declaration
    // order (mirrors Launchpad's own category list rather than sorting
    // alphabetically or by frequency).
    var availableCategories: [AppCategory] {
        let present = Set(allApps.map(effectiveCategory(for:)))
        return AppCategory.allCases.filter { present.contains($0) }
    }

    private func sorted(_ apps: [AppInfo]) -> [AppInfo] {
        switch sortOption {
        case .name:
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .mostUsed:
            return apps.sorted { lhs, rhs in
                let lhsCount = launchCounts[lhs.bundleIdentifier] ?? 0
                let rhsCount = launchCounts[rhs.bundleIdentifier] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    // The flat, filtered list search/category/"Recently Added" switch the
    // grid to — ignores pages and folders entirely, matching stock
    // Launchpad's search behavior. Shared by `LaunchpadView` (to render it)
    // and `OverlayWindowController` (to know what Return should launch, and
    // how many items arrow keys can move across, while filtering).
    var filteredResults: [AppInfo] {
        let scoped: [AppInfo]
        switch scope {
        case .all:
            scoped = allApps
        case .recentlyAdded:
            scoped = allApps.sorted { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        case .category(let category):
            scoped = allApps.filter { effectiveCategory(for: $0) == category }
        }

        guard !trimmedSearchQuery.isEmpty else {
            // "Recently Added" keeps its own date order regardless of
            // `sortOption` — same as stock Launchpad's equivalent view isn't
            // independently re-sortable either.
            return scope == .recentlyAdded ? scoped : sorted(scoped)
        }
        let matched = AppSearch.filter(scoped, query: searchQuery)
        // `AppSearch.filter` already sorts alphabetically on its own, but
        // re-sorting here lets "Most Used" apply while searching too,
        // instead of only in the unfiltered/category views.
        return scope == .recentlyAdded ? matched : sorted(matched)
    }

    // Removes an app wherever it is — loose on a page or tucked inside a
    // folder — and keeps everything downstream consistent: an emptied
    // folder is dropped, an emptied *page* is dropped too (and `currentPage`
    // adjusted so paging never lands on a blank grid), and the open folder
    // sheet (a separate snapshot, not a live view into `pages`) is kept in
    // sync if the removed app was inside it.
    func removeApp(_ app: AppInfo) {
        for pageIndex in pages.indices {
            for itemIndex in pages[pageIndex].indices {
                switch pages[pageIndex][itemIndex] {
                case .app(let existing) where existing.bundleIdentifier == app.bundleIdentifier:
                    pages[pageIndex].remove(at: itemIndex)
                    finishRemoval(pageIndex: pageIndex)
                    return
                case .folder(var folder):
                    guard let appIndex = folder.apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) else {
                        continue
                    }
                    let wasOpenFolder = openFolder?.id == folder.id
                    folder.apps.remove(at: appIndex)
                    if folder.apps.isEmpty {
                        pages[pageIndex].remove(at: itemIndex)
                        if wasOpenFolder { openFolder = nil }
                    } else {
                        pages[pageIndex][itemIndex] = .folder(folder)
                        if wasOpenFolder { openFolder = folder }
                    }
                    finishRemoval(pageIndex: pageIndex)
                    return
                default:
                    continue
                }
            }
        }
    }

    private func finishRemoval(pageIndex: Int) {
        if pages[pageIndex].isEmpty {
            pages.remove(at: pageIndex)
            if currentPage > pageIndex {
                currentPage -= 1
            } else if !pages.indices.contains(currentPage) {
                currentPage = max(0, pages.count - 1)
            }
        }
        save()
    }

    // Confirms, moves the app to the Trash, and — only once that actually
    // succeeds — removes it from the grid too, so a cancelled or failed
    // uninstall never leaves a dangling icon for an app that's still there.
    func uninstallApp(_ app: AppInfo) {
        guard AppUninstaller.moveToTrash(app) else { return }
        removeApp(app)
    }

    func toggleSelection(_ app: AppInfo) {
        if selectedBundleIdentifiers.contains(app.bundleIdentifier) {
            selectedBundleIdentifiers.remove(app.bundleIdentifier)
        } else {
            selectedBundleIdentifiers.insert(app.bundleIdentifier)
        }
    }

    func clearSelection() {
        selectedBundleIdentifiers.removeAll()
    }

    private var selectedApps: [AppInfo] {
        let allApps = pages.flatMap { $0 }.flatMap { item -> [AppInfo] in
            switch item {
            case .app(let app): return [app]
            case .folder(let folder): return folder.apps
            }
        }
        return allApps.filter { selectedBundleIdentifiers.contains($0.bundleIdentifier) }
    }

    func removeSelectedApps() {
        for app in selectedApps { removeApp(app) }
        clearSelection()
    }

    func uninstallSelectedApps() {
        let apps = selectedApps
        guard !apps.isEmpty, AppUninstaller.moveToTrash(apps) else { return }
        for app in apps { removeApp(app) }
        clearSelection()
    }

    // Merges every multi-selected app (except the target itself) into the
    // drop target — an existing folder, or a freshly created one if the
    // target was a loose app — wherever each of them currently lives,
    // possibly spread across several pages/folders. Runs as one pass over a
    // working copy of `pages` (collect + strip, then re-locate the target
    // and insert) instead of removing one at a time, so an earlier removal
    // pruning an empty page never invalidates an index computed earlier.
    func mergeSelectedApps(intoTarget targetItem: LaunchpadItem) {
        let targetAnchorID: String
        let excludeIDs: Set<String>
        switch targetItem {
        case .app(let app):
            targetAnchorID = app.bundleIdentifier
            excludeIDs = [app.bundleIdentifier]
        case .folder(let folder):
            targetAnchorID = folder.id
            excludeIDs = Set(folder.apps.map(\.bundleIdentifier))
        }

        let idsToMove = selectedBundleIdentifiers.subtracting(excludeIDs)
        guard !idsToMove.isEmpty else { return }

        var workingPages = pages
        var collectedApps: [AppInfo] = []

        for pageIndex in workingPages.indices {
            workingPages[pageIndex] = workingPages[pageIndex].compactMap { item -> LaunchpadItem? in
                switch item {
                case .app(let app):
                    guard idsToMove.contains(app.bundleIdentifier) else { return item }
                    collectedApps.append(app)
                    return nil
                case .folder(var folder):
                    let matching = folder.apps.filter { idsToMove.contains($0.bundleIdentifier) }
                    guard !matching.isEmpty else { return item }
                    collectedApps.append(contentsOf: matching)
                    folder.apps.removeAll { idsToMove.contains($0.bundleIdentifier) }
                    return folder.apps.isEmpty ? nil : .folder(folder)
                }
            }
        }
        workingPages.removeAll { $0.isEmpty }

        search: for pageIndex in workingPages.indices {
            for itemIndex in workingPages[pageIndex].indices {
                switch workingPages[pageIndex][itemIndex] {
                case .app(let app) where app.bundleIdentifier == targetAnchorID:
                    let merged = FolderInfo(name: "Folder", apps: [app] + collectedApps)
                    workingPages[pageIndex][itemIndex] = .folder(merged)
                    break search
                case .folder(let folder) where folder.id == targetAnchorID:
                    var merged = folder
                    merged.apps.append(contentsOf: collectedApps)
                    workingPages[pageIndex][itemIndex] = .folder(merged)
                    break search
                default:
                    continue
                }
            }
        }

        pages = workingPages
        if !pages.indices.contains(currentPage) {
            currentPage = max(0, pages.count - 1)
        }
        openFolder = nil // whatever was open may have just been mutated out from under it
        clearSelection()
        save()
    }

    // Renames a folder in place (matched by its pre-rename `id`, since that
    // id is derived from its name+contents) and keeps the open folder sheet
    // — a separate snapshot — in sync if it's the one being renamed.
    func renameFolder(_ folder: FolderInfo, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }

        for pageIndex in pages.indices {
            for itemIndex in pages[pageIndex].indices {
                guard case .folder(var existing) = pages[pageIndex][itemIndex], existing.id == folder.id else { continue }
                existing.name = trimmed
                pages[pageIndex][itemIndex] = .folder(existing)
                if openFolder?.id == folder.id {
                    openFolder = existing
                }
                save()
                return
            }
        }
    }

    // Matches stock macOS Launchpad grouping its built-in utility apps
    // (Terminal, Console, Disk Utility, Activity Monitor, ...) into one
    // "Other" folder rather than scattering them across the main grid.
    static let systemUtilitiesPathPrefix = "/System/Applications/Utilities/"
    static let systemUtilitiesFolderName = "Other"

    static func merge(discoveredApps: [AppInfo], savedLayout: LayoutFile?, itemsPerPage: Int) -> [[LaunchpadItem]] {
        var appsByID = Dictionary(uniqueKeysWithValues: discoveredApps.map { ($0.bundleIdentifier, $0) })
        var orderedItems: [LaunchpadItem] = []

        if let savedLayout {
            for page in savedLayout.pages {
                for item in page {
                    switch item {
                    case .app(let bundleIdentifier):
                        if let matchedApp = appsByID.removeValue(forKey: bundleIdentifier) {
                            orderedItems.append(.app(matchedApp))
                        }
                    case .folder(let name, let bundleIdentifiers):
                        let folderApps = bundleIdentifiers.compactMap { appsByID.removeValue(forKey: $0) }
                        if !folderApps.isEmpty {
                            orderedItems.append(.folder(FolderInfo(name: name, apps: folderApps)))
                        }
                    }
                }
            }
        }

        // Apps not already placed by a saved layout (including everything,
        // the first time the app ever runs): sort alphabetically, but pull
        // out anything under /System/Applications/Utilities into one shared
        // "Other" folder instead of leaving them loose on the grid.
        let remainingApps = discoveredApps
            .filter { appsByID[$0.bundleIdentifier] != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let remainingUtilities = remainingApps.filter { $0.path.path.hasPrefix(systemUtilitiesPathPrefix) }
        let remainingOthers = remainingApps.filter { !$0.path.path.hasPrefix(systemUtilitiesPathPrefix) }

        orderedItems.append(contentsOf: remainingOthers.map(LaunchpadItem.app))
        if !remainingUtilities.isEmpty {
            orderedItems.append(.folder(FolderInfo(name: systemUtilitiesFolderName, apps: remainingUtilities)))
        }

        guard !orderedItems.isEmpty else { return [] }
        return stride(from: 0, to: orderedItems.count, by: itemsPerPage).map {
            Array(orderedItems[$0..<min($0 + itemsPerPage, orderedItems.count)])
        }
    }

    static func mergingIntoFolder(sourceIndex: Int, targetIndex: Int, items: [LaunchpadItem]) -> [LaunchpadItem] {
        guard items.indices.contains(sourceIndex), items.indices.contains(targetIndex), sourceIndex != targetIndex else {
            return items
        }
        var result = items
        let source = result[sourceIndex]
        let target = result[targetIndex]

        let mergedFolder: FolderInfo
        switch (source, target) {
        case (.app(let sourceApp), .app(let targetApp)):
            mergedFolder = FolderInfo(name: "Folder", apps: [targetApp, sourceApp])
        case (.app(let sourceApp), .folder(var targetFolder)):
            targetFolder.apps.append(sourceApp)
            mergedFolder = targetFolder
        default:
            return items
        }

        result[targetIndex] = .folder(mergedFolder)
        result.remove(at: sourceIndex)
        return result
    }

    static func encode(pages: [[LaunchpadItem]]) -> LayoutFile {
        LayoutFile(pages: pages.map { page in
            page.map { item in
                switch item {
                case .app(let appInfo):
                    return LayoutItem.app(bundleIdentifier: appInfo.bundleIdentifier)
                case .folder(let folder):
                    return LayoutItem.folder(name: folder.name, bundleIdentifiers: folder.apps.map(\.bundleIdentifier))
                }
            }
        })
    }
}
