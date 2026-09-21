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
    private var isBouncingState = SwiftUI.State(wrappedValue: false)
    private var isBouncing: Bool {
        get { isBouncingState.wrappedValue }
        nonmutating set { isBouncingState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 8) {
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
            RoundedRectangle(cornerRadius: 14)
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
        .scaleEffect(isBouncing ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isBouncing)
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
            isBouncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isBouncing = false }
            onTap()
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
