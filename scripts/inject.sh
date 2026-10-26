#!/usr/bin/env bash
#
# Injects BoxBox.dylib into an .ipa or .app and re-signs the result ad-hoc, so it
# installs on a TrollStore / sideloaded / jailbroken device.
#
#   ./scripts/inject.sh App.ipa     -> App-injected.ipa
#   ./scripts/inject.sh App.app     -> build/injected/App.app
#
# env:
#   DYLIB    dylib to inject    (default: build/BoxBox.dylib)
#   SIGN_ID  codesign identity  (default: - for ad-hoc)
#   OUT      output path        (default: <input>-injected.ipa)
#
# The input is never modified: an .ipa is unpacked into a scratch directory and
# an .app is copied into one, so a bad build can always be re-injected from a
# pristine source.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DYLIB="${DYLIB:-$BB_DEVICE_DYLIB}"
SIGN_ID="${SIGN_ID:--}"

usage() {
    cat <<EOF
usage: $(basename "$0") <App.ipa | App.app>

env:
  DYLIB    dylib to inject (default: build/BoxBox.dylib)
  SIGN_ID  codesign identity (default: - for ad-hoc)
  OUT      output path (default: <input>-injected.ipa, or build/injected/<App>.app)

Build the dylib first with ./scripts/build.sh
EOF
}

[[ $# -eq 1 ]] || {
    usage >&2
    exit 1
}

INPUT="$1"
bb_require_file "$INPUT"
bb_require_file "$DYLIB" "run ./scripts/build.sh first"
bb_require_cmd insert_dylib "brew install insert-dylib"
bb_require_cmd codesign "install Xcode"
bb_require_cmd otool "install Xcode"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Stage the input ──────────────────────────────────────────────────────────

REPACK=0
case "$INPUT" in
    *.ipa)
        REPACK=1
        bb_note "unpacking $(basename "$INPUT")"
        unzip -q "$INPUT" -d "$WORK/unpacked"
        APP="$(find "$WORK/unpacked" -maxdepth 2 -name '*.app' -print -quit)"
        [[ -n "$APP" ]] || bb_die "no .app found inside $INPUT"
        ;;
    *.app)
        bb_note "staging $(basename "$INPUT")"
        APP="$WORK/$(basename "$INPUT")"
        cp -R "$INPUT" "$APP"
        ;;
    *)
        bb_die "input must be an .ipa or an .app"
        ;;
esac

BINARY_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
[[ -n "$BINARY_NAME" ]] || bb_die "could not read CFBundleExecutable from $APP/Info.plist"
BINARY="$APP/$BINARY_NAME"
bb_require_file "$BINARY"

bb_note "target: $BINARY"

# Entitlements must be read *before* insert_dylib --strip-codesig destroys the
# signature: a dropped application-groups entitlement silently breaks data
# sharing between the host and its extensions.
HOST_ENTITLEMENTS="$WORK/host-entitlements.plist"
if codesign -d --entitlements :- "$BINARY" >"$HOST_ENTITLEMENTS" 2>/dev/null &&
    [[ -s "$HOST_ENTITLEMENTS" ]]; then
    bb_step "captured host entitlements"
else
    rm -f "$HOST_ENTITLEMENTS"
    bb_warn "no entitlements on the host binary"
fi

bb_note "copying $(basename "$DYLIB") into Frameworks/"
mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/$(basename "$DYLIB")"

# ── Insert the load command ──────────────────────────────────────────────────

# An already-injected input (a pre-tweaked IPA, or a re-run over a staged copy)
# must not get a second load command: dyld aborts at launch with
# `duplicate linked dylib`.
already_linked() {
    otool -l "$1" 2>/dev/null |
        awk '/LC_LOAD_DYLIB|LC_LOAD_WEAK_DYLIB/ { found = 1; next }
             found && /name / { print $2; found = 0 }' |
        grep -qxF "$2"
}

link_dylib() { # binary, install name
    if already_linked "$1" "$2"; then
        bb_step "already links $2"
        return 0
    fi
    insert_dylib --inplace --strip-codesig --all-yes "$2" "$1" >/dev/null
}

bb_note "inserting LC_LOAD_DYLIB -> $BB_INSTALL_NAME"
link_dylib "$BINARY" "$BB_INSTALL_NAME"

# Embedded extensions (.appex) run in their own process and are not covered by
# host hooks, so they need the load command too — otherwise anything that gates
# on shared state (widgets, intents, the notification service) stays locked.
INSTALL_REL="${BB_INSTALL_NAME#@executable_path/}"
EXT_ENTITLEMENTS_DIR="$WORK/extension-entitlements"
mkdir -p "$EXT_ENTITLEMENTS_DIR"

for APPEX in "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex; do
    [[ -d "$APPEX" ]] || continue

    EXT_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APPEX/Info.plist" 2>/dev/null || true)"
    [[ -n "$EXT_NAME" ]] || continue
    EXT_BINARY="$APPEX/$EXT_NAME"
    [[ -f "$EXT_BINARY" ]] || continue

    # Walk back out of the .appex to the Frameworks/ directory filled above. The
    # depth varies per bundle, so count path components rather than hardcoding.
    EXT_REL="${APPEX#"$APP"/}"
    UPDIRS=""
    for _ in $(seq 1 "$(printf '%s' "$EXT_REL" | awk -F/ '{ print NF }')"); do
        UPDIRS="../$UPDIRS"
    done
    EXT_INSTALL_NAME="@executable_path/$UPDIRS$INSTALL_REL"

    # Read entitlements before --strip-codesig throws the signature away.
    EXT_ENTITLEMENTS="$EXT_ENTITLEMENTS_DIR/${EXT_REL//\//_}.plist"
    codesign -d --entitlements :- "$EXT_BINARY" >"$EXT_ENTITLEMENTS" 2>/dev/null ||
        rm -f "$EXT_ENTITLEMENTS"

    bb_step "extension $(basename "$APPEX") -> $EXT_INSTALL_NAME"
    link_dylib "$EXT_BINARY" "$EXT_INSTALL_NAME"
done

# ── Sign, innermost out ──────────────────────────────────────────────────────

bb_note "re-signing (identity: $SIGN_ID)"
# Nested code first, bundle seal last: touching a nested binary after the parent
# has been sealed invalidates its resource seal, and the extension then dies at
# launch with OS_REASON_CODESIGNING.
codesign --force --sign "$SIGN_ID" "$APP/Frameworks/$(basename "$DYLIB")"
codesign --force --deep --sign "$SIGN_ID" "$APP"

# --deep discards nested entitlements, so put the extensions' back...
for APPEX in "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex; do
    [[ -d "$APPEX" ]] || continue
    EXT_REL="${APPEX#"$APP"/}"
    EXT_ENTITLEMENTS="$EXT_ENTITLEMENTS_DIR/${EXT_REL//\//_}.plist"
    if [[ -s "$EXT_ENTITLEMENTS" ]]; then
        codesign --force --sign "$SIGN_ID" --entitlements "$EXT_ENTITLEMENTS" "$APPEX"
    else
        codesign --force --sign "$SIGN_ID" "$APPEX"
    fi
done

# ...then re-seal the bundle last; --entitlements here lands on the host binary.
if [[ -s "$HOST_ENTITLEMENTS" ]]; then
    codesign --force --sign "$SIGN_ID" --entitlements "$HOST_ENTITLEMENTS" "$APP"
else
    codesign --force --sign "$SIGN_ID" "$APP"
fi

# ── Verify ───────────────────────────────────────────────────────────────────

# `--deep` on the parent is not proof: it can verify clean while a nested binary
# is invalid. Check the host and every extension individually.
bb_note "verifying signatures"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'
for APPEX in "$APP"/PlugIns/*.appex "$APP"/Extensions/*.appex; do
    [[ -d "$APPEX" ]] || continue
    bb_step "$(basename "$APPEX")"
    codesign --verify --verbose=1 "$APPEX" 2>&1 | sed 's/^/    /'
done

# ── Emit the output ──────────────────────────────────────────────────────────

if [[ "$REPACK" == "1" ]]; then
    OUT="${OUT:-${INPUT%.ipa}-injected.ipa}"
    mkdir -p "$(dirname "$OUT")"
    # Resolve to an absolute path first: the `cd` into the repack directory below
    # would otherwise write the archive into the scratch tree, which the EXIT
    # trap deletes.
    OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

    bb_note "repacking -> $OUT"
    mkdir -p "$WORK/repack/Payload"
    mv "$APP" "$WORK/repack/Payload/"
    (cd "$WORK/repack" && zip -qry "$OUT" Payload)
    zip -T "$OUT" >/dev/null || bb_die "archive integrity check failed: $OUT"
else
    OUT="${OUT:-$BB_INJECTED_DIR/$(basename "$APP")}"
    bb_note "staging -> $OUT"
    rm -rf "$OUT"
    mkdir -p "$(dirname "$OUT")"
    cp -R "$APP" "$OUT"
fi

printf '\n'
bb_note "done: $OUT"
bb_note "install with: ./scripts/install.sh \"$OUT\""
