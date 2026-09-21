import AppKit
import SwiftUI

enum OverlayKeyHandling {
    static func shouldClose(forKeyCode keyCode: UInt16) -> Bool {
        keyCode == 53 // Esc
    }
}

// A borderless NSWindow returns `false` from `canBecomeKey`/`canBecomeMain`
// by default, so it never becomes the key window and never gets keyboard
// focus — the search field would silently ignore every keystroke. Overriding
// both to `true` is the standard fix for a borderless overlay that still
// needs to accept text input.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayWindowController: NSWindowController {
    private var keyMonitor: Any?

    init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = OverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        // Left fully clear rather than tinted: the SwiftUI content draws its
        // own `NSVisualEffectView` blur (behindWindow-blended), which needs
        // to see through the window to actually sample and blur what's on
        // screen behind it.
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: window)

        window.contentView = NSHostingView(rootView: LaunchpadView(
            store: store,
            onSelect: { app in
                onLaunch(app)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if OverlayKeyHandling.shouldClose(forKeyCode: event.keyCode) {
                self.hide()
                return nil
            }
            return event
        }
    }

    func hide() {
        window?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func toggle() {
        guard let window else { return }
        window.isVisible ? hide() : show()
    }
}
