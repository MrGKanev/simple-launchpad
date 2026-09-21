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

    // One confirmation for the whole batch (bulk multi-select action)
    // rather than one alert per app. Trashes whatever it can; any failures
    // are reported together at the end instead of interrupting the batch.
    @discardableResult
    static func moveToTrash(_ apps: [AppInfo]) -> Bool {
        guard !apps.isEmpty else { return false }
        if apps.count == 1 { return moveToTrash(apps[0]) }

        let alert = NSAlert()
        alert.messageText = "Move \(apps.count) apps to the Trash?"
        alert.informativeText = "You can restore them from the Trash if you change your mind."
        alert.alertStyle = .warning
        let trashButton = alert.addButton(withTitle: "Move to Trash")
        trashButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        var failures: [String] = []
        for app in apps {
            do {
                try FileManager.default.trashItem(at: app.path, resultingItemURL: nil)
            } catch {
                failures.append(app.name)
            }
        }
        if !failures.isEmpty {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Couldn't move some apps to the Trash"
            errorAlert.informativeText = failures.joined(separator: ", ")
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
        return true
    }
}
