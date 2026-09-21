import Foundation
import Combine
import Carbon

// Backed by UserDefaults so the choice survives relaunches; `@Published` (a
// plain Combine property wrapper, not one of the newer macro-based ones) is
// safe to use directly under this project's toolchain — see the `@State`
// caveat noted elsewhere for what isn't.
final class AppPreferences: ObservableObject {
    private static let showMenuBarIconKey = "showMenuBarIcon"
    private static let hotKeyCodeKey = "hotKeyCode"
    private static let hotKeyModifiersKey = "hotKeyModifiers"

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
    }
}
