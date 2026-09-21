# Simple Launchpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS Launchpad clone (menu bar + hotkey activated fullscreen app grid with paging, search, drag-to-reorder, and folders) as a Swift Package Manager project with PR-triggered CI.

**Architecture:** SwiftUI renders the grid/paging/search/folder UI; a thin AppKit layer (borderless fullscreen `NSWindow`, `NSStatusItem`, Carbon global hotkey) drives activation. Pure, unit-tested logic (app discovery, layout persistence, merge, search, folder-merge) lives in plain Swift types with no AppKit/SwiftUI dependency so it's testable without a UI.

**Tech Stack:** Swift 5.9+, Swift Package Manager, SwiftUI, AppKit, Carbon (`RegisterEventHotKey`), XCTest, GitHub Actions (macos-latest).

**Spec:** `docs/superpowers/specs/2026-09-21-simple-launchpad-design.md`

## Global Constraints

- Target macOS 13+ (`platforms: [.macOS(.v13)]` in Package.swift).
- No third-party dependencies — only system frameworks (Foundation, AppKit, SwiftUI, Carbon, Combine, XCTest).
- No code signing / notarization / auto-release — out of scope per spec's Non-goals.
- No settings UI — hardcoded defaults (F4 hotkey, no custom app icon).
- CI runs only on `pull_request` events, on `macos-latest`, running `swift build` + `swift test`.
- Unit tests only (XCTest) — no UI/snapshot tests, per spec's Testing section.

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/SimpleLaunchpad/App.swift`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a buildable, empty SPM executable target named `SimpleLaunchpad`, and a test target `SimpleLaunchpadTests` that later tasks add test files to.

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SimpleLaunchpad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SimpleLaunchpad",
            path: "Sources/SimpleLaunchpad"
        ),
        .testTarget(
            name: "SimpleLaunchpadTests",
            dependencies: ["SimpleLaunchpad"],
            path: "Tests/SimpleLaunchpadTests"
        )
    ]
)
```

- [ ] **Step 2: Create `Sources/SimpleLaunchpad/App.swift`**

```swift
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {}
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/SimpleLaunchpad/App.swift
git commit -m "chore: scaffold SimpleLaunchpad SPM executable target"
```

---

### Task 2: AppDiscoveryService

**Files:**
- Create: `Sources/SimpleLaunchpad/AppDiscoveryService.swift`
- Test: `Tests/SimpleLaunchpadTests/AppDiscoveryServiceTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `struct AppInfo: Equatable, Codable { let bundleIdentifier: String; let name: String; let path: URL }` and `enum AppDiscoveryService { static func scan(searchPaths: [String] = defaultSearchPaths, fileManager: FileManager = .default) -> [AppInfo] }`. Later tasks (`LaunchpadStore`, views) construct and consume `AppInfo` values and call `AppDiscoveryService.scan()`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SimpleLaunchpadTests/AppDiscoveryServiceTests.swift`:

```swift
import XCTest
@testable import SimpleLaunchpad

final class AppDiscoveryServiceTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFakeApp(name: String, bundleIdentifier: String?, bundleName: String?) throws {
        let appURL = tempDir.appendingPathComponent("\(name).app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        var info: [String: Any] = [:]
        if let bundleIdentifier { info["CFBundleIdentifier"] = bundleIdentifier }
        if let bundleName { info["CFBundleName"] = bundleName }
        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: plistURL)
    }

    func testScanFindsAppWithInfoPlist() throws {
        try makeFakeApp(name: "Foo", bundleIdentifier: "com.example.foo", bundleName: "Foo App")

        let results = AppDiscoveryService.scan(searchPaths: [tempDir.path])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].bundleIdentifier, "com.example.foo")
        XCTAssertEqual(results[0].name, "Foo App")
    }

    func testScanFallsBackToFolderNameWhenInfoPlistIncomplete() throws {
        try makeFakeApp(name: "Bar", bundleIdentifier: nil, bundleName: nil)

        let results = AppDiscoveryService.scan(searchPaths: [tempDir.path])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].bundleIdentifier, "Bar")
        XCTAssertEqual(results[0].name, "Bar")
    }

    func testScanIgnoresNonAppEntries() throws {
        let fileURL = tempDir.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let results = AppDiscoveryService.scan(searchPaths: [tempDir.path])

        XCTAssertTrue(results.isEmpty)
    }

    func testScanSkipsUnreadableSearchPaths() {
        let results = AppDiscoveryService.scan(searchPaths: ["/nonexistent/path/for/test"])

        XCTAssertTrue(results.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppDiscoveryServiceTests`
Expected: FAIL to compile — `AppDiscoveryService` / `AppInfo` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpleLaunchpad/AppDiscoveryService.swift`:

```swift
import Foundation

struct AppInfo: Equatable, Codable {
    let bundleIdentifier: String
    let name: String
    let path: URL
}

enum AppDiscoveryService {
    static let defaultSearchPaths: [String] = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities"
    ]

    static func scan(searchPaths: [String] = defaultSearchPaths, fileManager: FileManager = .default) -> [AppInfo] {
        var results: [AppInfo] = []
        for searchPath in searchPaths {
            guard let entries = try? fileManager.contentsOfDirectory(atPath: searchPath) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let appPath = searchPath + "/" + entry
                let url = URL(fileURLWithPath: appPath)
                guard let bundle = Bundle(url: url) else { continue }
                let fallbackName = url.deletingPathExtension().lastPathComponent
                let bundleIdentifier = bundle.bundleIdentifier ?? fallbackName
                let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? fallbackName
                results.append(AppInfo(bundleIdentifier: bundleIdentifier, name: name, path: url))
            }
        }
        return results
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppDiscoveryServiceTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/AppDiscoveryService.swift Tests/SimpleLaunchpadTests/AppDiscoveryServiceTests.swift
git commit -m "feat: scan Applications folders for installed apps"
```

---

### Task 3: LayoutPersistence

**Files:**
- Create: `Sources/SimpleLaunchpad/LayoutPersistence.swift`
- Test: `Tests/SimpleLaunchpadTests/LayoutPersistenceTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `struct LayoutFile: Codable, Equatable { var pages: [[LayoutItem]] }`, `enum LayoutItem: Codable, Equatable { case app(bundleIdentifier: String); case folder(name: String, bundleIdentifiers: [String]) }`, `enum LayoutPersistence { static func defaultURL(fileManager: FileManager = .default) -> URL; static func load(from url: URL) -> LayoutFile?; static func save(_ layout: LayoutFile, to url: URL) throws }`. `LaunchpadStore` (Task 4) is the consumer.

- [ ] **Step 1: Write the failing test**

Create `Tests/SimpleLaunchpadTests/LayoutPersistenceTests.swift`:

```swift
import XCTest
@testable import SimpleLaunchpad

final class LayoutPersistenceTests: XCTestCase {
    var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("layout.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    func testSaveThenLoadRoundTrips() throws {
        let layout = LayoutFile(pages: [
            [.app(bundleIdentifier: "com.example.a"),
             .folder(name: "Utilities", bundleIdentifiers: ["com.example.b", "com.example.c"])]
        ])

        try LayoutPersistence.save(layout, to: fileURL)
        let loaded = LayoutPersistence.load(from: fileURL)

        XCTAssertEqual(loaded, layout)
    }

    func testLoadReturnsNilWhenFileMissing() {
        let loaded = LayoutPersistence.load(from: fileURL)

        XCTAssertNil(loaded)
    }

    func testLoadReturnsNilWhenFileIsCorrupt() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = LayoutPersistence.load(from: fileURL)

        XCTAssertNil(loaded)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LayoutPersistenceTests`
Expected: FAIL to compile — `LayoutFile` / `LayoutPersistence` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpleLaunchpad/LayoutPersistence.swift`:

```swift
import Foundation

struct LayoutFile: Codable, Equatable {
    var pages: [[LayoutItem]]
}

enum LayoutItem: Codable, Equatable {
    case app(bundleIdentifier: String)
    case folder(name: String, bundleIdentifiers: [String])

    private enum CodingKeys: String, CodingKey {
        case type, bundleIdentifier, name, bundleIdentifiers
    }

    private enum Kind: String, Codable {
        case app, folder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .app:
            let id = try container.decode(String.self, forKey: .bundleIdentifier)
            self = .app(bundleIdentifier: id)
        case .folder:
            let name = try container.decode(String.self, forKey: .name)
            let ids = try container.decode([String].self, forKey: .bundleIdentifiers)
            self = .folder(name: name, bundleIdentifiers: ids)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleIdentifier):
            try container.encode(Kind.app, forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case .folder(let name, let bundleIdentifiers):
            try container.encode(Kind.folder, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(bundleIdentifiers, forKey: .bundleIdentifiers)
        }
    }
}

enum LayoutPersistence {
    static func defaultURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SimpleLaunchpad", isDirectory: true)
            .appendingPathComponent("layout.json")
    }

    static func load(from url: URL) -> LayoutFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LayoutFile.self, from: data)
    }

    static func save(_ layout: LayoutFile, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(layout)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LayoutPersistenceTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/LayoutPersistence.swift Tests/SimpleLaunchpadTests/LayoutPersistenceTests.swift
git commit -m "feat: persist launchpad layout to JSON"
```

---

### Task 4: LaunchpadStore (merge + folder logic)

**Files:**
- Create: `Sources/SimpleLaunchpad/LaunchpadStore.swift`
- Test: `Tests/SimpleLaunchpadTests/LaunchpadStoreTests.swift`

**Interfaces:**
- Consumes: `AppInfo` (Task 2), `LayoutFile`/`LayoutItem`/`LayoutPersistence` (Task 3)
- Produces: `struct FolderInfo: Equatable { var name: String; var apps: [AppInfo] }`, `enum LaunchpadItem: Equatable { case app(AppInfo); case folder(FolderInfo) }`, `final class LaunchpadStore: ObservableObject { @Published var pages: [[LaunchpadItem]]; init(itemsPerPage: Int = 35, persistenceURL: URL = LayoutPersistence.defaultURL()); func load(discoveredApps: [AppInfo] = AppDiscoveryService.scan()); func save(); static func merge(discoveredApps: [AppInfo], savedLayout: LayoutFile?, itemsPerPage: Int) -> [[LaunchpadItem]]; static func mergingIntoFolder(sourceIndex: Int, targetIndex: Int, items: [LaunchpadItem]) -> [LaunchpadItem] }`. Views (Task 9) and `OverlayWindowController` (Task 8) consume `LaunchpadStore`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/SimpleLaunchpadTests/LaunchpadStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LaunchpadStoreTests`
Expected: FAIL to compile — `LaunchpadStore` / `LaunchpadItem` / `FolderInfo` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpleLaunchpad/LaunchpadStore.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LaunchpadStoreTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/LaunchpadStore.swift Tests/SimpleLaunchpadTests/LaunchpadStoreTests.swift
git commit -m "feat: add LaunchpadStore with merge and folder-creation logic"
```

---

### Task 5: AppSearch

**Files:**
- Create: `Sources/SimpleLaunchpad/AppSearch.swift`
- Test: `Tests/SimpleLaunchpadTests/AppSearchTests.swift`

**Interfaces:**
- Consumes: `AppInfo` (Task 2)
- Produces: `enum AppSearch { static func filter(_ apps: [AppInfo], query: String) -> [AppInfo] }`. Consumed by `LaunchpadView` (Task 9).

- [ ] **Step 1: Write the failing test**

Create `Tests/SimpleLaunchpadTests/AppSearchTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSearchTests`
Expected: FAIL to compile — `AppSearch` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpleLaunchpad/AppSearch.swift`:

```swift
import Foundation

enum AppSearch {
    static func filter(_ apps: [AppInfo], query: String) -> [AppInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return apps
            .filter { $0.name.range(of: trimmed, options: .caseInsensitive) != nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSearchTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/AppSearch.swift Tests/SimpleLaunchpadTests/AppSearchTests.swift
git commit -m "feat: add case-insensitive app name search"
```

---

### Task 6: HotKeyManager

**Files:**
- Create: `Sources/SimpleLaunchpad/HotKeyManager.swift`
- Test: `Tests/SimpleLaunchpadTests/HotKeyManagerTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `final class HotKeyManager { init(onTrigger: @escaping () -> Void); func register(keyCode: UInt32 = UInt32(kVK_F4), modifiers: UInt32 = 0); func handleTrigger() }`. Consumed by `App.swift` (Task 10).

Note: `register()` touches real OS global hotkey state via Carbon and is not exercised in the unit test (would be flaky/order-dependent in CI); only the internal trigger dispatch (`handleTrigger`) is tested here.

- [ ] **Step 1: Write the failing test**

Create `Tests/SimpleLaunchpadTests/HotKeyManagerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotKeyManagerTests`
Expected: FAIL to compile — `HotKeyManager` not found.

- [ ] **Step 3: Write the implementation**

Create `Sources/SimpleLaunchpad/HotKeyManager.swift`:

```swift
import Carbon
import AppKit

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register(keyCode: UInt32 = UInt32(kVK_F4), modifiers: UInt32 = 0) {
        let hotKeyID = EventHotKeyID(signature: OSType(1_397_509_699), id: 1) // 'SLPD'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleTrigger()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("SimpleLaunchpad: failed to register global hotkey (status \(status))")
        }
    }

    func handleTrigger() {
        onTrigger()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotKeyManagerTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/HotKeyManager.swift Tests/SimpleLaunchpadTests/HotKeyManagerTests.swift
git commit -m "feat: add global hotkey registration via Carbon"
```

---

### Task 7: StatusItemController

**Files:**
- Create: `Sources/SimpleLaunchpad/StatusItemController.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `final class StatusItemController { init(onToggle: @escaping () -> Void) }`. Consumed by `App.swift` (Task 10).

No XCTest here: creating a real `NSStatusItem` requires a running `NSApplication` with a menu bar / window server session, which is not reliably available headless in CI — consistent with the spec's "no UI tests" scope. Verified manually in Task 10's smoke test instead.

- [ ] **Step 1: Write the implementation**

Create `Sources/SimpleLaunchpad/StatusItemController.swift`:

```swift
import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem

    init(onToggle: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onToggle = onToggle
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Launchpad")
            button.target = self
            button.action = #selector(handleClick)
        }
    }

    private let onToggle: () -> Void

    @objc private func handleClick() {
        onToggle()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/SimpleLaunchpad/StatusItemController.swift
git commit -m "feat: add menu bar status item controller"
```

---

### Task 8: OverlayWindowController

**Files:**
- Create: `Sources/SimpleLaunchpad/OverlayWindowController.swift`
- Test: `Tests/SimpleLaunchpadTests/OverlayKeyHandlingTests.swift`

**Interfaces:**
- Consumes: `LaunchpadStore` (Task 4), `AppInfo` (Task 2), `LaunchpadView` (Task 9 — this task's implementation step assumes `LaunchpadView(store:onSelect:onDismiss:)` already exists; implement Task 9 first, or implement Task 8 last if executing out of written order)
- Produces: `enum OverlayKeyHandling { static func shouldClose(forKeyCode keyCode: UInt16) -> Bool }`, `final class OverlayWindowController: NSWindowController { init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void); func show(); func hide(); func toggle() }`. Consumed by `App.swift` (Task 10).

**Note on ordering:** This task's implementation references `LaunchpadView`. Implement Task 9 (Views) before this task's Step 3, even though it's numbered after. The `OverlayKeyHandlingTests` (Step 1-2) have no such dependency and can be done in order.

- [ ] **Step 1: Write the failing test**

Create `Tests/SimpleLaunchpadTests/OverlayKeyHandlingTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter OverlayKeyHandlingTests`
Expected: FAIL to compile — `OverlayKeyHandling` not found.

- [ ] **Step 3: Write the implementation (after Task 9 is done)**

Create `Sources/SimpleLaunchpad/OverlayWindowController.swift`:

```swift
import AppKit
import SwiftUI

enum OverlayKeyHandling {
    static func shouldClose(forKeyCode keyCode: UInt16) -> Bool {
        keyCode == 53 // Esc
    }
}

final class OverlayWindowController: NSWindowController {
    private var keyMonitor: Any?

    init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.4)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)

        window.contentView = NSHostingView(rootView: LaunchpadView(
            store: store,
            onSelect: { app in
                onLaunch(app)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if OverlayKeyHandling.shouldClose(forKeyCode: event.keyCode) {
                self.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        window?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func toggle() {
        guard let window else { return }
        window.isVisible ? hide() : show()
    }
}
```

Note: launching an app does not automatically hide the overlay here — wire `onLaunch` in `App.swift` (Task 10) to also call `overlayController.hide()` if that's the desired behavior, or leave it open per the spec's "closes on ... launching an app" — Task 10 sets this up explicitly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OverlayKeyHandlingTests`
Expected: PASS (2 tests).

Run: `swift build`
Expected: `Build complete!` with no errors (validates it compiles against `LaunchpadView` from Task 9).

- [ ] **Step 5: Commit**

```bash
git add Sources/SimpleLaunchpad/OverlayWindowController.swift Tests/SimpleLaunchpadTests/OverlayKeyHandlingTests.swift
git commit -m "feat: add fullscreen overlay window with Esc-to-close"
```

---

### Task 9: SwiftUI views (grid, paging, folders, search)

**Files:**
- Create: `Sources/SimpleLaunchpad/Views/AppIconView.swift`
- Create: `Sources/SimpleLaunchpad/Views/FolderIconView.swift`
- Create: `Sources/SimpleLaunchpad/Views/FolderView.swift`
- Create: `Sources/SimpleLaunchpad/Views/SearchField.swift`
- Create: `Sources/SimpleLaunchpad/Views/PageView.swift`
- Create: `Sources/SimpleLaunchpad/Views/LaunchpadView.swift`

**Interfaces:**
- Consumes: `AppInfo`, `LaunchpadItem`, `FolderInfo`, `LaunchpadStore` (Task 4), `AppSearch` (Task 5)
- Produces: `struct LaunchpadView: View { init(store: LaunchpadStore, onSelect: @escaping (AppInfo) -> Void, onDismiss: @escaping () -> Void) }`. Consumed by `OverlayWindowController` (Task 8).

No XCTest here — SwiftUI view rendering is out of scope for unit tests per spec. Verified manually via `swift run` in Task 10's smoke test.

- [ ] **Step 1: Create `Sources/SimpleLaunchpad/Views/AppIconView.swift`**

```swift
import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppInfo

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: 64, height: 64)
            Text(app.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: 90, height: 100)
    }
}
```

- [ ] **Step 2: Create `Sources/SimpleLaunchpad/Views/FolderIconView.swift`**

```swift
import SwiftUI
import AppKit

struct FolderIconView: View {
    let folder: FolderInfo

    private let columns = [GridItem(.fixed(26)), GridItem(.fixed(26))]

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(folder.apps.prefix(4)), id: \.bundleIdentifier) { app in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                }
            }
            .padding(6)
            .frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
            Text(folder.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: 90, height: 100)
    }
}
```

- [ ] **Step 3: Create `Sources/SimpleLaunchpad/Views/FolderView.swift`**

```swift
import SwiftUI

struct FolderView: View {
    let folder: FolderInfo
    let onSelect: (AppInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.fixed(90), spacing: 24), count: 5)

    var body: some View {
        VStack(spacing: 20) {
            Text(folder.name)
                .font(.title2)
                .foregroundColor(.white)
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(folder.apps, id: \.bundleIdentifier) { app in
                    AppIconView(app: app)
                        .onTapGesture {
                            onSelect(app)
                            dismiss()
                        }
                }
            }
        }
        .padding(40)
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.black.opacity(0.85))
    }
}

extension FolderInfo: Identifiable {
    var id: String { name + apps.map(\.bundleIdentifier).joined() }
}
```

- [ ] **Step 4: Create `Sources/SimpleLaunchpad/Views/SearchField.swift`**

```swift
import SwiftUI

struct SearchField: View {
    @Binding var query: String

    var body: some View {
        TextField("", text: $query, prompt: Text("Search").foregroundColor(.white.opacity(0.6)))
            .textFieldStyle(.plain)
            .font(.title3)
            .foregroundColor(.white)
            .padding(10)
            .frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.15)))
    }
}
```

- [ ] **Step 5: Create `Sources/SimpleLaunchpad/Views/PageView.swift`**

```swift
import SwiftUI
import UniformTypeIdentifiers

struct PageView: View {
    @Binding var items: [LaunchpadItem]
    let onSelect: (AppInfo) -> Void
    let onMergeIntoFolder: (Int, Int) -> Void
    @State private var selectedFolder: FolderInfo?

    private let columns = Array(repeating: GridItem(.fixed(90), spacing: 24), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemView(for: item, at: index)
                    .onDrag { NSItemProvider(object: String(index) as NSString) }
                    .onDrop(of: [.text], delegate: ItemDropDelegate(
                        targetIndex: index,
                        items: $items,
                        onMergeIntoFolder: onMergeIntoFolder
                    ))
            }
        }
        .padding(40)
        .sheet(item: $selectedFolder) { folder in
            FolderView(folder: folder, onSelect: onSelect)
        }
    }

    @ViewBuilder
    private func itemView(for item: LaunchpadItem, at index: Int) -> some View {
        switch item {
        case .app(let app):
            AppIconView(app: app)
                .onTapGesture { onSelect(app) }
        case .folder(let folder):
            FolderIconView(folder: folder)
                .onTapGesture { selectedFolder = folder }
        }
    }
}

// ponytail: hover state is a static dictionary keyed by target index, not per-drag-session
// state, because DropDelegate structs are recreated on every render. Fine for a single-user,
// single-drag-at-a-time grid; would need real per-session state if concurrent drags were possible.
private struct ItemDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var items: [LaunchpadItem]
    let onMergeIntoFolder: (Int, Int) -> Void

    private static let mergeHoldThreshold: TimeInterval = 0.6
    private static var hoverStartedAt: [Int: Date] = [:]

    func dropEntered(info: DropInfo) {
        Self.hoverStartedAt[targetIndex] = Date()
    }

    func performDrop(info: DropInfo) -> Bool {
        let hoverDuration = Self.hoverStartedAt[targetIndex].map { Date().timeIntervalSince($0) } ?? 0
        Self.hoverStartedAt[targetIndex] = nil

        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { reading, _ in
            guard let string = reading as? String, let sourceIndex = Int(string) else { return }
            DispatchQueue.main.async {
                guard sourceIndex != targetIndex,
                      items.indices.contains(sourceIndex),
                      items.indices.contains(targetIndex) else { return }

                let isMergeable: Bool = {
                    if case .app = items[sourceIndex] {
                        if case .app = items[targetIndex] { return true }
                        if case .folder = items[targetIndex] { return true }
                    }
                    return false
                }()

                if hoverDuration >= Self.mergeHoldThreshold && isMergeable {
                    onMergeIntoFolder(sourceIndex, targetIndex)
                } else {
                    let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
                    items.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
                }
            }
        }
        return true
    }
}
```

- [ ] **Step 6: Create `Sources/SimpleLaunchpad/Views/LaunchpadView.swift`**

```swift
import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var store: LaunchpadStore
    let onSelect: (AppInfo) -> Void
    let onDismiss: () -> Void

    @State private var currentPage = 0
    @State private var searchQuery = ""

    private var searchResults: [AppInfo] {
        let allApps = store.pages.flatMap { $0 }.compactMap { item -> AppInfo? in
            if case .app(let app) = item { return app }
            return nil
        }
        return AppSearch.filter(allApps, query: searchQuery)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // catches taps on the empty background to dismiss
                .onTapGesture { onDismiss() }

            VStack(spacing: 24) {
                SearchField(query: $searchQuery)

                if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), spacing: 24), count: 7), spacing: 24) {
                            ForEach(searchResults, id: \.bundleIdentifier) { app in
                                AppIconView(app: app)
                                    .onTapGesture { onSelect(app) }
                            }
                        }
                        .padding(40)
                    }
                } else {
                    TabView(selection: $currentPage) {
                        ForEach(Array(store.pages.enumerated()), id: \.offset) { pageIndex, _ in
                            PageView(
                                items: Binding(
                                    get: { store.pages[pageIndex] },
                                    set: { newValue in
                                        store.pages[pageIndex] = newValue
                                        store.save()
                                    }
                                ),
                                onSelect: onSelect,
                                onMergeIntoFolder: { source, target in
                                    let merged = LaunchpadStore.mergingIntoFolder(
                                        sourceIndex: source,
                                        targetIndex: target,
                                        items: store.pages[pageIndex]
                                    )
                                    store.pages[pageIndex] = merged
                                    store.save()
                                }
                            )
                            .tag(pageIndex)
                        }
                    }
                    .tabViewStyle(.page)

                    if store.pages.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(store.pages.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == currentPage ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { store.load() }
    }
}
```

- [ ] **Step 7: Verify it builds**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/SimpleLaunchpad/Views
git commit -m "feat: add SwiftUI grid, paging, folder, and search views"
```

---

### Task 10: Wire everything together in App.swift

**Files:**
- Modify: `Sources/SimpleLaunchpad/App.swift` (created in Task 1)

**Interfaces:**
- Consumes: `LaunchpadStore` (Task 4), `OverlayWindowController` (Task 8), `StatusItemController` (Task 7), `HotKeyManager` (Task 6)
- Produces: a runnable app — nothing downstream depends on this.

- [ ] **Step 1: Replace `Sources/SimpleLaunchpad/App.swift` contents**

```swift
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: LaunchpadStore!
    private var overlayController: OverlayWindowController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = LaunchpadStore()

        overlayController = OverlayWindowController(store: store, onLaunch: { [weak self] app in
            NSWorkspace.shared.open(app.path)
            self?.overlayController.hide()
        })

        statusItemController = StatusItemController(onToggle: { [weak self] in
            self?.overlayController.toggle()
        })

        hotKeyManager = HotKeyManager(onTrigger: { [weak self] in
            self?.overlayController.toggle()
        })
        hotKeyManager.register()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 3: Manual smoke test**

Run: `swift run`
Expected, checked by hand:
- A grid icon appears in the menu bar (no Dock icon).
- Clicking it shows a fullscreen dimmed grid of installed apps.
- Pressing F4 toggles the grid open/closed.
- Typing in the search field filters the grid to matching apps.
- Dragging one app onto another and dropping after holding briefly (~0.6s) creates a folder.
- Clicking an app launches it and the overlay closes.
- Pressing Esc closes the overlay.
- Quit with Ctrl+C in the terminal running `swift run`.

- [ ] **Step 4: Commit**

```bash
git add Sources/SimpleLaunchpad/App.swift
git commit -m "feat: wire status item, hotkey, and overlay together in AppDelegate"
```

---

### Task 11: App bundle packaging script

**Files:**
- Create: `Sources/SimpleLaunchpad/Resources/Info.plist`
- Create: `Scripts/build-app-bundle.sh`
- Modify: `Package.swift` (exclude the new non-Swift resource file from the target)

**Interfaces:**
- Consumes: the compiled `SimpleLaunchpad` executable (all prior tasks)
- Produces: a `.app` bundle at `.build/release/Simple Launchpad.app`. Nothing downstream depends on this within the plan.

- [ ] **Step 1: Create `Sources/SimpleLaunchpad/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Simple Launchpad</string>
    <key>CFBundleIdentifier</key>
    <string>dev.skanevi.simplelaunchpad</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Simple Launchpad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
```

- [ ] **Step 2: Update `Package.swift` to exclude the Info.plist from the Swift source scan**

Change the `.executableTarget` entry to:

```swift
.executableTarget(
    name: "SimpleLaunchpad",
    path: "Sources/SimpleLaunchpad",
    exclude: ["Resources/Info.plist"]
),
```

- [ ] **Step 3: Create `Scripts/build-app-bundle.sh`**

```sh
#!/bin/sh
set -e

APP_NAME="Simple Launchpad"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/SimpleLaunchpad" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$(dirname "$0")/../Sources/SimpleLaunchpad/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
```

- [ ] **Step 4: Make it executable and run it**

Run: `chmod +x Scripts/build-app-bundle.sh && ./Scripts/build-app-bundle.sh`
Expected: prints `Built .build/release/Simple Launchpad.app` with no errors.

- [ ] **Step 5: Verify the bundle exists**

Run: `test -d ".build/release/Simple Launchpad.app" && echo "bundle exists"`
Expected: `bundle exists`.

- [ ] **Step 6: Commit**

```bash
git add Sources/SimpleLaunchpad/Resources/Info.plist Scripts/build-app-bundle.sh Package.swift
git commit -m "feat: add .app bundle packaging script"
```

---

### Task 12: GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the whole repo (build + test)
- Produces: nothing downstream depends on this.

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

- [ ] **Step 2: Validate the YAML is well-formed**

Run: `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'valid'"`
Expected: `valid`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: build and test on pull requests"
```

---

### Task 13: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (documents the finished project)
- Produces: nothing downstream depends on this.

- [ ] **Step 1: Replace `README.md` contents**

```markdown
# Simple Launchpad

A minimal, fast, native macOS clone of the classic Launchpad app grid.
A menu bar icon and a global hotkey (F4) open a fullscreen grid of your
installed apps, with paging, search, drag-to-reorder, and folders (drag
one app onto another and hold briefly to group them).

## Build & run

```sh
swift build
swift run
```

## Test

```sh
swift test
```

## Create a distributable .app

```sh
./Scripts/build-app-bundle.sh
open ".build/release/Simple Launchpad.app"
```

The app is unsigned. On first launch, right-click the app and choose
**Open** to bypass Gatekeeper, or run:

```sh
xattr -dr com.apple.quarantine ".build/release/Simple Launchpad.app"
```

## Design

See [docs/superpowers/specs/2026-09-21-simple-launchpad-design.md](docs/superpowers/specs/2026-09-21-simple-launchpad-design.md).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document build, test, and packaging steps"
```
