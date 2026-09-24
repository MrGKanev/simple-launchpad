import SwiftUI
import AppKit

/// Frosted-glass background that blurs and reflects whatever is behind the
/// window (desktop, other apps), matching the real Launchpad look. SwiftUI
/// has no material/blur view on macOS, so this wraps `NSVisualEffectView`.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    // Unlike the rest of the SwiftUI content in this ZStack, this is a real
    // AppKit subview competing for hit-testing. Left as-is, it would win
    // clicks over the SwiftUI "tap empty space to dismiss" catcher sitting
    // logically in front of it, since AppKit routes the click straight to
    // this literal NSView instead of asking SwiftUI's own gesture system.
    // Returning `nil` from `hitTest` makes it click-through, so those clicks
    // fall through to the dismiss catcher as intended.
    final class ClickThroughVisualEffectView: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = ClickThroughVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
