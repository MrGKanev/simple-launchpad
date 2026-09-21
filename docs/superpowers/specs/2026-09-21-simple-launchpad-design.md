# Simple Launchpad — Design

## Goal

A minimal, fast, native macOS clone of the classic Launchpad: fullscreen grid
of installed apps, paging, folders, drag-to-reorder, search. Opened via a
menu bar icon or a global hotkey. Ships as an open-source project buildable
and testable via GitHub Actions.

## Non-goals

- Code signing / notarization (no Apple Developer account in scope)
- Automated .dmg/release publishing (can be added later via a tag-triggered
  workflow)
- Settings UI (hotkey, appearance, etc.) — hardcoded sensible defaults
- Cross-platform support

## Architecture

Swift Package Manager executable target (no `.xcodeproj`) built with
`swift build`. SwiftUI implements the grid/paging/drag&drop/search UI. A thin
AppKit layer covers what SwiftUI does not: a borderless fullscreen window, a
menu bar item, and a global hotkey via Carbon `RegisterEventHotKey` (works
without Accessibility/Input Monitoring permission, unlike
`NSEvent.addGlobalMonitorForEvents`).

The app runs as a menu-bar-only agent (`LSUIElement = true` in Info.plist) —
no Dock icon.

## Components

- **`App.swift`** — entry point, `NSApplicationDelegate`, wires up the pieces
  below at launch.
- **`HotKeyManager`** — registers a default global hotkey (e.g. the F4/Launchpad
  key), calls a closure to toggle the overlay. Logs and no-ops on registration
  failure (menu bar click remains as fallback).
- **`StatusItemController`** — owns an `NSStatusItem` with an icon; click
  toggles the overlay.
- **`OverlayWindowController`** — a borderless, fullscreen `NSWindow` hosting
  the SwiftUI root view via `NSHostingView`. Closes on Esc, click outside the
  grid, or launching an app.
- **`AppDiscoveryService`** — shallow-scans `/Applications`, `~/Applications`,
  `/System/Applications`, `/System/Applications/Utilities` for `.app`
  bundles; returns name, bundle identifier, and icon
  (`NSWorkspace.shared.icon(forFile:)`).
- **`LaunchpadStore`** (`ObservableObject`) — holds `pages: [[LaunchpadItem]]`
  where `LaunchpadItem` is `.app(AppInfo)` or `.folder(FolderInfo)`. Merges
  freshly discovered apps with the persisted layout on load; applies
  drag&drop mutations; triggers persistence.
- **`LayoutPersistence`** — reads/writes JSON at
  `~/Library/Application Support/SimpleLaunchpad/layout.json`.
- **Views** (`Sources/SimpleLaunchpad/Views/`):
  - `LaunchpadView` — root view, page-swiping + page-dot indicator
  - `PageView` — `LazyVGrid` of icons for one page
  - `AppIconView` — icon + label, drag source/target
  - `FolderView` — expanded overlay showing a folder's contents; created by
    dragging one app icon onto another
  - `SearchField` — text field that switches the view to a flat filtered
    list across all apps, ignoring pages/folders

## Data flow

1. **Launch**: `AppDiscoveryService` scans disk → `LayoutPersistence` loads
   saved layout (or nil) → `LaunchpadStore` merges: known apps keep their
   saved position, newly-found apps are appended to the last page, apps no
   longer on disk are dropped, folders left empty are dropped.
2. **Reorder**: drag&drop mutates `LaunchpadStore.pages` in memory; a save to
   JSON happens on drop-end (not per-frame).
3. **Search**: typing switches to a flat filtered grid over all known apps;
   Enter or click launches the selected app via
   `NSWorkspace.shared.openApplication`.
4. **Hotkey / menu bar click**: toggles the overlay window. The window is
   created lazily on first show.

## Error handling

- Missing or corrupt `layout.json` → fall back to an alphabetically sorted
  default layout; never crash on parse failure.
- An app referenced in the saved layout no longer exists on disk → dropped
  silently on next load.
- Icon lookup fails → generic app icon placeholder.
- Hotkey registration fails (conflict) → warning logged; menu bar icon click
  still activates the overlay.

## Testing

XCTest unit tests only, no UI/snapshot tests for MVP:

- `AppDiscoveryServiceTests` — scans a temp directory containing fake `.app`
  bundle stand-ins, verifies name/bundle-id extraction and that non-`.app`
  entries are ignored.
- `LayoutPersistenceTests` — JSON round-trip, and the merge logic (new apps
  appended, missing apps/empty folders pruned, known app order preserved).
- Search filter logic — matches by substring on app name, case-insensitive.

## Repo structure

```
simple-launchpad/
  Package.swift
  Sources/SimpleLaunchpad/
    App.swift
    HotKeyManager.swift
    StatusItemController.swift
    OverlayWindowController.swift
    AppDiscoveryService.swift
    LaunchpadStore.swift
    LayoutPersistence.swift
    Views/
      LaunchpadView.swift
      PageView.swift
      AppIconView.swift
      FolderView.swift
      SearchField.swift
    Resources/
      Info.plist
  Tests/SimpleLaunchpadTests/
    AppDiscoveryServiceTests.swift
    LayoutPersistenceTests.swift
  .github/workflows/ci.yml
  README.md
```

## CI/CD

`.github/workflows/ci.yml`, triggered on `pull_request` only, running on
`macos-latest`: checkout → `swift build` → `swift test`. No release/dmg
automation for now.
