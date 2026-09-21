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
    private let store: LaunchpadStore
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var lastPageChange = Date.distantPast

    init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void) {
        self.store = store
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

        // Matches real Launchpad: clicking a Dock icon (or anything else
        // that activates another app) hands focus away from us, so the
        // overlay should get out of the way instead of lingering on screen.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive() {
        guard window?.isVisible == true else { return }
        hide()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Installed/removed alongside window visibility (like the Esc
        // handling below) so paging works anywhere over the overlay, not
        // just while hovering a particular SwiftUI subview.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if OverlayKeyHandling.shouldClose(forKeyCode: event.keyCode) {
                self.hide()
                return nil
            }
            // Left/right arrows page the grid, but only while there's no
            // active search — otherwise they should move the text cursor.
            if self.store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                if event.keyCode == 124 { // Right arrow
                    self.changePage(by: 1)
                    return nil
                } else if event.keyCode == 123 { // Left arrow
                    self.changePage(by: -1)
                    return nil
                }
            }
            return event
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            self.handleScroll(delta)
            return event
        }
    }

    func hide() {
        window?.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    func toggle() {
        guard let window else { return }
        window.isVisible ? hide() : show()
    }

    // Debounced so one trackpad scroll gesture (which fires many small
    // events) only flips a single page instead of racing through several.
    private func handleScroll(_ delta: CGFloat) {
        guard store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard abs(delta) > 1 else { return }
        guard Date().timeIntervalSince(lastPageChange) > 0.35 else { return }
        // Same convention as the swipe gesture: scrolling/swiping left advances.
        if delta < 0 {
            changePage(by: 1)
        } else if delta > 0 {
            changePage(by: -1)
        }
    }

    private func changePage(by offset: Int) {
        let target = store.currentPage + offset
        guard store.pages.indices.contains(target) else { return }
        store.currentPage = target
        lastPageChange = Date()
    }
}
