import SwiftUI

struct FolderView: View {
    let folder: FolderInfo
    let onSelect: (AppInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columnCount = 5
    private let cellWidth: CGFloat = 120
    private let cellHeight: CGFloat = 130
    private let spacing: CGFloat = 28
    private let outerPadding: CGFloat = 40
    private let titleHeight: CGFloat = 29 // .title2 line height
    private let titleSpacing: CGFloat = 20
    private let maxVisibleRows = 4

    private let columns = Array(repeating: GridItem(.fixed(120), spacing: 28), count: 5)

    // The grid uses fixed-width columns, so the popup must be at least wide
    // enough to fit them all — an idealWidth narrower than this clipped the
    // leftmost and rightmost columns with no way to scroll to them.
    private var gridWidth: CGFloat {
        CGFloat(columnCount) * cellWidth + CGFloat(columnCount - 1) * spacing
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
        return visibleRows * cellHeight + max(0, visibleRows - 1) * spacing + 16 // + .padding(.vertical, 8)
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
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(folder.apps, id: \.bundleIdentifier) { app in
                            AppIconView(app: app, onTap: {
                                onSelect(app)
                                dismiss()
                            })
                        }
                    }
                    .padding(.vertical, 8)
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
