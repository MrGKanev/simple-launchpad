import SwiftUI

// User-facing "Appearance" preference (Settings) — independent of the
// system's own light/dark setting, since the overlay otherwise always
// inherits whatever macOS is currently in.
enum LaunchpadAppearance: String, CaseIterable, Identifiable, Codable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    // `nil` here (System) is the "don't override" case for both
    // `NSAppearance` (window-level, in `OverlayWindowController`) and
    // SwiftUI's `.preferredColorScheme` (view-level, in `LaunchpadView`).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// Every overlay-facing color derives from here instead of being hardcoded
// per view, so the "Light"/"Dark" appearance setting actually changes how
// things look instead of just leaving `Color.white` text sitting on a now-
// light backdrop. Resolved once per view from `@Environment(\.colorScheme)`
// (itself driven by `.preferredColorScheme`, see `LaunchpadAppearance`).
struct LaunchpadPalette {
    let isDark: Bool

    static func resolve(_ colorScheme: ColorScheme) -> LaunchpadPalette {
        LaunchpadPalette(isDark: colorScheme != .light)
    }

    var text: Color { isDark ? .white : Color.black.opacity(0.85) }
    var secondaryText: Color { isDark ? Color.white.opacity(0.7) : Color.black.opacity(0.55) }
    var backdropTint: Color { isDark ? Color.black.opacity(0.18) : Color.white.opacity(0.32) }
    var selectionFill: Color { isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12) }
    var folderTileFill: Color { isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08) }
    var folderBackdrop: Color { isDark ? Color.black.opacity(0.85) : Color.white.opacity(0.92) }
    var pillSelectedFill: Color { isDark ? .white : Color.black.opacity(0.85) }
    var pillSelectedText: Color { isDark ? .black : .white }
    var pillFill: Color { isDark ? Color.white.opacity(0.14) : Color.black.opacity(0.08) }
    var pillText: Color { isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75) }
    var pillDropTargetFill: Color { isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.22) }
    var dotActive: Color { isDark ? .white : Color.black.opacity(0.8) }
    var dotInactive: Color { isDark ? Color.white.opacity(0.4) : Color.black.opacity(0.25) }
}
