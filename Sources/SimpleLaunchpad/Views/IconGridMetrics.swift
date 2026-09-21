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

    /// Fixed sizing for contexts that aren't the full-screen grid (e.g. the
    /// folder popover), which don't scale off the screen size.
    static let fixed = IconGridMetrics(
        columns: 7, spacing: 28, cellWidth: 120, cellHeight: 130, imageSize: 84, font: .body
    )

    static func fitting(_ size: CGSize, columns: Int = 7, rows: Int = 5, targetFraction: CGFloat = 0.7) -> IconGridMetrics {
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
            font: .system(size: baseFontSize * scale)
        )
    }
}
