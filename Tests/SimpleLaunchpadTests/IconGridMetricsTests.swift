import XCTest
@testable import SimpleLaunchpad

final class IconGridMetricsTests: XCTestCase {
    func testZeroSizeFallsBackToFixed() {
        let metrics = IconGridMetrics.fitting(.zero)

        XCTAssertEqual(metrics.scale, IconGridMetrics.fixed.scale)
        XCTAssertEqual(metrics.cellWidth, IconGridMetrics.fixed.cellWidth)
    }

    func testScaleTracksTheSmallerDimension() {
        // A very tall, narrow window: width is the binding constraint, so
        // scale should come from width alone, not the taller height.
        let narrow = IconGridMetrics.fitting(CGSize(width: 400, height: 4000))
        let square = IconGridMetrics.fitting(CGSize(width: 400, height: 400))

        XCTAssertEqual(narrow.scale, square.scale, accuracy: 0.0001)
    }

    func testLargerWindowProducesLargerCells() {
        let small = IconGridMetrics.fitting(CGSize(width: 1000, height: 700))
        let large = IconGridMetrics.fitting(CGSize(width: 2000, height: 1400))

        XCTAssertGreaterThan(large.cellWidth, small.cellWidth)
        XCTAssertGreaterThan(large.scale, small.scale)
    }

    func testColumnsPassThroughUnscaled() {
        let metrics = IconGridMetrics.fitting(CGSize(width: 1000, height: 700), columns: 9)

        XCTAssertEqual(metrics.columns, 9)
    }
}
