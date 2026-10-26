#!/usr/bin/env bash
#
# The fast iteration loop: stage the app, rewrite it for the simulator platform,
# build and inject the simulator dylib, install, and launch.
#
#   ./scripts/sim.sh                            # uses vendor/*.ipa
#   ./scripts/sim.sh path/to/App.ipa
#   ./scripts/sim.sh path/to/App.ipa <bundle-id>
#   CLEAN=1 UDID=<udid> ./scripts/sim.sh        # wipe the container first
#
# No device, no signing, no repacking. Re-run after every code change.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

UDID="${UDID:-booted}"

INPUT="${1:-}"
if [[ -z "$INPUT" ]]; then
    INPUT="$(bb_default_ipa || true)"
fi
if [[ -z "$INPUT" ]]; then
    bb_die "no input app — pass one, or drop an .ipa in $(bb_drop_zone)"
fi
bb_require_file "$INPUT"

bb_require_cmd xcrun "install Xcode"
bb_require_arm64
bb_require_booted_simulator "$UDID"

STAGE="$BB_BUILD_DIR/sim"
rm -rf "$STAGE"
mkdir -p "$STAGE"

case "$INPUT" in
    *.ipa)
        bb_note "unpacking $(basename "$INPUT")"
        unzip -q "$INPUT" -d "$STAGE/unpacked"
        APP="$(find "$STAGE/unpacked" -maxdepth 2 -name '*.app' -print -quit)"
        [[ -n "$APP" ]] || bb_die "no .app found inside $INPUT"
        ;;
    *.app)
        APP="$INPUT"
        ;;
    *)
        bb_die "input must be an .ipa or an .app"
        ;;
esac

BUNDLE_ID="${2:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" 2>/dev/null || true)}"
[[ -n "$BUNDLE_ID" ]] || bb_die "could not read CFBundleIdentifier from $APP/Info.plist"

# Device IPAs will not install on the simulator: rewrite every Mach-O platform.
bb_note "patching platform for the simulator"
"$BB_ROOT/scripts/sim-patch.sh" "$APP"

bb_note "building simulator dylib"
SDK=iphonesimulator "$BB_ROOT/scripts/build.sh"

bb_note "injecting"
DYLIB="$BB_SIM_DYLIB" OUT="$STAGE/$(basename "$APP")" \
    "$BB_ROOT/scripts/inject.sh" "$APP"

bb_note "installing to $UDID"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
if [[ "${CLEAN:-0}" == "1" ]]; then
    bb_step "CLEAN=1: wiping the app container"
    xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi
xcrun simctl install "$UDID" "$STAGE/$(basename "$APP")"

bb_note "launching $BUNDLE_ID"
xcrun simctl launch "$UDID" "$BUNDLE_ID"

printf '\n'
bb_note "logs: ./scripts/sim-logs.sh (or -f to follow)"
