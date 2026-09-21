import AppKit
import SwiftUI

/// Invisible helper that lets trackpad/mouse-wheel scrolling change pages.
/// SwiftUI has no `.onScrollWheel` modifier on macOS, and a plain
/// `NSViewRepresentable` only sees events AppKit hit-testing routes to it —
/// which SwiftUI content like the app icons sitting on top would block. A
/// local event monitor observes scroll events window-wide instead, the same
/// technique `OverlayWindowController` already uses for the Esc key.
struct ScrollPageMonitor: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class MonitoringView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
                self?.onScroll?(delta)
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}
