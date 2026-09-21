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
    private let onLaunch: (AppInfo) -> Void
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var lastPageChange = Date.distantPast

    // Matches `IconGridMetrics`'s fixed 7-column layout (both `.fixed` and
    // `.fitting`'s default) — used to translate Up/Down into ± a row.
    private static let gridColumns = 7

    init(store: LaunchpadStore, onLaunch: @escaping (AppInfo) -> Void) {
        self.store = store
        self.onLaunch = onLaunch
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

    // Kept short and eased so opening/closing reads as an instant response
    // to the hotkey/click rather than a deliberate "animation" — real
    // Launchpad's own feel.
    private static let showHideDuration: TimeInterval = 0.15

    func show() {
        guard let window else { return }

        window.contentView?.wantsLayer = true
        window.alphaValue = 0
        window.contentView?.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.showHideDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        window.animator().alphaValue = 1
        window.contentView?.layer?.transform = CATransform3DIdentity
        CATransaction.commit()

        // Installed/removed alongside window visibility (like the Esc
        // handling below) so paging works anywhere over the overlay, not
        // just while hovering a particular SwiftUI subview.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let isSearching = !self.store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty

            if OverlayKeyHandling.shouldClose(forKeyCode: event.keyCode) {
                // Esc backs out of an open folder first, same as clicking
                // its background, before it closes the whole overlay.
                if self.store.openFolder != nil {
                    self.store.openFolder = nil
                } else {
                    self.hide()
                }
                return nil
            }

            // While renaming a folder, Return/arrows must behave like normal
            // text editing (commit the field, move the cursor) instead of
            // driving icon selection/launch.
            if self.store.isEditingFolderName {
                return event
            }

            switch event.keyCode {
            case 36, 76: // Return / numpad Enter — launch or open the selection
                self.activateSelectedItem(isSearching: isSearching)
                return nil
            case 125: // Down arrow
                self.moveSelection(dx: 0, dy: 1, isSearching: isSearching)
                return nil
            case 126: // Up arrow
                self.moveSelection(dx: 0, dy: -1, isSearching: isSearching)
                return nil
            case 124 where !isSearching: // Right arrow — text cursor while searching
                self.moveSelection(dx: 1, dy: 0, isSearching: isSearching)
                return nil
            case 123 where !isSearching: // Left arrow — text cursor while searching
                self.moveSelection(dx: -1, dy: 0, isSearching: isSearching)
                return nil
            default:
                return event
            }
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            self.handleScroll(delta)
            return event
        }
    }

    func hide() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }

        guard let window, window.isVisible else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.showHideDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        CATransaction.setCompletionBlock { [weak window] in
            window?.orderOut(nil)
        }
        window.animator().alphaValue = 0
        window.contentView?.layer?.transform = CATransform3DMakeScale(0.97, 0.97, 1)
        CATransaction.commit()
    }

    func toggle() {
        guard let window else { return }
        window.isVisible ? hide() : show()
    }

    // Debounced so one trackpad scroll gesture (which fires many small
    // events) only flips a single page instead of racing through several.
    private func handleScroll(_ delta: CGFloat) {
        guard store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // A folder has its own internal ScrollView — while one's open,
        // scrolling over it (or its backdrop) must stay scoped to the
        // folder, not also page the grid behind it.
        guard store.openFolder == nil else { return }
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

    private func visibleItemCount(isSearching: Bool) -> Int {
        if isSearching {
            return store.searchResults.count
        }
        guard store.pages.indices.contains(store.currentPage) else { return 0 }
        return store.pages[store.currentPage].count
    }

    private func moveSelection(dx: Int, dy: Int, isSearching: Bool) {
        let count = visibleItemCount(isSearching: isSearching)
        guard count > 0 else { return }
        let proposed = store.selectedIndex + dx + dy * Self.gridColumns
        store.selectedIndex = max(0, min(count - 1, proposed))
    }

    private func activateSelectedItem(isSearching: Bool) {
        if isSearching {
            let results = store.searchResults
            guard results.indices.contains(store.selectedIndex) else { return }
            onLaunch(results[store.selectedIndex])
            return
        }
        guard store.pages.indices.contains(store.currentPage) else { return }
        let items = store.pages[store.currentPage]
        guard items.indices.contains(store.selectedIndex) else { return }
        switch items[store.selectedIndex] {
        case .app(let app):
            onLaunch(app)
        case .folder(let folder):
            store.openFolder = folder
        }
    }
}
