import SwiftUI

/// Icon/grid sizing derived from the available window size, so the grid
/// (7 columns × 5 rows, matching `LaunchpadStore`'s default
/// `itemsPerPage: 35`) fills roughly `targetFraction` of the screen on any
/// display size instead of using fixed pixel values.
struct IconGridMetrics {
    let columns: Int
    let spacing: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let imageSize: CGFloat
    let font: Font
    // Relative to `.fixed`'s own metrics (scale == 1.0 there). Every other
    // piece of chrome around the grid (dots, outer padding, popover title,
    // corner radii, …) derives its own size from this one number instead of
    // hardcoding pixels, so the whole overlay scales together — like a `rem`
    // unit in web CSS scaling off the root font size.
    let scale: CGFloat

    /// Fixed sizing for contexts that aren't the full-screen grid (e.g. the
    /// folder popover), which don't scale off the screen size.
    static let fixed = IconGridMetrics(
        columns: 7, spacing: 28, cellWidth: 120, cellHeight: 130, imageSize: 84, font: .body, scale: 1.0
    )

    static func fitting(_ size: CGSize, columns: Int = 7, rows: Int = 5, targetFraction: CGFloat = 0.6) -> IconGridMetrics {
        let baseSpacing: CGFloat = 28
        let baseCellWidth: CGFloat = 120
        let baseCellHeight: CGFloat = 130
        let baseImageSize: CGFloat = 84
        let baseFontSize: CGFloat = 17

        let baseTotalWidth = CGFloat(columns) * baseCellWidth + CGFloat(columns - 1) * baseSpacing
        let baseTotalHeight = CGFloat(rows) * baseCellHeight + CGFloat(rows - 1) * baseSpacing

        guard baseTotalWidth > 0, baseTotalHeight > 0, size.width > 0, size.height > 0 else { return .fixed }

        let scaleForWidth = (size.width * targetFraction) / baseTotalWidth
        let scaleForHeight = (size.height * targetFraction) / baseTotalHeight
        let scale = min(scaleForWidth, scaleForHeight)

        return IconGridMetrics(
            columns: columns,
            spacing: baseSpacing * scale,
            cellWidth: baseCellWidth * scale,
            cellHeight: baseCellHeight * scale,
            imageSize: baseImageSize * scale,
            font: .system(size: baseFontSize * scale),
            scale: scale
        )
    }
}
