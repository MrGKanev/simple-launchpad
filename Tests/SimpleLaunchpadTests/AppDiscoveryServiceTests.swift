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

    func testScanDedupesAppsSharingABundleIdentifier() throws {
        // Real-world case: multiple Xcode installs (e.g. Xcode_16.app,
        // Xcode_16.2.app) all report the same CFBundleIdentifier since Apple
        // doesn't vary it by version — this must not crash callers that key
        // apps by bundleIdentifier (LaunchpadStore.merge in particular).
        try makeFakeApp(name: "Xcode_16", bundleIdentifier: "com.apple.dt.Xcode", bundleName: "Xcode")
        try makeFakeApp(name: "Xcode_16.2", bundleIdentifier: "com.apple.dt.Xcode", bundleName: "Xcode")

        let results = AppDiscoveryService.scan(searchPaths: [tempDir.path])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].bundleIdentifier, "com.apple.dt.Xcode")
    }
}
