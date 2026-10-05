// Run with: bash Scripts/check-regressions.sh (no XCTest or installed app required).
import Foundation
import Combine

@main
struct RegressionChecks {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LaunchpadStore(itemsPerPage: 2, persistenceURL: directory.appendingPathComponent("layout.json"))
        let apps = ["A", "B", "C", "D"].map {
            AppInfo(bundleIdentifier: $0, name: $0, path: directory.appendingPathComponent($0 + ".app"))
        }
        let items = apps.map(LaunchpadItem.app)
        store.pages = [[items[0], items[1]], [items[2], items[3]]]
        store.moveItem(items[0].dragID, onto: items[2].dragID, merge: false)
        assert(store.pages == [[items[1]], [items[0], items[2]], [items[3]]])
        assert(store.currentPage == 1)
        assert(LayoutPersistence.load(from: directory.appendingPathComponent("layout.json"))?.pages == LaunchpadStore.encode(pages: store.pages).pages)

        store.pages = [[items[0]], [items[1]]]
        store.moveItem(items[0].dragID, onto: items[1].dragID, merge: true)
        assert(store.pages == [[.folder(FolderInfo(name: "Folder", apps: [apps[1], apps[0]]))]])
        assert(store.currentPage == 0)
        let unchanged = store.pages
        store.moveItem("APP:missing", onto: items[1].dragID, merge: false)
        assert(store.pages == unchanged)

        store.pages = [[items[0], items[1]]]
        store.moveItem(items[0].dragID, onto: items[1].dragID, merge: false)
        assert(store.pages == [[items[1], items[0]]])
        store.moveItem(items[0].dragID, onto: items[1].dragID, merge: false)
        assert(store.pages == [[items[0], items[1]]])

        store.selectedBundleIdentifiers = ["A", "B"]
        store.uninstallSelectedApps { selected in
            let (removed, failures) = AppUninstaller.trashApps(selected) { app in
                if app.bundleIdentifier == "B" { throw CocoaError(.fileWriteNoPermission) }
            }
            assert(removed == [apps[0]] && failures == ["B"])
            return removed
        }
        assert(store.pages == [[items[1]]])
        assert(store.selectedBundleIdentifiers == ["B"])
        store.uninstallSelectedApps { _ in [] }
        assert(store.pages == [[items[1]]] && store.selectedBundleIdentifiers == ["B"])

        // Hidden apps survive reload/export/import; Reset restores them. Old files still load.
        store.resetLayout(discoveredApps: apps)
        store.removeApp(apps[0])
        store.setCategoryOverride(.games, forBundleIdentifier: "B")
        let reloaded = LaunchpadStore(persistenceURL: directory.appendingPathComponent("layout.json"))
        reloaded.load(discoveredApps: apps)
        assert(!reloaded.pages.flatMap { $0 }.contains(items[0]))
        assert(reloaded.categoryOverrides["B"] == .games)
        let export = directory.appendingPathComponent("export.json")
        try reloaded.exportLayout(to: export)
        store.resetLayout(discoveredApps: apps)
        assert(store.pages.flatMap { $0 }.contains(items[0]))
        try store.importLayout(from: export, discoveredApps: apps)
        assert(!store.pages.flatMap { $0 }.contains(items[0]))
        let legacy = try JSONDecoder().decode(LayoutFile.self, from: Data("{\"pages\":[]}".utf8))
        assert(legacy.hiddenBundleIdentifiers == nil && legacy.categoryOverrides == nil)
        let legacyDirectory = directory.appendingPathComponent("legacy")
        let legacyURL = legacyDirectory.appendingPathComponent("layout.json")
        try LayoutPersistence.save(legacy, to: legacyURL)
        try LayoutPersistence.saveDictionary(["A": AppCategory.games], to: legacyDirectory.appendingPathComponent("categoryOverrides.json"))
        let legacyStore = LaunchpadStore(persistenceURL: legacyURL)
        legacyStore.load(discoveredApps: apps)
        assert(legacyStore.categoryOverrides == ["A": .games])
        legacyStore.pages = [[.folder(FolderInfo(name: "Folder", apps: [apps[0], apps[1]]))]]
        legacyStore.removeApp(apps[0])
        legacyStore.load(discoveredApps: [apps[0], apps[1]])
        assert(legacyStore.pages == [[.folder(FolderInfo(name: "Folder", apps: [apps[1]]))]])
        assert(legacyStore.categoryOverrides == ["A": .games])

        store.openFolder = FolderInfo(name: "Folder", apps: [apps[1]])
        store.isEditingFolderName = true
        store.openFolder = nil
        assert(!store.isEditingFolderName)

        // A missing or renamed bulk target must preserve both layout and selection.
        store.resetLayout(discoveredApps: [apps[0], apps[1]])
        store.selectedBundleIdentifiers = ["A"]
        let beforeDrop = store.pages
        store.mergeSelectedApps(intoTarget: items[2])
        assert(store.pages == beforeDrop && store.selectedBundleIdentifiers == ["A"])
        store.mergeSelectedApps(intoTarget: items[1])
        assert(store.pages == [[.folder(FolderInfo(name: "Folder", apps: [apps[1], apps[0]]))]])
        let staleFolder = store.pages[0][0]
        if case .folder(let folder) = staleFolder { store.renameFolder(folder, to: "Renamed") }
        store.pages.append([items[2]])
        store.selectedBundleIdentifiers = ["C"]
        let beforeStaleDrop = store.pages
        store.mergeSelectedApps(intoTarget: staleFolder)
        assert(store.pages == beforeStaleDrop && store.selectedBundleIdentifiers == ["C"])

        // Make writes fail without touching permissions or real application data.
        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: blockedParent)
        let blockedStore = LaunchpadStore(persistenceURL: blockedParent.appendingPathComponent("layout.json"))
        blockedStore.pages = [[items[3]]]
        blockedStore.categoryOverrides = ["D": .productivity]
        do {
            try blockedStore.importLayout(from: export, discoveredApps: apps)
            assertionFailure("Failed persistence must fail the import")
        } catch {
            assert(blockedStore.pages == [[items[3]]])
            assert(blockedStore.categoryOverrides == ["D": .productivity])
            let original = try Data(contentsOf: blockedParent)
            assert(original == Data("keep".utf8))
        }

        // More than a pipe buffer, on both output streams: waiting before reading deadlocks.
        let output = try UpdateChecker.run("/bin/sh", ["-c", "head -c 262144 /dev/zero; head -c 262144 /dev/zero >&2"])
        assert(output.utf8.count == 524288)
        do {
            try UpdateChecker.run("/bin/sh", ["-c", "printf failure >&2; exit 7"])
            assertionFailure("Nonzero exit must throw")
        } catch {
            assert((error as NSError).code == 7 && error.localizedDescription == "failure")
        }
        // Failed extraction must leave the existing installation untouched.
        let installed = directory.appendingPathComponent("Installed.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let marker = installed.appendingPathComponent("keep")
        try Data("original".utf8).write(to: marker)
        do {
            try await UpdateChecker.installArchive(directory.appendingPathComponent("missing.zip"), at: installed)
            assertionFailure("Missing archive must throw")
        } catch {
            let contents = try Data(contentsOf: marker)
            assert(contents == Data("original".utf8))
        }

        // @Published emits before storage changes: use emitted values for registration.
        final class Shortcut {
            @Published var keyCode = 1
            @Published var modifiers = 0
        }
        let shortcut = Shortcut()
        var registered = (0, 0)
        let subscription = Publishers.CombineLatest(shortcut.$keyCode, shortcut.$modifiers)
            .sink { code, modifiers in registered = (code, modifiers) }
        shortcut.keyCode = 2
        shortcut.modifiers = 8
        assert(registered == (2, 8))
        withExtendedLifetime(subscription) {}
        print("Regression checks passed: drag/reorder/merge, partial trash failure, updater output/errors, shortcut values, hidden apps, rename cleanup, stale drops, atomic import.")
    }
}
