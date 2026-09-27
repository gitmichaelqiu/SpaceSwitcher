# Bundle-identity migration release

The 1.1.0 release changes the app identifier from `michaelqiu.SpaceSwitcher`
to `dev.mqiu.SpaceSwitcher`. Existing installations update through a one-time
legacy bridge on the old `main` appcast; new-ID builds use the `dev` appcast.
The migration package checksum is pinned into the bridge, and settings are
copied from the legacy defaults domain before the app bundle is replaced.

The supplied 1.1.0 DMG is the staged current-ID application. Keep its build
number (`CFBundleVersion`) aligned with the package version. The current
distribution uses manual approval: the package and bridge are not notarized,
and users may need to approve them in macOS.

## Build the migration package

Mount the current-ID DMG read-only and pass its `SpaceSwitcher.app` to the
package builder. Choose the package's final HTTPS URL before building the
bridge; the URL and exact checksum are embedded in the bridge.

```sh
hdiutil attach -readonly -nobrowse -mountpoint /tmp/SpaceSwitcherDMG \
  "SpaceSwitcher 1.1.0.dmg"
Scripts/build-migration-package.sh \
  --app /tmp/SpaceSwitcherDMG/SpaceSwitcher.app \
  --version 6 \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/dev/appcast.xml \
  --output /tmp/SpaceSwitcher-migration-6.pkg \
  --manual-approval
hdiutil detach /tmp/SpaceSwitcherDMG
shasum -a 256 /tmp/SpaceSwitcher-migration-6.pkg
```

Upload the package to its final release URL before continuing. Do not change
the asset after building the bridge.

## Build and verify the legacy bridge

Use build `6`, which is newer than the published legacy build `5`. The bridge
points at the `main` appcast because that is where the shipped legacy app
checks for updates. Use the exact package URL and checksum returned above.

```sh
Scripts/build-bridge-release.sh \
  --version 1.1.0 --build-number 6 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.0-bridge/SpaceSwitcher-migration-6.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 6 \
  --output-dir /tmp/SpaceSwitcher-bridge-release \
  --source-packages /path/to/SpaceSwitcher/SourcePackages \
  --manual-approval

Scripts/verify-bridge-release.sh \
  --bridge-dmg /tmp/SpaceSwitcher-bridge-release/SpaceSwitcher-1.1.0-bridge.dmg \
  --migration-package /tmp/SpaceSwitcher-migration-6.pkg \
  --version 1.1.0 --build-number 6 --release-tag bridge \
  --feed-url https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml \
  --package-url https://github.com/gitmichaelqiu/SpaceSwitcher/releases/download/v1.1.0-bridge/SpaceSwitcher-migration-6.pkg \
  --package-sha256 PACKAGE_SHA256 --package-version 6 \
  --manual-approval
```

Before publishing, sign the bridge DMG with Sparkle's `sign_update -p`, record
its exact byte length and signature in `appcast.xml`, and put the bridge item
on the default channel with `spaceswitcher:targetBundleIdentifier` set to the
legacy ID. Current-ID appcast items belong to `dev-mqiu` and target
`dev.mqiu.SpaceSwitcher`. Keep the current-ID appcast item separate from the
legacy bridge item. Publish only after the release URLs, signatures, byte
lengths, and both feed copies have been verified.

Signing keys, packages, DMGs, archives, checksums, and Xcode build output stay
outside Git. The scripts do not upload or publish release assets.
