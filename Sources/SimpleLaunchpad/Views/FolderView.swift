import SwiftUI

struct FolderView: View {
    let folder: FolderInfo
    // Reuses the *same* screen-size-relative metrics the main grid computes
    // (`IconGridMetrics.fitting`) instead of hardcoded pixel constants, so
    // the popup scales the same way the grid behind it does on any screen
    // size — `.fixed` only as a fallback for previews/tests.
    var metrics: IconGridMetrics = .fixed
    var palette: LaunchpadPalette = LaunchpadPalette(isDark: true)
    let onSelect: (AppInfo) -> Void
    let onRemove: (AppInfo) -> Void
    var onUninstall: ((AppInfo) -> Void)? = nil
    let onRename: (String) -> Void
    // Lets the caller (`PageView`, via `LaunchpadStore`) suppress the global
    // arrow-key/Return handling while the name is being typed — otherwise
    // Return would trigger "launch the selected icon" instead of committing
    // the rename, and Left/Right would move icon selection instead of the
    // text cursor. See `OverlayWindowController`.
    var onEditingNameChanged: ((Bool) -> Void)? = nil
    // Cmd/Shift-click multi-select for the icons inside this folder too —
    // see `AppIconView` and `LaunchpadStore.selectedBundleIdentifiers`.
    var selectedBundleIdentifiers: Set<String> = []
    var onToggleSelectApp: ((AppInfo) -> Void)? = nil
    var onBulkRemove: (() -> Void)? = nil
    var onBulkUninstall: (() -> Void)? = nil
    // No longer a `.sheet` (see `PageView`, which now overlays this directly
    // so it can use a custom scale+fade transition) so there's no
    // presentation for `@Environment(\.dismiss)` to dismiss — the caller
    // supplies how to close instead.
    let onDismiss: () -> Void

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var isEditingNameState = SwiftUI.State(wrappedValue: false)
    private var isEditingName: Bool {
        get { isEditingNameState.wrappedValue }
        nonmutating set { isEditingNameState.wrappedValue = newValue }
    }
    private var editedNameState = SwiftUI.State(wrappedValue: "")
    private var editedName: String {
        get { editedNameState.wrappedValue }
        nonmutating set { editedNameState.wrappedValue = newValue }
    }

    // The synthesized memberwise init would be `private` because of the
    // `private` state properties above, so it's spelled out explicitly here
    // to stay accessible from other files (the state properties keep their
    // own defaults from the property declarations above).
    init(
        folder: FolderInfo,
        metrics: IconGridMetrics = .fixed,
        palette: LaunchpadPalette = LaunchpadPalette(isDark: true),
        onSelect: @escaping (AppInfo) -> Void,
        onRemove: @escaping (AppInfo) -> Void,
        onUninstall: ((AppInfo) -> Void)? = nil,
        onRename: @escaping (String) -> Void,
        onEditingNameChanged: ((Bool) -> Void)? = nil,
        selectedBundleIdentifiers: Set<String> = [],
        onToggleSelectApp: ((AppInfo) -> Void)? = nil,
        onBulkRemove: (() -> Void)? = nil,
        onBulkUninstall: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.folder = folder
        self.metrics = metrics
        self.palette = palette
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.onUninstall = onUninstall
        self.onRename = onRename
        self.onEditingNameChanged = onEditingNameChanged
        self.selectedBundleIdentifiers = selectedBundleIdentifiers
        self.onToggleSelectApp = onToggleSelectApp
        self.onBulkRemove = onBulkRemove
        self.onBulkUninstall = onBulkUninstall
        self.onDismiss = onDismiss
    }

    private let columnCount = 5
    private let maxVisibleRows = 4

    // Everything else below scales off this ratio, so the popup's padding
    // and title sizing track the grid's scale factor.
    private var scale: CGFloat { metrics.scale }
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
            palette.folderBackdrop
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditingName {
                        commitRename()
                    } else {
                        onDismiss()
                    }
                }

            VStack(spacing: titleSpacing) {
                title

                // A folder like the auto-generated "Other" one can hold more apps
                // than fit in `maxVisibleRows` — past that it scrolls.
                ScrollView {
                    LazyVGrid(columns: columns, spacing: metrics.spacing) {
                        ForEach(folder.apps, id: \.bundleIdentifier) { app in
                            AppIconView(
                                app: app,
                                metrics: metrics,
                                palette: palette,
                                onTap: {
                                    onSelect(app)
                                    onDismiss()
                                },
                                onRemove: { onRemove(app) },
                                onUninstall: onUninstall.map { callback in { callback(app) } },
                                isMultiSelected: selectedBundleIdentifiers.contains(app.bundleIdentifier),
                                selectionCount: selectedBundleIdentifiers.count,
                                onToggleSelect: onToggleSelectApp.map { callback in { callback(app) } },
                                onBulkRemove: onBulkRemove,
                                onBulkUninstall: onBulkUninstall
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

    // Real macOS Launchpad: click the folder's own name (while it's open)
    // to rename it in place.
    @ViewBuilder
    private var title: some View {
        // `.title2`'s own point size, scaled to match everything else in the
        // popup instead of staying fixed while the rest of it resizes.
        let titleFont = Font.system(size: 22 * scale)
        if isEditingName {
            TextField("Folder Name", text: Binding(get: { editedName }, set: { editedName = $0 }))
                .textFieldStyle(.plain)
                .font(titleFont)
                .foregroundColor(palette.text)
                .multilineTextAlignment(.center)
                .frame(width: popupWidth * 0.6)
                .onSubmit { commitRename() }
        } else {
            Text(folder.name)
                .font(titleFont)
                .foregroundColor(palette.text)
                .onTapGesture {
                    editedName = folder.name
                    isEditingName = true
                    onEditingNameChanged?(true)
                }
        }
    }

    private func commitRename() {
        isEditingName = false
        onEditingNameChanged?(false)
        onRename(editedName)
    }
}

extension FolderInfo: Identifiable {
    var id: String { name + apps.map(\.bundleIdentifier).joined() }
}
