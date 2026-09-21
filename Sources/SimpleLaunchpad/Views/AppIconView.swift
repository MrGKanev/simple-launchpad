import SwiftUI
import AppKit

struct AppIconView: View {
    let app: AppInfo
    var metrics: IconGridMetrics = .fixed
    var isSelected: Bool = false
    let onTap: () -> Void
    // nil hides the "Remove from Launchpad" context menu entirely.
    var onRemove: (() -> Void)? = nil
    // nil hides "Move to Trash…" — this one actually deletes the app
    // (after confirming), so unlike `onRemove` it's marked destructive.
    var onUninstall: (() -> Void)? = nil

    // Cmd/Shift-click multi-select, for bulk remove/uninstall. `isMultiSelected`
    // is this icon's own membership; `selectionCount` is the total selected
    // across the grid, so the context menu can switch to "N apps" wording.
    var isMultiSelected: Bool = false
    var selectionCount: Int = 0
    var onToggleSelect: (() -> Void)? = nil
    var onBulkRemove: (() -> Void)? = nil
    var onBulkUninstall: (() -> Void)? = nil

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var isLaunchingState = SwiftUI.State(wrappedValue: false)
    // Grow-and-fade feedback for the icon that was actually tapped, so a
    // click reads as "launching this app" rather than just the whole
    // overlay abruptly vanishing (`OverlayWindowController.hide` fades the
    // window itself at the same time, over the same duration).
    private var isLaunching: Bool {
        get { isLaunchingState.wrappedValue }
        nonmutating set { isLaunchingState.wrappedValue = newValue }
    }

    // The synthesized memberwise init would be `private` because of the
    // `private` state properties above, so it's spelled out explicitly here
    // to stay accessible from other files (`isLaunchingState` keeps its own
    // default from the property declaration above).
    init(
        app: AppInfo,
        metrics: IconGridMetrics = .fixed,
        isSelected: Bool = false,
        onTap: @escaping () -> Void,
        onRemove: (() -> Void)? = nil,
        onUninstall: (() -> Void)? = nil,
        isMultiSelected: Bool = false,
        selectionCount: Int = 0,
        onToggleSelect: (() -> Void)? = nil,
        onBulkRemove: (() -> Void)? = nil,
        onBulkUninstall: (() -> Void)? = nil
    ) {
        self.app = app
        self.metrics = metrics
        self.isSelected = isSelected
        self.onTap = onTap
        self.onRemove = onRemove
        self.onUninstall = onUninstall
        self.isMultiSelected = isMultiSelected
        self.selectionCount = selectionCount
        self.onToggleSelect = onToggleSelect
        self.onBulkRemove = onBulkRemove
        self.onBulkUninstall = onBulkUninstall
    }

    var body: some View {
        VStack(spacing: 8 * metrics.scale) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path.path))
                .resizable()
                .frame(width: metrics.imageSize, height: metrics.imageSize)
            Text(app.name)
                .font(metrics.font)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .frame(width: metrics.cellWidth, height: metrics.cellHeight)
        .background(
            RoundedRectangle(cornerRadius: 14 * metrics.scale)
                .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .font(.system(size: max(14, metrics.imageSize * 0.22)))
                    .offset(x: -metrics.cellWidth * 0.18, y: metrics.cellHeight * 0.02)
            }
        }
        .contentShape(Rectangle())
        // Scale only — no separate opacity fade here. The tapped icon fading
        // out *with its own animation curve*, racing the whole overlay
        // window's *own* alpha fade (a completely separate Core Animation
        // driven by `OverlayWindowController.hide`), was what made the
        // dismiss look like two disjointed stages instead of one motion:
        // the two fades rarely finished at the same instant. Leaving fading
        // entirely to the window's single alpha animation means the icon
        // disappears in exact lockstep with the background, since they're
        // then just the same pixels — the icon only adds its own quick
        // "pop" on top of that shared fade.
        .scaleEffect(isLaunching ? 1.15 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isLaunching)
        // A plain tap gesture (rather than a `Button`) — `Button` claims the
        // mouse-down before `.onDrag` (applied by the caller) can recognize a
        // drag start, which silently broke dragging apps into folders.
        .onTapGesture {
            // Cmd/Shift-click toggles multi-select instead of launching —
            // same modifier convention as Finder.
            if let onToggleSelect, NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift) {
                onToggleSelect()
                return
            }
            isLaunching = true
            onTap()
            // Reset only once the whole sequence — this pop, the beat before
            // the window starts leaving, and the window's own fade-out (see
            // `AppDelegate`'s `onLaunch` and
            // `OverlayWindowController.showHideDuration`) — has finished, so
            // the icon isn't left enlarged the next time the overlay reopens
            // on the same item, and doesn't visibly snap back mid-fade.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { isLaunching = false }
        }
        .contextMenu {
            if isMultiSelected, selectionCount > 1 {
                if let onBulkRemove {
                    Button("Remove \(selectionCount) from Launchpad", action: onBulkRemove)
                }
                if let onBulkUninstall {
                    Button("Move \(selectionCount) to Trash…", role: .destructive, action: onBulkUninstall)
                }
            } else {
                if let onRemove {
                    Button("Remove from Launchpad", action: onRemove)
                }
                if let onUninstall {
                    Button("Move to Trash…", role: .destructive, action: onUninstall)
                }
            }
        }
    }
}
