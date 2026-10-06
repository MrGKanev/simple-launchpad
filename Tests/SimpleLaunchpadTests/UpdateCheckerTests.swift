import XCTest
@testable import SimpleLaunchpad

final class UpdateCheckerTests: XCTestCase {
    func testHigherMajorVersionIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9"))
    }

    func testDoubleDigitMinorIsNewerThanSingleDigit() {
        // The whole reason for a numeric compare instead of a string
        // compare: "1.10" > "1.2" numerically, but "1.10" < "1.2" as text.
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.2"))
    }

    func testEqualVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.1", than: "1.2"))
    }

    func testMissingTrailingComponentsCountAsZero() {
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.1"))
    }

    func testParseReleaseStripsVPrefixAndFindsZip() throws {
        let json = #"{"tag_name":"v1.2.3","assets":[{"name":"a.dmg","browser_download_url":"https://x/a.dmg"},{"name":"a.zip","browser_download_url":"https://x/a.zip"}]}"#
        let release = try XCTUnwrap(UpdateChecker.parseRelease(Data(json.utf8)))
        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.zipAssetURL.absoluteString, "https://x/a.zip")
    }

    func testParseReleaseWithoutZipThrows() {
        let json = #"{"tag_name":"1.0","assets":[]}"#
        XCTAssertThrowsError(try UpdateChecker.parseRelease(Data(json.utf8)))
    }

    func testRateLimitJSONIsNotAReleaseButNonSuccessStatusThrows() throws {
        XCTAssertNil(try UpdateChecker.parseRelease(Data(#"{"message":"rate limited"}"#.utf8)))
        let response = HTTPURLResponse(url: URL(string: "https://x")!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try UpdateChecker.checkStatus(response))
    }

    func testInstallArchiveSwapsAppContents() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let newApp = dir.appendingPathComponent("src/Test.app")
        try fm.createDirectory(at: newApp, withIntermediateDirectories: true)
        try "new".write(to: newApp.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("Test.zip")
        try UpdateChecker.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", newApp.path, zip.path])

        let installed = dir.appendingPathComponent("Test.app")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        try "old".write(to: installed.appendingPathComponent("marker"), atomically: true, encoding: .utf8)

        try await UpdateChecker.installArchive(zip, at: installed)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("marker")), "new")
    }
}
