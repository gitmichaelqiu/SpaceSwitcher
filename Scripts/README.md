# Bundle-identity migration release

The 1.1.0 release changes the app identifier from `michaelqiu.SpaceSwitcher`
to `dev.mqiu.SpaceSwitcher`. All release artifacts and appcast updates are
published from `main`. Existing installations update through a one-time legacy
bridge on the `main` appcast; new-ID builds use that same feed. The migration
package checksum is pinned into the bridge, and settings are copied from the
legacy defaults domain before the app bundle is replaced. The app's
`SUPublicEDKey` is stored in `SpaceSwitcher/info.plist`; release verification
checks the key in both the bridge and staged app bundles.

For the 1.1.2 migration fix, build the current-ID app from this `main` checkout
with build number `8`; use that archived app both for the normal release DMG
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
  -archivePath /tmp/SpaceSwitcher-1.1.2.xcarchive archive
ARCHIVED_APP=/tmp/SpaceSwitcher-1.1.2.xcarchive/Products/Applications/SpaceSwitcher.app
mkdir -p /tmp/SpaceSwitcher-1.1.2-dmg
ditto "$ARCHIVED_APP" /tmp/SpaceSwitcher-1.1.2-dmg/SpaceSwitcher.app
ln -s /Applications /tmp/SpaceSwitcher-1.1.2-dmg/Applications
hdiutil create -volname "SpaceSwitcher 1.1.2" -srcfolder /tmp/SpaceSwitcher-1.1.2-dmg \
  -format UDZO /tmp/SpaceSwitcher.1.1.2.dmg
Scripts/build-migration-package.sh \
  --app "$ARCHIVED_APP" \
  --version 8 \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --output /tmp/SpaceSwitcher-migration-8.pkg \
  --manual-approval
shasum -a 256 /tmp/SpaceSwitcher-migration-8.pkg
```

Upload the package to its final release URL before continuing. Do not change
the asset after building the bridge.

## Build and verify the legacy bridge

Use bridge build `7`, which is newer than the published legacy build `6`. The
bridge points at the `main` appcast, where the shipped legacy app checks for
updates. Use the exact package URL and checksum returned above.

```sh
Scripts/build-bridge-release.sh \
  --version 1.1.2 --build-number 8 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.2-bridge/SpaceSwitcher-migration-8.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 8 \
  --output-dir /tmp/SpaceSwitcher-bridge-release \
  --source-packages /path/to/SpaceSwitcher/SourcePackages \
  --manual-approval

Scripts/verify-bridge-release.sh \
  --bridge-dmg /tmp/SpaceSwitcher-bridge-release/SpaceSwitcher-1.1.2-bridge.dmg \
  --migration-package /tmp/SpaceSwitcher-migration-8.pkg \
  --version 1.1.2 --build-number 8 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.2-bridge/SpaceSwitcher-migration-8.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 8 \
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
