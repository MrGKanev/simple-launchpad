import AppKit

final class StatusItemController {
    private let statusItem: NSStatusItem

    init(onToggle: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onToggle = onToggle
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Launchpad")
            button.target = self
            button.action = #selector(handleClick)
        }
    }

    private let onToggle: () -> Void

    @objc private func handleClick() {
        onToggle()
    }
}
