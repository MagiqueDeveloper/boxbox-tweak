#!/usr/bin/env bash
#
# Rewrites an iOS *device* .app so the iOS Simulator will accept it.
#
# A stock App Store IPA is built for platform `iOS`; the Simulator only runs
# `iOS-simulator` code. On an Apple Silicon host the CPU already matches, so the
# only real mismatch is the LC_BUILD_VERSION platform — rewrite it on every
# Mach-O (host, extensions, frameworks) and ad-hoc sign innermost-first.
#
#   ./scripts/sim-patch.sh /path/to/App.app
#   MINOS=17.0 ./scripts/sim-patch.sh /path/to/App.app   # force a deployment floor
#
# The input .app is modified in place, so stage a copy first. ./scripts/sim.sh
# does that for you.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

APP="${1:-}"
[[ -n "$APP" && -d "$APP" ]] || bb_die "usage: $(basename "$0") <App.app>"
bb_require_cmd vtool "xcode-select --install"
bb_require_cmd codesign "install Xcode"
bb_require_arm64

MINOS="${MINOS:-}"

is_macho() {
    local header
    header="$(xxd -l 4 -p "$1" 2>/dev/null || true)"
    case "$header" in
        cffaedfe | cefaedfe | feedfacf | feedface | cafebabe | bebafeca) return 0 ;;
        *) return 1 ;;
    esac
}

patched=0
skipped=0

while IFS= read -r binary; do
    is_macho "$binary" || continue

    relative="${binary#"$APP"/}"
    platform="$(vtool -show-build "$binary" 2>/dev/null | awk '/platform/ { print $2; exit }')"

    if [[ "$platform" == "IOSSIMULATOR" ]]; then
        skipped=$((skipped + 1))
        continue
    fi
    if [[ -n "$platform" && "$platform" != "IOS" ]]; then
        bb_step "skip $relative (platform $platform)"
        skipped=$((skipped + 1))
        continue
    fi

    minos="$MINOS"
    [[ -n "$minos" ]] || minos="$(vtool -show-build "$binary" 2>/dev/null | awk '/minos/ { print $2; exit }')"
    sdk="$(vtool -show-build "$binary" 2>/dev/null | awk '/sdk/ { print $2; exit }')"
    if [[ -z "$minos" || -z "$sdk" ]]; then
        bb_warn "no build version on $relative, skipping"
        continue
    fi

    vtool -set-build-version iossim "$minos" "$sdk" -replace \
        -output "$binary.tmp" "$binary" >/dev/null 2>&1
    mv -f "$binary.tmp" "$binary"
    codesign --force --sign - "$binary" >/dev/null 2>&1 ||
        bb_warn "codesign failed on $relative"

    # These also advertise the platform and vtool cannot rewrite them.
    if otool -l "$binary" 2>/dev/null | grep -q LC_VERSION_MIN_; then
        bb_warn "$relative has LC_VERSION_MIN_* (dyld may still read it as iOS)"
    fi
    if otool -l "$binary" 2>/dev/null | grep -q LC_ENCRYPTION_INFO; then
        bb_warn "$relative has LC_ENCRYPTION_INFO (expected if decrypted; cryptid should be 0)"
    fi

    patched=$((patched + 1))
done < <(find "$APP" -type f)

# Bundle seal last, once every nested Mach-O is final.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

bb_note "patched $patched mach-o ($skipped already ok)"
bb_note "install with: xcrun simctl install booted \"$APP\""
