import SwiftUI

struct FolderView: View {
    let folder: FolderInfo
    // Reuses the *same* screen-size-relative metrics the main grid computes
    // (`IconGridMetrics.fitting`) instead of hardcoded pixel constants, so
    // the popup scales the same way the grid behind it does on any screen
    // size — `.fixed` only as a fallback for previews/tests.
    var metrics: IconGridMetrics = .fixed
    let onSelect: (AppInfo) -> Void
    let onRemove: (AppInfo) -> Void
    var onUninstall: ((AppInfo) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private let columnCount = 5
    private let maxVisibleRows = 4

    // Everything else below scales off this ratio, so the popup's padding
    // and title sizing track the grid's scale factor even though
    // `IconGridMetrics` doesn't expose the raw scale itself.
    private var scale: CGFloat { metrics.cellWidth / IconGridMetrics.fixed.cellWidth }
    private var outerPadding: CGFloat { 40 * scale }
    private var titleHeight: CGFloat { 29 * scale } // .title2 line height
    private var titleSpacing: CGFloat { 20 * scale }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(metrics.cellWidth), spacing: metrics.spacing), count: columnCount)
    }

    // The grid uses fixed-width columns, so the popup must be at least wide
    // enough to fit them all — narrower than this clipped the leftmost and
    // rightmost columns with no way to scroll to them.
    private var gridWidth: CGFloat {
        CGFloat(columnCount) * metrics.cellWidth + CGFloat(columnCount - 1) * metrics.spacing
    }
    private var popupWidth: CGFloat {
        gridWidth + outerPadding * 2
    }

    private var rowCount: Int {
        max(1, Int(ceil(Double(folder.apps.count) / Double(columnCount))))
    }

    // A ScrollView on macOS always claims the full height it's given for its
    // own drag/scroll handling, so a tap on the "empty" space below a short
    // row of icons never reached a dismiss gesture behind it. Sizing the
    // ScrollView tightly to its actual content (up to `maxVisibleRows`,
    // beyond which it scrolls) instead leaves that empty space as real
    // background outside the ScrollView, where the tap-to-dismiss below can
    // reliably catch it.
    private var scrollViewHeight: CGFloat {
        let visibleRows = CGFloat(min(rowCount, maxVisibleRows))
        return visibleRows * metrics.cellHeight + max(0, visibleRows - 1) * metrics.spacing + 16 * scale
    }
    private var popupHeight: CGFloat {
        outerPadding * 2 + titleHeight + titleSpacing + scrollViewHeight
    }

    var body: some View {
        // Standard macOS Launchpad behavior: clicking anywhere in the folder
        // that isn't an icon closes it. `AppIconView`'s own tap gesture wins
        // over this background one on the icons themselves, so both coexist.
        ZStack {
            Color.black.opacity(0.85)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: titleSpacing) {
                Text(folder.name)
                    .font(.title2)
                    .foregroundColor(.white)
                // A folder like the auto-generated "Other" one can hold more apps
                // than fit in `maxVisibleRows` — past that it scrolls.
                ScrollView {
                    LazyVGrid(columns: columns, spacing: metrics.spacing) {
                        ForEach(folder.apps, id: \.bundleIdentifier) { app in
                            AppIconView(
                                app: app,
                                metrics: metrics,
                                onTap: {
                                    onSelect(app)
                                    dismiss()
                                },
                                onRemove: { onRemove(app) },
                                onUninstall: onUninstall.map { callback in { callback(app) } }
                            )
                        }
                    }
                    .padding(.vertical, 8 * scale)
                }
                .frame(height: scrollViewHeight)
            }
            .padding(outerPadding)
        }
        .frame(width: popupWidth, height: popupHeight)
    }
}

extension FolderInfo: Identifiable {
    var id: String { name + apps.map(\.bundleIdentifier).joined() }
}
