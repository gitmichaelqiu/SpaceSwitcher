# Bundle-identity migration release

The 1.1.0 release changes the app identifier from `michaelqiu.SpaceSwitcher`
to `dev.mqiu.SpaceSwitcher`. All release artifacts and appcast updates are
published from `main`. Existing installations update through a one-time legacy
bridge on the `main` appcast; new-ID builds use that same feed. The migration
package checksum is pinned into the bridge, and settings are copied from the
legacy defaults domain before the app bundle is replaced.

For the 1.1.1 migration fix, build the current-ID app from this `main` checkout
with build number `7`; use that archived app both for the normal release DMG
and the migration package. Keep `CFBundleVersion` aligned. The current
distribution uses manual approval: the package and bridge are not notarized,
and users may need to approve them in macOS.

## Build the migration package

Mount the current-ID DMG read-only and pass its `SpaceSwitcher.app` to the
package builder. Choose the package's final HTTPS URL before building the
bridge; the URL and exact checksum are embedded in the bridge.

```sh
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath /tmp/SpaceSwitcher-1.1.1.xcarchive archive
ARCHIVED_APP=/tmp/SpaceSwitcher-1.1.1.xcarchive/Products/Applications/SpaceSwitcher.app
mkdir -p /tmp/SpaceSwitcher-1.1.1-dmg
ditto "$ARCHIVED_APP" /tmp/SpaceSwitcher-1.1.1-dmg/SpaceSwitcher.app
ln -s /Applications /tmp/SpaceSwitcher-1.1.1-dmg/Applications
hdiutil create -volname "SpaceSwitcher 1.1.1" -srcfolder /tmp/SpaceSwitcher-1.1.1-dmg \
  -format UDZO /tmp/SpaceSwitcher.1.1.1.dmg
Scripts/build-migration-package.sh \
  --app "$ARCHIVED_APP" \
  --version 7 \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --output /tmp/SpaceSwitcher-migration-7.pkg \
  --manual-approval
shasum -a 256 /tmp/SpaceSwitcher-migration-7.pkg
```

Upload the package to its final release URL before continuing. Do not change
the asset after building the bridge.

## Build and verify the legacy bridge

Use bridge build `7`, which is newer than the published legacy build `6`. The
bridge points at the `main` appcast, where the shipped legacy app checks for
updates. Use the exact package URL and checksum returned above.

```sh
Scripts/build-bridge-release.sh \
  --version 1.1.1 --build-number 7 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.1-bridge/SpaceSwitcher-migration-7.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 7 \
  --output-dir /tmp/SpaceSwitcher-bridge-release \
  --source-packages /path/to/SpaceSwitcher/SourcePackages \
  --manual-approval

Scripts/verify-bridge-release.sh \
  --bridge-dmg /tmp/SpaceSwitcher-bridge-release/SpaceSwitcher-1.1.1-bridge.dmg \
  --migration-package /tmp/SpaceSwitcher-migration-7.pkg \
  --version 1.1.1 --build-number 7 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.1-bridge/SpaceSwitcher-migration-7.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 7 \
  --manual-approval
```

Before publishing, sign the bridge DMG with Sparkle's `sign_update -p`, record
its exact byte length and signature in `appcast.xml`, and put the bridge item
on the default channel with `spaceswitcher:targetBundleIdentifier` set to the
legacy ID. Current-ID appcast items belong to `dev-mqiu` and target
`dev.mqiu.SpaceSwitcher`. Keep the current-ID appcast item separate from the
legacy bridge item. Publish only after the release URLs, signatures, byte
lengths, and the `main` feed have been verified.

Signing keys, packages, DMGs, archives, checksums, and Xcode build output stay
outside Git. The scripts do not upload or publish release assets.
