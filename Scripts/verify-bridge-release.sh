#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="michaelqiu.SpaceSwitcher"
CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.SpaceSwitcher"
EXPECTED_TEAM_IDENTIFIER="W94S87F4LJ"
STAGED_APPLICATION_NAME="SpaceSwitcher-Migration.app"

die() {
    echo "error: $*" >&2
    exit 1
}

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

team_identifier_for_app() {
    codesign -dv --verbose=4 "$1" 2>&1 \
        | awk -F= '$1 == "TeamIdentifier" { print $2; exit }'
}

assert_equal() {
    local label="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] || die "$label mismatch (expected '$expected', got '$actual')"
}

BRIDGE_DMG=""
MIGRATION_PACKAGE=""
MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
PACKAGE_URL=""
PACKAGE_SHA256=""
PACKAGE_VERSION=""
STAGING_PATH="/Applications/SpaceSwitcher-Migration.app"
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --bridge-dmg) (($# >= 2)) || die "--bridge-dmg requires a path"; BRIDGE_DMG="$2"; shift 2 ;;
        --migration-package) (($# >= 2)) || die "--migration-package requires a path"; MIGRATION_PACKAGE="$2"; shift 2 ;;
        --version) (($# >= 2)) || die "--version requires a value"; MARKETING_VERSION="$2"; shift 2 ;;
        --build-number) (($# >= 2)) || die "--build-number requires a value"; BUILD_NUMBER="$2"; shift 2 ;;
        --release-tag) (($# >= 2)) || die "--release-tag requires a value"; RELEASE_TAG="$2"; shift 2 ;;
        --feed-url) (($# >= 2)) || die "--feed-url requires a URL"; FEED_URL="$2"; shift 2 ;;
        --package-url) (($# >= 2)) || die "--package-url requires a URL"; PACKAGE_URL="$2"; shift 2 ;;
        --package-sha256) (($# >= 2)) || die "--package-sha256 requires a digest"; PACKAGE_SHA256="$2"; shift 2 ;;
        --package-version) (($# >= 2)) || die "--package-version requires a build"; PACKAGE_VERSION="$2"; shift 2 ;;
        --staging-path) (($# >= 2)) || die "--staging-path requires a path"; STAGING_PATH="$2"; shift 2 ;;
        --manual-approval) MANUAL_APPROVAL=1; shift ;;
        -h|--help)
            echo "Usage: verify-bridge-release.sh --bridge-dmg PATH --migration-package PATH --version VERSION --build-number BUILD --release-tag TAG --feed-url URL --package-url URL --package-sha256 SHA256 --package-version BUILD --manual-approval [--staging-path PATH]"
            exit 0
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -f "$BRIDGE_DMG" ]] || die "bridge DMG not found"
[[ -f "$MIGRATION_PACKAGE" ]] || die "migration package not found"
[[ "$PACKAGE_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "invalid package checksum"
[[ "$FEED_URL" =~ ^https://[^[:space:]]+$ ]] || die "feed URL must be HTTPS"
[[ "$PACKAGE_URL" =~ ^https://[^[:space:]]+$ ]] || die "package URL must be HTTPS"
((MANUAL_APPROVAL == 1)) || die "this release uses --manual-approval"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SpaceSwitcherBridgeVerify.XXXXXX")"
cleanup() {
    if [[ -n "${MOUNT_POINT:-}" ]] && [[ "${DMG_ATTACHED:-0}" == "1" ]]; then
        hdiutil detach -quiet "$MOUNT_POINT" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

MOUNT_POINT="$WORK_DIR/mount"
mkdir -p "$MOUNT_POINT"
hdiutil verify "$BRIDGE_DMG"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$BRIDGE_DMG" >/dev/null
DMG_ATTACHED=1
BRIDGE_APP="$MOUNT_POINT/SpaceSwitcher.app"
[[ -f "$BRIDGE_APP/Contents/Info.plist" ]] || die "SpaceSwitcher.app missing from bridge DMG"
APP_INFO_PLIST="$BRIDGE_APP/Contents/Info.plist"
assert_equal "bridge bundle ID" "$LEGACY_BUNDLE_IDENTIFIER" "$(read_plist_value "$APP_INFO_PLIST" CFBundleIdentifier)"
assert_equal "bridge signing team" "$EXPECTED_TEAM_IDENTIFIER" "$(team_identifier_for_app "$BRIDGE_APP")"
assert_equal "bridge version" "$MARKETING_VERSION" "$(read_plist_value "$APP_INFO_PLIST" CFBundleShortVersionString)"
assert_equal "bridge build" "$BUILD_NUMBER" "$(read_plist_value "$APP_INFO_PLIST" CFBundleVersion)"
assert_equal "bridge feed URL" "$FEED_URL" "$(read_plist_value "$APP_INFO_PLIST" SUFeedURL)"
assert_equal "bridge package URL" "$PACKAGE_URL" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageURL)"
assert_equal "bridge package checksum" "$(printf '%s' "$PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageSHA256)"
assert_equal "bridge package build" "$PACKAGE_VERSION" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageVersion)"
assert_equal "bridge manual-approval flag" "true" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationAllowManualApproval | tr '[:upper:]' '[:lower:]')"
assert_equal "bridge staging path" "$STAGING_PATH" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationStagingPath)"
assert_equal "bridge release tag" "$RELEASE_TAG" "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherReleaseTag)"

if ! codesign --verify --deep --strict "$BRIDGE_APP" >/dev/null 2>&1; then
    echo "warning: bridge signature is not trusted locally; manual approval is required" >&2
fi

ACTUAL_PACKAGE_SHA256="$(shasum -a 256 "$MIGRATION_PACKAGE" | awk '{print tolower($1)}')"
assert_equal "migration package SHA256" "$(printf '%s' "$PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" "$ACTUAL_PACKAGE_SHA256"
EXPANDED_PACKAGE="$WORK_DIR/expanded-package"
pkgutil --expand-full "$MIGRATION_PACKAGE" "$EXPANDED_PACKAGE" >/dev/null
STAGED_APP="$EXPANDED_PACKAGE/Payload/Applications/$STAGED_APPLICATION_NAME"
[[ -f "$STAGED_APP/Contents/Info.plist" ]] || die "staged app missing from migration package"
assert_equal "staged app bundle ID" "$CURRENT_BUNDLE_IDENTIFIER" "$(read_plist_value "$STAGED_APP/Contents/Info.plist" CFBundleIdentifier)"
assert_equal "staged app signing team" "$EXPECTED_TEAM_IDENTIFIER" "$(team_identifier_for_app "$STAGED_APP")"
assert_equal "staged app build" "$PACKAGE_VERSION" "$(read_plist_value "$STAGED_APP/Contents/Info.plist" CFBundleVersion)"
assert_equal "staged app feed URL" "https://raw.githubusercontent.com/gitmichaelqiu/SpaceSwitcher/main/appcast.xml" "$(read_plist_value "$STAGED_APP/Contents/Info.plist" SUFeedURL)"
if ! codesign --verify --deep --strict "$STAGED_APP" >/dev/null 2>&1; then
    echo "warning: staged app signature is not trusted locally; manual approval is required" >&2
fi

echo "Bridge release verification passed"
echo "Bridge DMG: $BRIDGE_DMG"
echo "Migration package: $MIGRATION_PACKAGE"
echo "Migration package SHA256: $ACTUAL_PACKAGE_SHA256"
