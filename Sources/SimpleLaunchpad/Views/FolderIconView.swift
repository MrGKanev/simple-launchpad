import SwiftUI
import AppKit

struct FolderIconView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let folder: FolderInfo
    var metrics: IconGridMetrics = .fixed
    var isSelected: Bool = false
    var palette: LaunchpadPalette = LaunchpadPalette(isDark: true)
    let onTap: () -> Void

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var isBouncingState = SwiftUI.State(wrappedValue: false)
    private var isBouncing: Bool {
        get { isBouncingState.wrappedValue }
        nonmutating set { isBouncingState.wrappedValue = newValue }
    }

    // The synthesized memberwise init would be `private` because of the
    // `private` state property above, so it's spelled out explicitly here
    // to stay accessible from other files (`isBouncingState` keeps its own
    // default from the property declaration above).
    init(
        folder: FolderInfo,
        metrics: IconGridMetrics = .fixed,
        isSelected: Bool = false,
        palette: LaunchpadPalette = LaunchpadPalette(isDark: true),
        onTap: @escaping () -> Void
    ) {
        self.folder = folder
        self.metrics = metrics
        self.isSelected = isSelected
        self.palette = palette
        self.onTap = onTap
    }

    private var miniIconSize: CGFloat { max(12, (metrics.imageSize - 16 * metrics.scale - 3 * metrics.scale) / 2) }
    private var columns: [GridItem] { [GridItem(.fixed(miniIconSize)), GridItem(.fixed(miniIconSize))] }

    var body: some View {
        VStack(spacing: 8 * metrics.scale) {
            LazyVGrid(columns: columns, spacing: 3 * metrics.scale) {
                ForEach(Array(folder.apps.prefix(4)), id: \.bundleIdentifier) { app in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                        .resizable()
                        .frame(width: miniIconSize, height: miniIconSize)
                }
            }
            .padding(8 * metrics.scale)
            .frame(width: metrics.imageSize, height: metrics.imageSize)
            .background(RoundedRectangle(cornerRadius: metrics.imageSize * 0.19).fill(palette.folderTileFill))
            Text(folder.name)
                .font(metrics.font)
                .foregroundColor(palette.text)
                .lineLimit(1)
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 14 * metrics.scale)
                .fill(isSelected ? palette.selectionFill : Color.clear)
        )
        .contentShape(Rectangle())
        .scaleEffect(isBouncing && !reduceMotion ? 0.96 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.9), value: isBouncing)
        // A plain tap gesture (rather than a `Button`) — `Button` claims the
        // mouse-down before `.onDrag` (applied by the caller) can recognize a
        // drag start, which silently broke dragging apps into folders.
        .onTapGesture {
            isBouncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isBouncing = false }
            onTap()
        }
    }
}
