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
