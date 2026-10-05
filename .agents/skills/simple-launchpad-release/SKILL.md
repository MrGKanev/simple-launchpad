---
name: simple-launchpad-release
description: Prepare or publish a Simple Launchpad GitHub release, or build local ZIP and DMG artifacts.
---

# Release Simple Launchpad

Read `.github/workflows/release.yml`, `Scripts/build-app-bundle.sh`,
`Scripts/build-dmg.sh` and `Sources/SimpleLaunchpad/UpdateChecker.swift` first.

For local packaging, run `sh Scripts/build-app-bundle.sh` then
`sh Scripts/build-dmg.sh`. Outputs are under `.build/release/`.
For the updater ZIP, use the workflow's command from that directory:
`zip -r -y "Simple Launchpad.app.zip" "Simple Launchpad.app"`.
Local packaging does not publish or install anything. Artifacts are unsigned and unnotarized.

For a release:

1. Establish the intended commit and version; inspect status, tags and that commit's CI.
   Run `swift build` and `swift test` for the release candidate.
2. Keep `CFBundleVersion` and `CFBundleShortVersionString` in
   `Sources/SimpleLaunchpad/Resources/Info.plist` consistent with the intended numeric
   dotted version. The workflow does not inject the tag into the plist.
   The updater strips an optional `v` prefix; do not assume prerelease ordering is supported.
3. Prepare a reviewable version change and notes from actual changes. A preparation request
   stops before publication. A request to publish authorizes the tag push for the agreed version
   and commit; resolve a missing version before publishing.
4. Push only the intended tag. Any tag push triggers the Release workflow, which builds the app,
   packages ZIP and DMG, and creates a GitHub release with generated notes. It does not run tests.
   Do not create a second competing release pipeline or move a published tag.
5. Watch the matching workflow using `gh run list`, `gh run view` and `gh run watch`.
   Verify both `Simple Launchpad.app.zip` and `Simple Launchpad.dmg` on the release,
   and the bundled version. On failure inspect the failing job before retrying;
   a source fix requires a new release commit and version rather than retagging.

Report the release URL, workflow result and asset verification, or the local artifact paths.
