import ServiceManagement

// `SMAppService.mainApp` (macOS 13+) registers this very app bundle to
// launch at login — no separate helper target or LaunchAgent plist needed,
// unlike the older `SMLoginItemSetEnabled` API.
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail for an unsigned/ad-hoc build; nothing
            // to recover here, the toggle just won't stick until re-tried.
        }
    }
}
