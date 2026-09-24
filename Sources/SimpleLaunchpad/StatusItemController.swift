import AppKit
import Combine

final class StatusItemController {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onOpenSettings: () -> Void
    private var preferencesCancellable: AnyCancellable?

    init(preferences: AppPreferences, onToggle: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onToggle = onToggle
        self.onOpenSettings = onOpenSettings
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Launchpad")
            button.target = self
            button.action = #selector(handleClick)
            // Left click keeps toggling the overlay directly; right/control
            // click instead shows a small menu (Settings, Quit) — same split
            // as the Dock icon's plain click vs. right-click menu.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // The icon can be hidden from Settings — the global hotkey (and the
        // Dock icon's own right-click menu) still reach Settings/the overlay
        // either way, so hiding it never strands the user.
        preferencesCancellable = preferences.$showMenuBarIcon.sink { [weak self] visible in
            self?.statusItem.isVisible = visible
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Simple Launchpad", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    @objc private func settingsClicked() {
        onOpenSettings()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
