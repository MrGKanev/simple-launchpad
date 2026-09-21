# Simple Launchpad

A minimal, fast, native macOS clone of the classic Launchpad app grid.
A menu bar icon and a global hotkey (F4) open a fullscreen grid of your
installed apps, with paging, search, drag-to-reorder, and folders (drag
one app onto another and hold briefly to group them).

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

## Design

See [docs/superpowers/specs/2026-09-21-simple-launchpad-design.md](docs/superpowers/specs/2026-09-21-simple-launchpad-design.md).
