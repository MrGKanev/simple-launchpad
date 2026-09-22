import Foundation
import Combine
import AppKit
import Carbon

// Which screen the overlay opens on. `.cursor` is the original, only-ever
// behavior (the screen the mouse happens to be over); `.main` and `.named`
// are opt-in for multi-monitor setups where that's the wrong screen. A named
// screen is matched by `localizedName` (there's no stable persistent screen
// ID across reboots/reconnects) — if it's not currently connected, `show()`
// falls back to `.cursor`'s logic.
enum DisplayPreference: Equatable, Hashable {
    case cursor
    case main
    case named(String)

    var rawValue: String {
        switch self {
        case .cursor: return "cursor"
        case .main: return "main"
        case .named(let name): return "named:\(name)"
        }
    }

    init(rawValue: String) {
        if rawValue == "main" {
            self = .main
        } else if rawValue.hasPrefix("named:") {
            self = .named(String(rawValue.dropFirst("named:".count)))
        } else {
            self = .cursor
        }
    }
}

// Backed by UserDefaults so the choice survives relaunches; `@Published` (a
// plain Combine property wrapper, not one of the newer macro-based ones) is
// safe to use directly under this project's toolchain — see the `@State`
// caveat noted elsewhere for what isn't.
final class AppPreferences: ObservableObject {
    private static let showMenuBarIconKey = "showMenuBarIcon"
    private static let hotKeyCodeKey = "hotKeyCode"
    private static let hotKeyModifiersKey = "hotKeyModifiers"
    private static let displayPreferenceKey = "displayPreference"
    private static let appearanceKey = "appearance"
    private static let showSearchFieldKey = "showSearchField"
    private static let showCategoryBarKey = "showCategoryBar"

    // Same default the app always used before this was configurable.
    static let defaultHotKeyCode = UInt32(kVK_F4)
    static let defaultHotKeyModifiers: UInt32 = 0

    @Published var showMenuBarIcon: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: Self.showMenuBarIconKey)
        }
    }

    @Published var hotKeyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(hotKeyCode, forKey: Self.hotKeyCodeKey)
        }
    }

    @Published var hotKeyModifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(hotKeyModifiers, forKey: Self.hotKeyModifiersKey)
        }
    }

    @Published var displayPreference: DisplayPreference {
        didSet {
            UserDefaults.standard.set(displayPreference.rawValue, forKey: Self.displayPreferenceKey)
        }
    }

    @Published var appearance: LaunchpadAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    // Lets the search field and/or category bar be turned off entirely for
    // a leaner, icons-only grid — some users just never use one or the
    // other. Both default on (the overlay's original, only-ever look).
    @Published var showSearchField: Bool {
        didSet {
            UserDefaults.standard.set(showSearchField, forKey: Self.showSearchFieldKey)
        }
    }

    @Published var showCategoryBar: Bool {
        didSet {
            UserDefaults.standard.set(showCategoryBar, forKey: Self.showCategoryBarKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        showMenuBarIcon = defaults.object(forKey: Self.showMenuBarIconKey) != nil
            ? defaults.bool(forKey: Self.showMenuBarIconKey)
            : true
        hotKeyCode = defaults.object(forKey: Self.hotKeyCodeKey) != nil
            ? UInt32(defaults.integer(forKey: Self.hotKeyCodeKey))
            : Self.defaultHotKeyCode
        hotKeyModifiers = defaults.object(forKey: Self.hotKeyModifiersKey) != nil
            ? UInt32(defaults.integer(forKey: Self.hotKeyModifiersKey))
            : Self.defaultHotKeyModifiers
        displayPreference = DisplayPreference(rawValue: defaults.string(forKey: Self.displayPreferenceKey) ?? "cursor")
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(LaunchpadAppearance.init(rawValue:)) ?? .system
        showSearchField = defaults.object(forKey: Self.showSearchFieldKey) != nil
            ? defaults.bool(forKey: Self.showSearchFieldKey)
            : true
        showCategoryBar = defaults.object(forKey: Self.showCategoryBarKey) != nil
            ? defaults.bool(forKey: Self.showCategoryBarKey)
            : true
    }
}
