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
- **Rename a folder** — click its name while it's open to edit it in place.
- **Multi-select** — Cmd/Shift-click app icons to select several, then
  right-click any of them for "Remove N from Launchpad" or "Move N to
  Trash…", or drag one of them onto a target to move the whole selection
  into that folder (or a new one) at once.
- **Reorder pages** — drag a page dot onto another to reorder pages.
- **Drag to a page edge** — hold a dragged icon over the left/right edge of
  the grid briefly to flip to that page, so you can drop it somewhere other
  than the page you started on.
- **Reset Layout** (in Settings) — rebuilds the grid alphabetically,
  discarding custom folders/ordering, if things get into a state you don't
  want.
- Auto-closes when you click elsewhere (a Dock icon, another app) or open
  Settings, matching stock Launchpad's behavior.
- Fast, subtle fade/scale animation when the grid and folders open and
  close, instead of appearing/disappearing instantly.

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
`.github/workflows/release.yml`, which builds the app and attaches two
assets to a new GitHub Release: a `.dmg` (a drag-to-`/Applications` installer,
for a first install) and a `.zip` (what the in-app updater fetches). The
in-app "Check for Updates" button reads the release, and if it's newer than
the running version, downloads the `.zip`, strips the quarantine flag (the
app isn't notarized), and swaps itself in place.
