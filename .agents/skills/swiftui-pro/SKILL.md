---
name: swiftui-pro
description: Write and review Simple Launchpad macOS SwiftUI views for data flow, accessibility, API correctness and measured performance.
license: MIT
metadata:
  author: Paul Hudson
  version: "1.1-launchpad.1"
  adapted-for: Simple Launchpad
---

# SwiftUI in Simple Launchpad

Simple Launchpad targets macOS 13 with Swift tools 5.9, as declared in `Package.swift`.
Check availability before using newer APIs in the references, including Observation, modern
`onChange`, `Tab` and animation completion. Preserve compatible existing APIs and follow
neighbouring code for architecture and file organisation. AppKit integration is intentional; do not apply iOS-only
rules or replace working bridges simply because a SwiftUI API exists.

For a review, report actionable defects with file locations and their effects. For an edit,
make the requested change. Avoid sweeping API migrations, fixed review templates and stylistic
findings without a concrete benefit.

Load only the references relevant to the code:

- [Data](references/data.md): state ownership, observation and bindings.
- [Views](references/views.md): composition, actions, previews and animation.
- [API](references/api.md): API migrations and platform availability.
- [Navigation](references/navigation.md): navigation state, sheets and dialogs.
- [Accessibility](references/accessibility.md): labels, keyboard access, contrast and motion.
- [Design](references/design.md): Simple Launchpad's design system and native Mac layout.
- [Performance](references/performance.md): identity, observation boundaries and expensive work.
- [Swift](references/swift.md): language and Foundation choices affecting UI code.
- [Hygiene](references/hygiene.md): project validation and handling sensitive data.
