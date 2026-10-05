---
name: swift-testing-pro
description: Write and review Simple Launchpad XCTest tests, including async behaviour, isolated fixtures and regressions; use Swift Testing guidance for requested migrations.
license: MIT
metadata:
  author: Paul Hudson
  version: "1.0-launchpad.1"
  adapted-for: Simple Launchpad
---

# Testing Simple Launchpad

Follow the existing XCTest suites in `Tests/SimpleLaunchpadTests`, using
`@testable import SimpleLaunchpad`. Keep XCTest for new tests in this project.
The Swift Testing examples in the references apply only to a requested migration with a
compatible toolchain; do not raise the Swift tools 5.9 baseline just to adopt them.

Run `swift test --filter <filter>` for affected suites, `swift test` for the full suite,
and `swift build` to verify compilation. See `.github/workflows/ci.yml` for CI.
Keep network and machine-dependent checks controlled and isolated.

Keep assertions about observable behaviour. Lift mutating calls out of assertions: store their
result in a local, then assert on it. Use isolated temporary files, databases and defaults domains.

For reviews, report actual defects with file locations and effects. For test changes, edit the
files directly. Check installed toolchain/API availability rather than treating this guide as
more authoritative than compiler diagnostics or upstream documentation.

Load only the relevant references:

- [Core rules](references/core-rules.md): suites, assertions and parameterised cases.
- [Test design](references/writing-better-tests.md): dependencies, errors and useful regressions.
- [Async tests](references/async-tests.md): serialisation, completion and cancellation.
- [Newer APIs](references/new-features.md): version-dependent testing features.
- [XCTest migration](references/migrating-from-xctest.md): only for a requested migration.
