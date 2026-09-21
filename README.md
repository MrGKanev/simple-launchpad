# Simple Launchpad

A minimal, fast, native macOS clone of the classic Launchpad app grid.
A menu bar icon, a Dock icon, and a global hotkey (F4 by default,
customizable) open a fullscreen grid of your installed apps, with paging,
search, drag-to-reorder, and folders (drag one app onto another and hold
briefly to group them).

## Features

- **Menu bar icon** — click to toggle the grid; right/control-click for a
  Settings/Quit menu. Can be hidden from Settings without losing access
  (the global hotkey and the Dock icon's menu still work).
- **Dock icon** — click to toggle the grid (reopens it if the app resigned
  active, closes it if already open); right/control-click lists every known
  app (including ones tucked inside folders) plus Settings, so it doubles as
  a quick launcher for anything installed.
- **Global hotkey** — F4 by default, recordable to anything in Settings.
- **Keyboard navigation** — arrow keys move a highlight across the grid (or
  search results), Return launches the highlighted app or opens the
  highlighted folder, Esc backs out of an open folder before closing the
  whole overlay.
- **Remove from Launchpad** — right-click any app icon (on the grid, inside
  a folder, or in search results) for a "Remove from Launchpad" option
  (grid only) or "Move to Trash…" (confirms, then actually uninstalls it).
  Removing/uninstalling the last icon on a page drops that empty page
  instead of leaving a blank one to page through.
- **Settings** (Settings… from either menu) — Launch at Login, show/hide
  the menu bar icon, the hotkey recorder, and a "Check for Updates" button
  that downloads and installs the latest GitHub release in place.
- Auto-closes when you click elsewhere (a Dock icon, another app) or open
  Settings, matching stock Launchpad's behavior.

## Build & run

```sh
swift build
swift run
```

## Test

```sh
swift test
```

## Create a distributable .app

```sh
./Scripts/build-app-bundle.sh
open ".build/release/Simple Launchpad.app"
```

The app is unsigned. On first launch, right-click the app and choose
**Open** to bypass Gatekeeper, or run:

```sh
xattr -dr com.apple.quarantine ".build/release/Simple Launchpad.app"
```

## Releases & auto-update

Pushing a tag (e.g. `git tag 1.1 && git push origin 1.1`) triggers
`.github/workflows/release.yml`, which builds the app, zips it, and attaches
it to a new GitHub Release. The in-app "Check for Updates" button reads that
release, and if it's newer than the running version, downloads it, strips
the quarantine flag (the app isn't notarized), and swaps itself in place.
