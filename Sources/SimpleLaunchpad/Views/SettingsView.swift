import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    // `@ObservedObject` (unlike `@State`) is a plain property wrapper, not
    // macro-based, so the attribute works fine under this project's toolchain.
    @ObservedObject var store: LaunchpadStore
    @ObservedObject var preferences: AppPreferences

    // ponytail: manual `SwiftUI.State<Value>` wiring instead of the `@State`
    // attribute — see the comment in LaunchpadView.swift for why (this SDK's
    // `@State` macro plugin isn't available under Xcode Command Line Tools).
    private var launchAtLoginState = SwiftUI.State(wrappedValue: LoginItemManager.isEnabled)
    private var launchAtLogin: Bool {
        get { launchAtLoginState.wrappedValue }
        nonmutating set { launchAtLoginState.wrappedValue = newValue }
    }

    private var isCheckingForUpdatesState = SwiftUI.State(wrappedValue: false)
    private var isCheckingForUpdates: Bool {
        get { isCheckingForUpdatesState.wrappedValue }
        nonmutating set { isCheckingForUpdatesState.wrappedValue = newValue }
    }

    private var updateStatusState = SwiftUI.State(wrappedValue: "")
    private var updateStatus: String {
        get { updateStatusState.wrappedValue }
        nonmutating set { updateStatusState.wrappedValue = newValue }
    }

    private var layoutIOStatusState = SwiftUI.State(wrappedValue: "")
    private var layoutIOStatus: String {
        get { layoutIOStatusState.wrappedValue }
        nonmutating set { layoutIOStatusState.wrappedValue = newValue }
    }

    // The synthesized memberwise init would be `private` because of the
    // `private` state properties above, so it's spelled out explicitly here
    // to stay accessible from other files (the state properties keep their
    // own defaults from the property declarations above).
    init(store: LaunchpadStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    LoginItemManager.setEnabled(newValue)
                }
            ))

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show menu bar icon", isOn: $preferences.showMenuBarIcon)
                // Hiding the icon doesn't strand the user: the global
                // shortcut still opens the app, and the Dock icon's
                // right-click menu still reaches Settings.
                Text("Reopen anytime with the shortcut below, or from the Dock icon's right-click menu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Global Shortcut")
                Spacer()
                ShortcutRecorderView(keyCode: $preferences.hotKeyCode, modifiers: $preferences.hotKeyModifiers)
                    .frame(width: 120, height: 24)
            }

            HStack {
                Text("Appearance")
                Spacer()
                Picker("", selection: $preferences.appearance) {
                    ForEach(LaunchpadAppearance.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            // Only worth showing when there's actually a choice to make —
            // a single-display Mac has nothing for "Main Display" or a
            // named screen to mean beyond what "Follow Cursor" already does.
            if NSScreen.screens.count > 1 {
                HStack {
                    Text("Show Launchpad On")
                    Spacer()
                    Picker("", selection: $preferences.displayPreference) {
                        Text("Display with Cursor").tag(DisplayPreference.cursor)
                        Text("Main Display").tag(DisplayPreference.main)
                        ForEach(NSScreen.screens, id: \.localizedName) { screen in
                            Text(screen.localizedName).tag(DisplayPreference.named(screen.localizedName))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Show search field", isOn: $preferences.showSearchField)
                Toggle("Show category bar", isOn: $preferences.showCategoryBar)
                Text("Turn either off for a leaner, icons-only grid.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button(isCheckingForUpdates ? "Checking…" : "Check for Updates") {
                        checkForUpdates()
                    }
                    .disabled(isCheckingForUpdates)

                    Text(UpdateChecker.currentVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !updateStatus.isEmpty {
                    Text(updateStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Link("Download the latest version on GitHub",
                     destination: URL(string: "https://github.com/MrGKanev/simple-launchpad")!)
                    .font(.caption)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Button("Export Layout…") { exportLayout() }
                    Button("Import Layout…") { importLayout() }
                }
                if !layoutIOStatus.isEmpty {
                    Text(layoutIOStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Save or load your grid — pages, folders, and category tweaks — to move it to another Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Button("Reset Layout…", role: .destructive) {
                    confirmAndResetLayout()
                }
                Text("Rebuilds the grid alphabetically — discards custom folders and ordering.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
    }

    private func exportLayout() {
        let panel = NSSavePanel()
        panel.title = "Export Launchpad Layout"
        panel.nameFieldStringValue = "Launchpad Layout.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportLayout(to: url)
            layoutIOStatus = "Exported to \(url.lastPathComponent)."
        } catch {
            layoutIOStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.title = "Import Launchpad Layout"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importLayout(from: url)
            layoutIOStatus = "Imported \(url.lastPathComponent)."
        } catch {
            layoutIOStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private func confirmAndResetLayout() {
        let alert = NSAlert()
        alert.messageText = "Reset the Launchpad layout?"
        alert.informativeText = "This rebuilds the grid alphabetically and breaks up every folder. This can't be undone."
        alert.alertStyle = .warning
        let resetButton = alert.addButton(withTitle: "Reset Layout")
        resetButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.resetLayout()
    }

    // A found update downloads and installs itself immediately — the app
    // relaunches itself and quits on success, so there's nothing further to
    // update here in that case.
    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateStatus = ""
        Task {
            do {
                guard let release = try await UpdateChecker.fetchLatestRelease() else {
                    updateStatus = "Could not check for updates."
                    isCheckingForUpdates = false
                    return
                }
                if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion) {
                    updateStatus = "Downloading update \(release.version)…"
                    try await UpdateChecker.downloadAndInstall(release)
                } else {
                    updateStatus = "You're up to date (\(UpdateChecker.currentVersion))."
                    isCheckingForUpdates = false
                }
            } catch {
                updateStatus = "Update failed: \(error.localizedDescription)"
                isCheckingForUpdates = false
            }
        }
    }
}
