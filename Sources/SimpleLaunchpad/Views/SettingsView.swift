import SwiftUI

struct SettingsView: View {
    // `@ObservedObject` (unlike `@State`) is a plain property wrapper, not
    // macro-based, so the attribute works fine under this project's toolchain.
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
        }
        .padding(24)
        .frame(width: 320, alignment: .leading)
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
