#!/usr/bin/env bash
#
# Builds the BoxBox dylib for arm64 iOS, ad-hoc signs it and drops a copy at
# build/BoxBox.dylib ready for scripts/inject.sh.
#
#   ./scripts/build.sh                 # Release
#   CONFIG=Debug ./scripts/build.sh    # Debug
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-Release}"
OUT="$ROOT/build"
INSTALL_NAME="@executable_path/Frameworks/BoxBox.dylib"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"
command -v codesign   >/dev/null || die "codesign not found"

if [[ ! -d "$ROOT/BoxBox.xcodeproj" ]]; then
    command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
    note "generating BoxBox.xcodeproj"
    xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT"
fi

note "building BoxBox ($CONFIG, iphoneos/arm64)"
mkdir -p "$OUT"
xcodebuild \
    -project "$ROOT/BoxBox.xcodeproj" \
    -target BoxBox \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    SYMROOT="$OUT" \
    build \
    | sed -n '/error:/p; /warning:/p; /^\*\* /p'

BUILT="$OUT/$CONFIG-iphoneos/BoxBox.dylib"
[[ -f "$BUILT" ]] || die "expected product not found: $BUILT"

note "setting install_name -> $INSTALL_NAME"
install_name_tool -id "$INSTALL_NAME" "$BUILT"

note "ad-hoc signing"
codesign --force --sign - "$BUILT"

cp "$BUILT" "$OUT/BoxBox.dylib"

printf '\n'
note "done: $OUT/BoxBox.dylib"
otool -D "$OUT/BoxBox.dylib" | tail -1
