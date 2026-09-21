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
        .contentShape(Rectangle())
        .scaleEffect(isBouncing ? 0.85 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isBouncing)
        // A plain tap gesture (rather than a `Button`) — `Button` claims the
        // mouse-down before `.onDrag` (applied by the caller) can recognize a
        // drag start, which silently broke dragging apps into folders.
        .onTapGesture {
            isBouncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isBouncing = false }
            onTap()
        }
        .contextMenu {
            if let onRemove {
                Button("Remove from Launchpad", action: onRemove)
            }
            if let onUninstall {
                Button("Move to Trash…", role: .destructive, action: onUninstall)
            }
        }
    }
}
