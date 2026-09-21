import Foundation
import Combine

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
        didSet { selectedIndex = 0 }
    }
    @Published var searchQuery: String = "" {
        didSet { selectedIndex = 0 }
    }

    // Index of the keyboard-highlighted icon within whatever's currently
    // visible (the current page's items, or `searchResults` while
    // searching) — driven by `OverlayWindowController`'s arrow-key monitor.
    @Published var selectedIndex: Int = 0
    // Which folder popup is open, if any. Lives here (rather than as
    // view-local state in `PageView`) so pressing Return on a
    // keyboard-selected folder can open it from `OverlayWindowController`,
    // outside the SwiftUI view tree.
    @Published var openFolder: FolderInfo?

    private let itemsPerPage: Int
    private let persistenceURL: URL

    init(itemsPerPage: Int = 35, persistenceURL: URL = LayoutPersistence.defaultURL()) {
        self.itemsPerPage = itemsPerPage
        self.persistenceURL = persistenceURL
    }

    func load(discoveredApps: [AppInfo] = AppDiscoveryService.scan()) {
        let savedLayout = LayoutPersistence.load(from: persistenceURL)
        pages = Self.merge(discoveredApps: discoveredApps, savedLayout: savedLayout, itemsPerPage: itemsPerPage)
        currentPage = 0
        searchQuery = ""
    }

    func save() {
        try? LayoutPersistence.save(Self.encode(pages: pages), to: persistenceURL)
    }

    // The flat, filtered list search switches the grid to — ignores pages
    // and folders entirely, matching stock Launchpad's search behavior.
    // Shared by `LaunchpadView` (to render it) and `OverlayWindowController`
    // (to know what Return should launch while searching).
    var searchResults: [AppInfo] {
        let allApps = pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
        return AppSearch.filter(allApps, query: searchQuery)
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
