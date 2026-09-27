#!/bin/bash
set -euo pipefail

LEGACY_BUNDLE_IDENTIFIER="michaelqiu.SpaceSwitcher"
CURRENT_BUNDLE_IDENTIFIER="dev.mqiu.SpaceSwitcher"
EXPECTED_TEAM_IDENTIFIER="W94S87F4LJ"
STAGED_APPLICATION_NAME="SpaceSwitcher-Migration.app"
DEFAULT_PACKAGE_IDENTIFIER="dev.mqiu.SpaceSwitcher.migration"

usage() {
    cat <<'EOF'
Usage: build-migration-package.sh --app PATH --version BUILD \
    --feed-url URL --output PATH --manual-approval

Builds an unsigned migration package that stages the current-ID application
at /Applications/SpaceSwitcher-Migration.app for the legacy bridge.
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

team_identifier_for_app() {
    codesign -dv --verbose=4 "$1" 2>&1 \
        | awk -F= '$1 == "TeamIdentifier" { print $2; exit }'
}

APP_PATH=""
PACKAGE_VERSION=""
FEED_URL=""
OUTPUT_PATH=""
PACKAGE_IDENTIFIER="$DEFAULT_PACKAGE_IDENTIFIER"
MANUAL_APPROVAL=0

while (($# > 0)); do
    case "$1" in
        --app)
            (($# >= 2)) || die "--app requires a path"
            APP_PATH="$2"
            shift 2
            ;;
        --version)
            (($# >= 2)) || die "--version requires a build number"
            PACKAGE_VERSION="$2"
            shift 2
            ;;
        --feed-url)
            (($# >= 2)) || die "--feed-url requires a URL"
            FEED_URL="$2"
            shift 2
            ;;
        --output)
            (($# >= 2)) || die "--output requires a path"
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --package-identifier)
            (($# >= 2)) || die "--package-identifier requires an identifier"
            PACKAGE_IDENTIFIER="$2"
            shift 2
            ;;
        --manual-approval)
            MANUAL_APPROVAL=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$APP_PATH" ]] || die "--app is required"
[[ -n "$PACKAGE_VERSION" ]] || die "--version is required"
[[ "$PACKAGE_VERSION" =~ ^[0-9]+([.][0-9]+){0,3}$ ]] || die "invalid build number"
[[ "$FEED_URL" =~ ^https://[^[:space:]]+$ ]] || die "--feed-url must be HTTPS"
[[ -n "$OUTPUT_PATH" ]] || die "--output is required"
((MANUAL_APPROVAL == 1)) || die "this release uses --manual-approval"
[[ "$PACKAGE_IDENTIFIER" =~ ^[A-Za-z0-9.-]+$ ]] || die "invalid package identifier"

APP_PATH="$(to_absolute_path "$APP_PATH")"
OUTPUT_PATH="$(to_absolute_path "$OUTPUT_PATH")"
[[ -d "$APP_PATH/Contents" ]] || die "app bundle not found: $APP_PATH"
[[ "$APP_PATH" == *.app ]] || die "--app must point to an .app bundle"
[[ "$OUTPUT_PATH" == *.pkg ]] || die "--output must end in .pkg"
[[ ! -e "$OUTPUT_PATH" ]] || die "output already exists: $OUTPUT_PATH"

APP_INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleIdentifier)" == "$CURRENT_BUNDLE_IDENTIFIER" ]] \
    || die "app must use bundle identifier $CURRENT_BUNDLE_IDENTIFIER"
[[ "$(read_plist_value "$APP_INFO_PLIST" CFBundleVersion)" == "$PACKAGE_VERSION" ]] \
    || die "app CFBundleVersion does not match --version"
[[ "$(read_plist_value "$APP_INFO_PLIST" SUFeedURL)" == "$FEED_URL" ]] \
    || die "app SUFeedURL does not match --feed-url"
[[ "$(team_identifier_for_app "$APP_PATH")" == "$EXPECTED_TEAM_IDENTIFIER" ]] \
    || die "app must be signed by team $EXPECTED_TEAM_IDENTIFIER"

mkdir -p "$(dirname "$OUTPUT_PATH")"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SpaceSwitcherMigrationPackage.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

PACKAGE_ROOT="$WORK_DIR/root"
mkdir -p "$PACKAGE_ROOT/Applications"
ditto "$APP_PATH" "$PACKAGE_ROOT/Applications/$STAGED_APPLICATION_NAME"

if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "warning: app signature is not trusted locally; manual approval will be required" >&2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
pkgbuild \
    --root "$PACKAGE_ROOT" \
    --identifier "$PACKAGE_IDENTIFIER" \
    --version "$PACKAGE_VERSION" \
    --install-location / \
    --scripts "$SCRIPT_DIR/migration-package-scripts" \
    "$OUTPUT_PATH"

echo "warning: migration package is unsigned and intended for manual approval" >&2
echo "Migration package: $OUTPUT_PATH"
echo "Migration package SHA256: $(shasum -a 256 "$OUTPUT_PATH" | awk '{print tolower($1)}')"
