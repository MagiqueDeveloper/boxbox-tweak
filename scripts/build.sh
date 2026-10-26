#!/usr/bin/env bash
#
# Builds BoxBox.dylib, sets its install name, and ad-hoc signs it.
#
#   ./scripts/build.sh                        # device (iphoneos), Release
#   SDK=iphonesimulator ./scripts/build.sh    # simulator, for ./scripts/sim.sh
#   CONFIG=Debug ./scripts/build.sh           # Debug
#
# Output: build/BoxBox.dylib, or build/simulator/BoxBox.dylib for the simulator.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

CONFIG="${CONFIG:-Release}"
SDK="${SDK:-iphoneos}"

case "$SDK" in
    iphoneos) OUT="$BB_BUILD_DIR" ;;
    iphonesimulator) OUT="$BB_BUILD_DIR/simulator" ;;
    *) bb_die "unsupported SDK: $SDK (expected iphoneos or iphonesimulator)" ;;
esac

bb_require_xcode
bb_require_cmd xcodegen "brew install xcodegen"
bb_require_cmd install_name_tool "install Xcode"

# The .xcodeproj is generated, never committed, and its file list is only correct
# for the sources that existed when it was written — so regenerate on every build
# rather than only when the project happens to be missing.
bb_note "generating BoxBox.xcodeproj"
xcodegen generate --spec "$BB_ROOT/project.yml" --project "$BB_ROOT" >/dev/null

bb_note "building BoxBox $(bb_version) ($CONFIG, $SDK/arm64)"
mkdir -p "$OUT"
LOG="$OUT/xcodebuild.log"

if ! xcodebuild \
    -project "$BB_ROOT/BoxBox.xcodeproj" \
    -target BoxBox \
    -configuration "$CONFIG" \
    -sdk "$SDK" \
    SDKROOT="$SDK" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    SYMROOT="$OUT" \
    build >"$LOG" 2>&1; then
    grep -E 'error:|warning:' "$LOG" | head -40 || true
    bb_die "build failed — full log: $LOG"
fi

# Warnings are errors in project.yml, so this normally prints nothing.
grep -E 'warning:' "$LOG" || true

BUILT="$OUT/$CONFIG-$SDK/BoxBox.dylib"
if [[ ! -f "$BUILT" ]]; then
    BUILT="$(find "$OUT" -name BoxBox.dylib -type f -print -quit)"
fi
[[ -f "$BUILT" ]] || bb_die "expected product not found under $OUT"

if [[ "$SDK" == "iphonesimulator" ]]; then
    vtool -show-build "$BUILT" | grep -qi iossimulator \
        || bb_die "$BUILT is not a simulator binary"
fi

bb_note "setting install name -> $BB_INSTALL_NAME"
install_name_tool -id "$BB_INSTALL_NAME" "$BUILT"

bb_note "ad-hoc signing"
codesign --force --sign - "$BUILT"

cp "$BUILT" "$OUT/BoxBox.dylib"

printf '\n'
bb_note "done: $OUT/BoxBox.dylib"
otool -D "$OUT/BoxBox.dylib" | tail -1
