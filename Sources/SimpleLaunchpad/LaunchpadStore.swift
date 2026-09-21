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

    private let itemsPerPage: Int
    private let persistenceURL: URL

    init(itemsPerPage: Int = 35, persistenceURL: URL = LayoutPersistence.defaultURL()) {
        self.itemsPerPage = itemsPerPage
        self.persistenceURL = persistenceURL
    }

    func load(discoveredApps: [AppInfo] = AppDiscoveryService.scan()) {
        let savedLayout = LayoutPersistence.load(from: persistenceURL)
        pages = Self.merge(discoveredApps: discoveredApps, savedLayout: savedLayout, itemsPerPage: itemsPerPage)
    }

    func save() {
        try? LayoutPersistence.save(Self.encode(pages: pages), to: persistenceURL)
    }

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

        let remainingApps = discoveredApps
            .filter { appsByID[$0.bundleIdentifier] != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        orderedItems.append(contentsOf: remainingApps.map(LaunchpadItem.app))

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
