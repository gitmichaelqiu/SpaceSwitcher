#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="michaelqiu.SpaceSwitcher"
DEFAULT_STAGING_PATH="/Applications/SpaceSwitcher-Migration.app"
PROJECT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/SpaceSwitcher.xcodeproj"

usage() {
    cat <<'EOF'
Usage: build-bridge-release.sh --version VERSION --build-number BUILD \
    --release-tag TAG --feed-url URL --package-url URL --package-sha256 SHA256 \
    --package-version BUILD --output-dir PATH --manual-approval [options]

Builds the legacy-bundle-ID Sparkle bridge DMG. Package URL and checksum must
refer to the final, immutable HTTPS release asset.

Options:
  --staging-path PATH          Installer staging app path
  --source-packages PATH      Cached Xcode SourcePackages directory (offline builds)
  -h, --help                  Show this help
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

to_absolute_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}

read_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

MARKETING_VERSION=""
BUILD_NUMBER=""
RELEASE_TAG=""
FEED_URL=""
PACKAGE_URL=""
PACKAGE_SHA256=""
PACKAGE_VERSION=""
STAGING_PATH="$DEFAULT_STAGING_PATH"
OUTPUT_DIR=""
SOURCE_PACKAGES=""
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --version) (($# >= 2)) || die "--version requires a value"; MARKETING_VERSION="$2"; shift 2 ;;
        --build-number) (($# >= 2)) || die "--build-number requires a value"; BUILD_NUMBER="$2"; shift 2 ;;
        --release-tag) (($# >= 2)) || die "--release-tag requires a value"; RELEASE_TAG="$2"; shift 2 ;;
        --feed-url) (($# >= 2)) || die "--feed-url requires a value"; FEED_URL="$2"; shift 2 ;;
        --package-url) (($# >= 2)) || die "--package-url requires a value"; PACKAGE_URL="$2"; shift 2 ;;
        --package-sha256) (($# >= 2)) || die "--package-sha256 requires a value"; PACKAGE_SHA256="$2"; shift 2 ;;
        --package-version) (($# >= 2)) || die "--package-version requires a value"; PACKAGE_VERSION="$2"; shift 2 ;;
        --staging-path) (($# >= 2)) || die "--staging-path requires a value"; STAGING_PATH="$2"; shift 2 ;;
        --output-dir) (($# >= 2)) || die "--output-dir requires a value"; OUTPUT_DIR="$2"; shift 2 ;;
        --source-packages) (($# >= 2)) || die "--source-packages requires a path"; SOURCE_PACKAGES="$2"; shift 2 ;;
        --manual-approval) MANUAL_APPROVAL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ "$MARKETING_VERSION" =~ ^[0-9]+([.][0-9]+){1,3}$ ]] || die "invalid --version"
[[ "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "invalid --build-number"
[[ "$PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "invalid --package-version"
[[ "$RELEASE_TAG" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid --release-tag"
[[ "$FEED_URL" =~ ^https://[^[:space:]]+$ ]] || die "--feed-url must be HTTPS"
[[ "$PACKAGE_URL" =~ ^https://[^[:space:]]+$ ]] || die "--package-url must be HTTPS"
[[ "$PACKAGE_SHA256" =~ ^[0-9A-Fa-f]{64}$ ]] || die "--package-sha256 must be a 64-character digest"
[[ "$STAGING_PATH" == /* && "$STAGING_PATH" == *.app ]] || die "invalid --staging-path"
[[ -n "$OUTPUT_DIR" ]] || die "--output-dir is required"
((MANUAL_APPROVAL == 1)) || die "this release uses --manual-approval"

OUTPUT_DIR="$(to_absolute_path "$OUTPUT_DIR")"
[[ ! -e "$OUTPUT_DIR/SpaceSwitcher-$MARKETING_VERSION-$RELEASE_TAG.dmg" ]] \
    || die "bridge DMG already exists"
mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SpaceSwitcherBridge.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

BUILD_ARGUMENTS=(
    -project "$PROJECT_PATH"
    -scheme SpaceSwitcher
    -configuration Release
    -destination "generic/platform=macOS"
    -archivePath "$WORK_DIR/SpaceSwitcherBridge.xcarchive"
    -derivedDataPath "$WORK_DIR/DerivedData"
    -disableAutomaticPackageResolution
)
if [[ -n "$SOURCE_PACKAGES" ]]; then
    SOURCE_PACKAGES="$(to_absolute_path "$SOURCE_PACKAGES")"
    [[ -d "$SOURCE_PACKAGES/checkouts/Sparkle" ]] || die "Sparkle checkout missing under --source-packages"
    BUILD_ARGUMENTS+=(-clonedSourcePackagesDirPath "$SOURCE_PACKAGES")
fi

xcodebuild archive "${BUILD_ARGUMENTS[@]}" \
    PRODUCT_BUNDLE_IDENTIFIER="$LEGACY_BUNDLE_IDENTIFIER" \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    INFOPLIST_KEY_SUFeedURL="$FEED_URL" \
    INFOPLIST_KEY_SpaceSwitcherMigrationPackageURL="$PACKAGE_URL" \
    INFOPLIST_KEY_SpaceSwitcherMigrationPackageSHA256="$(printf '%s' "$PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" \
    INFOPLIST_KEY_SpaceSwitcherMigrationPackageVersion="$PACKAGE_VERSION" \
    INFOPLIST_KEY_SpaceSwitcherMigrationAllowManualApproval=YES \
    INFOPLIST_KEY_SpaceSwitcherMigrationStagingPath="$STAGING_PATH" \
    INFOPLIST_KEY_SpaceSwitcherReleaseTag="$RELEASE_TAG" \
    CODE_SIGN_STYLE=Automatic

ARCHIVED_APP="$WORK_DIR/SpaceSwitcherBridge.xcarchive/Products/Applications/SpaceSwitcher.app"
[[ -d "$ARCHIVED_APP/Contents" ]] || die "archived SpaceSwitcher.app is missing"
APP_INFO_PLIST="$ARCHIVED_APP/Contents/Info.plist"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$LEGACY_BUNDLE_IDENTIFIER" ]] \
    || die "bridge bundle identifier mismatch"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$BUILD_NUMBER" ]] \
    || die "bridge build number mismatch"
[[ "$(read_plist_value "$APP_INFO_PLIST" SUFeedURL)" == "$FEED_URL" ]] \
    || die "bridge feed URL mismatch"
[[ "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageURL)" == "$PACKAGE_URL" ]] \
    || die "embedded package URL mismatch"
[[ "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageSHA256)" == "$(printf '%s' "$PACKAGE_SHA256" | tr '[:upper:]' '[:lower:]')" ]] \
    || die "embedded package checksum mismatch"
[[ "$(read_plist_value "$APP_INFO_PLIST" SpaceSwitcherMigrationPackageVersion)" == "$PACKAGE_VERSION" ]] \
    || die "embedded package build mismatch"

BRIDGE_APP="$OUTPUT_DIR/SpaceSwitcher.app"
ditto "$ARCHIVED_APP" "$BRIDGE_APP"
if ! codesign --verify --deep --strict "$BRIDGE_APP" >/dev/null 2>&1; then
    echo "warning: bridge signature is not trusted locally; manual approval will be required" >&2
fi

DMG_ROOT="$WORK_DIR/dmg"
mkdir -p "$DMG_ROOT"
ditto "$BRIDGE_APP" "$DMG_ROOT/SpaceSwitcher.app"
ln -s /Applications "$DMG_ROOT/Applications"
DMG_PATH="$OUTPUT_DIR/SpaceSwitcher-$MARKETING_VERSION-$RELEASE_TAG.dmg"
hdiutil create -volname "SpaceSwitcher $MARKETING_VERSION Bridge" \
    -srcfolder "$DMG_ROOT" -format UDZO "$DMG_PATH"

echo "Bridge app: $BRIDGE_APP"
echo "Bridge DMG: $DMG_PATH"
echo "Bridge DMG SHA256: $(shasum -a 256 "$DMG_PATH" | awk '{print tolower($1)}')"
