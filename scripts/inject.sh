#!/usr/bin/env bash
#
# Injects build/BoxBox.dylib into an .ipa or .app, then re-signs the result
# ad-hoc so it installs on a jailbroken / TrollStore / sideloaded device.
#
#   ./scripts/inject.sh Foo.ipa              -> Foo-injected.ipa
#   ./scripts/inject.sh Foo.app              -> build/injected/Foo.app
#   DYLIB=build/BoxBox.dylib ./scripts/inject.sh Foo.ipa
#
# The original input is never modified.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DYLIB="${DYLIB:-$ROOT/build/BoxBox.dylib}"
INSTALL_NAME="@executable_path/Frameworks/BoxBox.dylib"
SIGN_ID="${SIGN_ID:--}"

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
usage: $(basename "$0") <path/to/App.ipa | path/to/App.app>

env:
  DYLIB      dylib to inject (default: build/BoxBox.dylib)
  SIGN_ID    codesign identity (default: - for ad-hoc)
  OUT        output path (default: <input>-injected.ipa or build/injected/App.app)

Build the dylib first with ./scripts/build.sh
EOF
}

[[ $# -eq 1 ]] || { usage; exit 1; }
INPUT="$1"
[[ -e "$INPUT" ]] || die "no such file: $INPUT"
[[ -f "$DYLIB" ]] || die "dylib not found: $DYLIB (run ./scripts/build.sh)"
command -v insert_dylib >/dev/null || die "insert_dylib not found (brew install insert-dylib)"
command -v codesign >/dev/null || die "codesign not found"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPACK=0
case "$INPUT" in
    *.ipa)
        REPACK=1
        note "unpacking $(basename "$INPUT")"
        unzip -q "$INPUT" -d "$WORK/unpacked"
        APP="$(find "$WORK/unpacked" -maxdepth 2 -name '*.app' -print -quit)"
        [[ -n "$APP" ]] || die "no .app found inside $INPUT"
        APP="$WORK/unpacked/${APP#"$WORK/unpacked/"}"
        ;;
    *.app)
        note "staging $(basename "$INPUT")"
        APP="$WORK/$(basename "$INPUT")"
        cp -R "$INPUT" "$APP"
        ;;
    *)
        die "input must be an .ipa or .app"
        ;;
esac

BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
[[ -n "$BINARY_NAME" ]] || die "could not read CFBundleExecutable from $APP/Info.plist"
BINARY="$APP/$BINARY_NAME"
[[ -f "$BINARY" ]] || die "executable not found: $BINARY"

note "target: $BINARY"

# Preserve the original entitlements; ad-hoc re-signing drops them otherwise,
# and several system frameworks refuse to load without them.
ENT="$WORK/entitlements.plist"
HAVE_ENT=0
if codesign -d --entitlements :- "$BINARY" >"$ENT" 2>/dev/null && [[ -s "$ENT" ]]; then
    HAVE_ENT=1
else
    warn "no entitlements read from target binary"
fi

cp -p "$BINARY" "$BINARY.bak"

note "copying dylib into Frameworks/"
mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/$(basename "$DYLIB")"

note "inserting LC_LOAD_DYLIB -> $INSTALL_NAME"
insert_dylib --inplace --strip-codesig --all-yes "$INSTALL_NAME" "$BINARY" >/dev/null

# Embedded extensions (.appex) run in their own process, so they need the load
# command too — otherwise hooks only apply to the host app and anything that
# gates on shared state (widgets, intents) stays locked.
INSTALL_REL="${INSTALL_NAME#@executable_path/}"
mkdir -p "$WORK/ents"
for APPEX in "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex; do
    [[ -d "$APPEX" ]] || continue
    EXT_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null || true)"
    [[ -n "$EXT_NAME" ]] || continue
    EXT_BIN="$APPEX/$EXT_NAME"
    [[ -f "$EXT_BIN" ]] || continue
    EXT_REL="${APPEX#"$APP"/}"

    # Walk back out of the .appex to the Frameworks/ dir we just populated.
    UPDIRS=""
    I=0
    while [[ "$I" -lt "$(printf '%s' "$EXT_REL" | awk -F/ '{print NF}')" ]]; do
        UPDIRS="../$UPDIRS"
        I=$((I + 1))
    done

    # Read entitlements before --strip-codesig throws the signature away.
    codesign -d --entitlements :- "$EXT_BIN" >"$WORK/ents/${EXT_REL//\//_}.plist" 2>/dev/null || true

    note "  extension $(basename "$APPEX") -> @executable_path/$UPDIRS$INSTALL_REL"
    insert_dylib --inplace --strip-codesig --all-yes "@executable_path/$UPDIRS$INSTALL_REL" "$EXT_BIN" >/dev/null
done

# When repacking an IPA the pristine input is already the backup, and an extra
# .bak inside the bundle would just get sealed into its CodeResources.
if [[ "$REPACK" == "1" ]]; then
    rm -f "$BINARY.bak"
fi

note "re-signing (ad-hoc)"
# Nested code first, bundle seal last: touching a nested binary after the parent
# has been sealed invalidates its resource seal, and the extension then dies at
# launch with OS_REASON_CODESIGNING.
codesign --force --sign "$SIGN_ID" "$APP/Frameworks/$(basename "$DYLIB")"
codesign --force --deep --sign "$SIGN_ID" "$APP"

# --deep throws nested entitlements away, so put the extensions' back...
for APPEX in "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex; do
    [[ -d "$APPEX" ]] || continue
    EXT_ENT="$WORK/ents/${APPEX#"$APP"/}.plist"
    EXT_ENT="${EXT_ENT//\//_}"
    if [[ -s "$EXT_ENT" ]]; then
        codesign --force --sign "$SIGN_ID" --entitlements "$EXT_ENT" "$APPEX"
    else
        codesign --force --sign "$SIGN_ID" "$APPEX"
    fi
done

# ...then re-seal the bundle last; --entitlements here lands on the host binary.
if [[ "$HAVE_ENT" == "1" ]]; then
    codesign --force --sign "$SIGN_ID" --entitlements "$ENT" "$APP"
else
    codesign --force --sign "$SIGN_ID" "$APP"
fi

note "verifying"
codesign --verify --deep --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

if [[ "$REPACK" == "1" ]]; then
    OUT="${OUT:-${INPUT%.ipa}-injected.ipa}"
    note "repacking -> $OUT"
    mkdir -p "$WORK/repack"
    mv "$APP" "$WORK/repack/Payload.tmp"
    mkdir -p "$WORK/repack/Payload"
    mv "$WORK/repack/Payload.tmp" "$WORK/repack/Payload/$(basename "$APP")"
    (cd "$WORK/repack" && zip -qry "$OUT" Payload)
else
    OUT_DIR="$ROOT/build/injected"
    mkdir -p "$OUT_DIR"
    OUT="${OUT:-$OUT_DIR/$(basename "$APP")}"
    rm -rf "$OUT"
    cp -R "$APP" "$OUT"
fi

printf '\n'
note "done: $OUT"
note "install with: ./scripts/install.sh \"$OUT\""
