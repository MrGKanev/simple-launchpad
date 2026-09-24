import XCTest
@testable import SimpleLaunchpad

final class AppCategoryTests: XCTestCase {
    func testKnownCategorySuffixMaps() {
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.developer-tools"), .developerTools)
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.music"), .music)
    }

    func testNilRawValueMapsToOther() {
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: nil), .other)
    }

    func testUnrecognizedSuffixMapsToOther() {
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.made-up"), .other)
    }

    func testAnyGamesSubcategoryFoldsIntoGames() {
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.action-games"), .games)
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.puzzle-games"), .games)
        XCTAssertEqual(AppCategory(lsApplicationCategoryType: "public.app-category.games"), .games)
    }
}
