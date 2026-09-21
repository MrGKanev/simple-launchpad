import AppKit
import SwiftUI

enum OverlayKeyHandling {
    static func shouldClose(forKeyCode keyCode: UInt16) -> Bool {
        keyCode == 53 // Esc
    }
}

final class OverlayWindowController: NSWindowController {
    private var keyMonitor: Any?

    init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void) {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.4)
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
