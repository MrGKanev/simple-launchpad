---
name: simple-launchpad-dev-build
description: Build, test or run Simple Launchpad locally using the existing Swift package and app bundle script.
---

# Build Simple Launchpad

Run from the repository root. Read `Package.swift`, `README.md` and
`Scripts/build-app-bundle.sh` when diagnosing build issues.

| Purpose | Command |
| --- | --- |
| Compile current edits | `swift build` |
| Run relevant tests | `swift test --filter <filter>` |
| Run all tests | `swift test` |
| Run locally when requested | `swift run` |
| Build a release app bundle | `sh Scripts/build-app-bundle.sh` |
| Open that bundle when requested | `open ".build/release/Simple Launchpad.app"` |

The package requires macOS 13 or later and a Swift tools 5.9 compatible toolchain.
Builds include current edits; no commit is needed. Prefer compile/test for verification.
The bundle script rebuilds `.build/release/Simple Launchpad.app` and does not install it.
Verify its executable and `Contents/Info.plist`; the identifier is `dev.skanevi.simplelaunchpad`.
The app is unsigned. There is no separate dev identity or isolated dev preferences;
launching can share the installed app's data. Preserve existing layouts and preferences.
Report commands, results, and whether the app was launched.
