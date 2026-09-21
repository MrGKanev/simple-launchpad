import AppKit
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: LaunchpadStore!
    private var overlayController: OverlayWindowController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!
    private var settingsWindowController: SettingsWindowController!
    private var preferences: AppPreferences!
    private var hotKeyCancellable: AnyCancellable?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = LaunchpadStore()
        preferences = AppPreferences()

        overlayController = OverlayWindowController(store: store, onLaunch: { [weak self] app in
            NSWorkspace.shared.open(app.path)
            self?.overlayController.hide()
        })

        settingsWindowController = SettingsWindowController(preferences: preferences)

        statusItemController = StatusItemController(
            preferences: preferences,
            onToggle: { [weak self] in
                self?.overlayController.toggle()
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            }
        )

        registerHotKey()
        // Re-register (unregistering the old one first, via a fresh
        // `HotKeyManager` whose `deinit` unregisters) whenever the user
        // records a new shortcut in Settings.
        hotKeyCancellable = Publishers.CombineLatest(preferences.$hotKeyCode, preferences.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in self?.registerHotKey() }

        overlayController.show()
    }

    // Standard macOS behavior: clicking the app's Dock icon while it's
    // already running should bring its window back, the same way the menu
    // bar item and hotkey do — not do nothing just because we have no
    // regular window for AppKit to reopen on its own. And if the overlay is
    // already showing, clicking the icon again should close it, same as the
    // menu bar item and hotkey toggling instead of only ever opening.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlayController.toggle()
        return true
    }

    // Right/Control-clicking the Dock icon lists every known app — apps
    // loose on a page and apps tucked inside folders alike — sorted
    // alphabetically, each launchable directly from the menu. Mirrors the
    // classic trick of keeping the /Applications folder itself in the Dock
    // and fanning it out for quick access to anything installed.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let allApps: [AppInfo] = store.pages.flatMap { $0 }.flatMap { item -> [AppInfo] in
            switch item {
            case .app(let app): return [app]
            case .folder(let folder): return folder.apps
            }
        }
        let sortedApps = allApps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromDockMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        for app in sortedApps {
            let item = NSMenuItem(title: app.name, action: #selector(openAppFromDockMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.path
            let icon = NSWorkspace.shared.icon(forFile: app.path.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openAppFromDockMenu(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettingsFromDockMenu() {
        openSettings()
    }

    // The overlay is a floating, always-on-top window — leaving it up while
    // Settings opens would just leave Settings stuck behind it. Close the
    // overlay first so Settings actually comes to the front.
    private func openSettings() {
        overlayController.hide()
        settingsWindowController.show()
    }

    private func registerHotKey() {
        hotKeyManager = HotKeyManager(onTrigger: { [weak self] in
            self?.overlayController.toggle()
        })
        hotKeyManager.register(keyCode: preferences.hotKeyCode, modifiers: preferences.hotKeyModifiers)
    }
}
