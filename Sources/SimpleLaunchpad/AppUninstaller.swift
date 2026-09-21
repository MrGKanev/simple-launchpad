import AppKit

// Actually deleting a user's app is high-stakes, so unlike "Remove from
// Launchpad" (which only touches the grid) this always confirms first, and
// moves it to the Trash rather than deleting outright — recoverable if it
// was a mistake, same as dragging an app to the Trash in Finder.
enum AppUninstaller {
    @discardableResult
    static func moveToTrash(_ app: AppInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move “\(app.name)” to the Trash?"
        alert.informativeText = "You can restore it from the Trash if you change your mind."
        alert.alertStyle = .warning
        let trashButton = alert.addButton(withTitle: "Move to Trash")
        trashButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try FileManager.default.trashItem(at: app.path, resultingItemURL: nil)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
