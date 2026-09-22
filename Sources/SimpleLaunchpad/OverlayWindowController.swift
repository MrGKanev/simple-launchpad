import AppKit
import SwiftUI
import Quartz

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
    private let preferences: AppPreferences
    private let onLaunch: (AppInfo) -> Void
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var lastPageChange = Date.distantPast
    private var lastCategoryBarNudge = Date.distantPast
    // The app Space/Quick Look is currently previewing, if any — see
    // `QLPreviewPanelDataSource` below.
    private var previewedApp: AppInfo?

    // Matches `IconGridMetrics`'s fixed 7-column layout (both `.fixed` and
    // `.fitting`'s default) — used to translate Up/Down into ± a row.
    private static let gridColumns = 7

    init(store: LaunchpadStore, preferences: AppPreferences, onLaunch: @escaping (AppInfo) -> Void) {
        self.store = store
        self.preferences = preferences
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
            preferences: preferences,
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

    // Which screen to open on, per the "Show Launchpad on" Settings
    // preference (`AppPreferences.displayPreference`). `.cursor` reproduces
    // the app's original, only-ever behavior; `.named` falls back to that
    // same cursor logic if the requested display isn't currently connected.
    private func targetScreen() -> NSScreen? {
        let cursorScreen = { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main }
        switch preferences.displayPreference {
        case .cursor:
            return cursorScreen()
        case .main:
            return NSScreen.main ?? cursorScreen()
        case .named(let name):
            return NSScreen.screens.first { $0.localizedName == name } ?? cursorScreen()
        }
    }

    func show() {
        guard let window else { return }

        // Re-measure the screen on every show, not just at window creation —
        // otherwise a resolution change (new external display, System
        // Settings change, etc.) after launch would leave the overlay sized
        // for whatever screen was main when the app started, instead of
        // reacting to the current one the way `IconGridMetrics.fitting`
        // (via the SwiftUI `GeometryReader` it's fed from) is designed to.
        if let screenFrame = targetScreen()?.frame, screenFrame != window.frame {
            window.setFrame(screenFrame, display: true)
        }

        // `nil` leaves the window following the system appearance on its
        // own; an explicit Light/Dark Settings choice pins it, which also
        // drives the frosted-glass `NSVisualEffectView` material's own
        // light/dark look (SwiftUI's side of the same choice is threaded
        // through `LaunchpadView.palette` — see its own comment for why
        // this isn't done via `.preferredColorScheme` instead).
        window.appearance = preferences.appearance.nsAppearance

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
            let isFiltering = self.store.isFiltering
            // Only an actual typed query needs Left/Right left alone for the
            // search field's own text cursor — a category pill selected on
            // its own (no typed text) has no cursor to protect, so arrows
            // should still page the grid.
            let hasTypedQuery = !self.store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty

            if OverlayKeyHandling.shouldClose(forKeyCode: event.keyCode) {
                // Esc closes an open Quick Look panel first, then backs out
                // of an open folder, same as clicking its background,
                // before it closes the whole overlay.
                if let panel = QLPreviewPanel.shared(), panel.isVisible {
                    panel.orderOut(nil)
                } else if self.store.openFolder != nil {
                    self.store.openFolder = nil
                } else {
                    self.hide()
                }
                return nil
            }

            // While renaming a folder, Return/arrows/Space must behave like
            // normal text editing (commit the field, move the cursor, type
            // a space) instead of driving icon selection/launch/preview.
            if self.store.isEditingFolderName {
                return event
            }

            switch event.keyCode {
            case 36, 76: // Return / numpad Enter — launch or open the selection
                self.activateSelectedItem(isFiltering: isFiltering)
                return nil
            case 49 where self.store.hasKeyboardSelection: // Space — Quick Look the selection, Finder-style
                self.toggleQuickLook(isFiltering: isFiltering)
                return nil
            case 125: // Down arrow
                self.moveSelection(dx: 0, dy: 1, isFiltering: isFiltering)
                return nil
            case 126: // Up arrow
                self.moveSelection(dx: 0, dy: -1, isFiltering: isFiltering)
                return nil
            case 124 where !hasTypedQuery: // Right arrow — text cursor while searching
                self.moveSelection(dx: 1, dy: 0, isFiltering: isFiltering)
                return nil
            case 123 where !hasTypedQuery: // Left arrow — text cursor while searching
                self.moveSelection(dx: -1, dy: 0, isFiltering: isFiltering)
                return nil
            default:
                return event
            }
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            self.handleScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY)
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
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }

        guard let window, window.isVisible else { return }
        // Clear the search/scope so reopening the overlay later starts
        // fresh instead of showing whatever was last typed/selected.
        store.searchQuery = ""
        store.scope = .all
        store.isHoveringCategoryBar = false
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
    // events) only flips a single page — or steps the category bar by one
    // notch — instead of racing through several.
    private func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        if store.isHoveringCategoryBar {
            // A trackpad's own horizontal swipe already scrolls the pill
            // row natively (`ScrollView(.horizontal)` in
            // `CategoryFilterBar`) — leave that alone. Only a *plain*
            // vertical wheel delta (a mouse with no horizontal axis) needs
            // help, translated into stepping the row instead, since a
            // horizontal `ScrollView` never reacts to a Y-only delta on
            // its own.
            guard deltaX == 0, abs(deltaY) > 1 else { return }
            guard Date().timeIntervalSince(lastCategoryBarNudge) > 0.25 else { return }
            lastCategoryBarNudge = Date()
            // Natural-scrolling convention: scrolling down (negative deltaY)
            // reads as "forward", same as swiping left advances a page below.
            store.categoryBarScrollNudge = CategoryBarScrollNudge(direction: deltaY < 0 ? .forward : .backward)
            return
        }

        guard !store.isFiltering else { return }
        // A folder has its own internal ScrollView — while one's open,
        // scrolling over it (or its backdrop) must stay scoped to the
        // folder, not also page the grid behind it.
        guard store.openFolder == nil else { return }
        let delta = deltaX != 0 ? deltaX : deltaY
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

    private func visibleItemCount(isFiltering: Bool) -> Int {
        if isFiltering {
            return store.filteredResults.count
        }
        guard store.pages.indices.contains(store.currentPage) else { return 0 }
        return store.pages[store.currentPage].count
    }

    private func moveSelection(dx: Int, dy: Int, isFiltering: Bool) {
        let count = visibleItemCount(isFiltering: isFiltering)
        guard count > 0 else { return }
        let proposed = store.selectedIndex + dx + dy * Self.gridColumns
        store.selectedIndex = max(0, min(count - 1, proposed))
        store.hasKeyboardSelection = true

        // Keep an already-open Quick Look panel following the selection,
        // the same way Finder's own Quick Look tracks arrow-key movement.
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            previewedApp = selectedApp(isFiltering: isFiltering)
            panel.reloadData()
        }
    }

    private func activateSelectedItem(isFiltering: Bool) {
        if isFiltering {
            let results = store.filteredResults
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

    // The currently keyboard-selected *app* — `nil` if nothing's selected or
    // the selection is a folder (Quick Look has nothing useful to show for
    // one of those).
    private func selectedApp(isFiltering: Bool) -> AppInfo? {
        if isFiltering {
            let results = store.filteredResults
            return results.indices.contains(store.selectedIndex) ? results[store.selectedIndex] : nil
        }
        guard store.pages.indices.contains(store.currentPage) else { return nil }
        let items = store.pages[store.currentPage]
        guard items.indices.contains(store.selectedIndex), case .app(let app) = items[store.selectedIndex] else { return nil }
        return app
    }

    private func toggleQuickLook(isFiltering: Bool) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        guard let app = selectedApp(isFiltering: isFiltering) else { return }
        previewedApp = app
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

extension OverlayWindowController: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewedApp == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewedApp?.path as NSURL?
    }
}

extension OverlayWindowController: QLPreviewPanelDelegate {}
