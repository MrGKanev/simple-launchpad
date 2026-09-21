import SwiftUI
import AppKit

/// Frosted-glass background that blurs and reflects whatever is behind the
/// window (desktop, other apps), matching the real Launchpad look. SwiftUI
/// has no material/blur view on macOS, so this wraps `NSVisualEffectView`.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .fullScreenUI
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
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
