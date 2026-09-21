import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: LaunchpadStore!
    private var overlayController: OverlayWindowController!
    private var statusItemController: StatusItemController!
    private var hotKeyManager: HotKeyManager!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = LaunchpadStore()

        overlayController = OverlayWindowController(store: store, onLaunch: { [weak self] app in
            NSWorkspace.shared.open(app.path)
            self?.overlayController.hide()
        })

        statusItemController = StatusItemController(onToggle: { [weak self] in
            self?.overlayController.toggle()
        })

        hotKeyManager = HotKeyManager(onTrigger: { [weak self] in
            self?.overlayController.toggle()
        })
        hotKeyManager.register()

        overlayController.show()
    }
}
