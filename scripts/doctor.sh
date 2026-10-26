#!/usr/bin/env bash
#
# Preflight: the host, the toolchain, the repository, and — when you name one —
# the input app you are about to tweak.
#
#   ./scripts/doctor.sh                     # environment only
#   ./scripts/doctor.sh vendor/App.ipa      # ...plus a look inside the input
#
# Run this first when something "does not work": it separates a missing tool from
# an already-injected input from a still-encrypted one. Exits non-zero when
# something the build/inject path needs is missing.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

FAILED=0
fail() {
    bb_fail "$*"
    FAILED=1
}

# ── Host ─────────────────────────────────────────────────────────────────────

printf '\n%sHost%s\n' "$_bb_blue" "$_bb_reset"
bb_info "$(sw_vers -productName) $(sw_vers -productVersion) ($(uname -m))"
if [[ "$(uname -m)" == "arm64" ]]; then
    bb_ok "Apple Silicon — the simulator loop is available"
else
    bb_skip "Intel host — ./scripts/sim.sh will refuse to run"
fi

if DEVELOPER_DIR="$(xcode-select -p 2>/dev/null)"; then
    bb_ok "xcode-select: $DEVELOPER_DIR"
else
    fail "no Xcode selected (sudo xcode-select -s /Applications/Xcode.app)"
fi
if command -v xcodebuild >/dev/null 2>&1; then
    bb_info "$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
fi

# ── Toolchain ────────────────────────────────────────────────────────────────
#
# required: the build/inject path cannot run without these.
# optional: only the install, log and lint paths use them.

printf '\n%sToolchain%s\n' "$_bb_blue" "$_bb_reset"

require_tool() { # command, install hint
    if command -v "$1" >/dev/null 2>&1; then
        bb_ok "$1"
    else
        fail "$1 missing — $2"
    fi
}

optional_tool() { # command, install hint
    if command -v "$1" >/dev/null 2>&1; then
        bb_ok "$1"
    else
        bb_skip "$1 missing — $2"
    fi
}

require_tool xcodebuild "install Xcode"
require_tool codesign "install Xcode"
require_tool install_name_tool "install Xcode"
require_tool vtool "install Xcode"
require_tool otool "install Xcode"
require_tool xcodegen "brew install xcodegen"
require_tool insert_dylib "brew install insert-dylib"

optional_tool ldid "brew install ldid"
optional_tool ideviceinstaller "brew install ideviceinstaller"
optional_tool ios-deploy "brew install ios-deploy"
optional_tool idevicesyslog "brew install libimobiledevice"
optional_tool shellcheck "brew install shellcheck"
if bb_clang_format >/dev/null; then
    bb_ok "clang-format ($(bb_clang_format))"
else
    bb_skip "clang-format missing — install LLVM (Xcode normally ships one)"
fi

# ── Repository ───────────────────────────────────────────────────────────────

printf '\n%sRepository%s\n' "$_bb_blue" "$_bb_reset"
bb_info "$BB_ROOT"
bb_info "version $(bb_version) (src/BBVersion.h)"

sources="$(bb_objc_sources | wc -l | tr -d ' ')"
bb_info "$sources Objective-C files in src/"

if [[ -f "$BB_DEVICE_DYLIB" ]]; then
    bb_ok "device dylib: build/BoxBox.dylib ($(du -h "$BB_DEVICE_DYLIB" | cut -f1))"
else
    bb_skip "device dylib not built yet — ./scripts/build.sh"
fi

if [[ -f "$BB_SIM_DYLIB" ]]; then
    bb_ok "simulator dylib: build/simulator/BoxBox.dylib"
else
    bb_skip "simulator dylib not built yet — SDK=iphonesimulator ./scripts/build.sh"
fi

if input="$(bb_default_ipa)"; then
    bb_ok "input app: ${input#"$BB_ROOT"/} ($(du -h "$input" | cut -f1))"
else
    bb_skip "no input app — drop a decrypted .ipa in $(bb_drop_zone)"
fi

if xcrun simctl list devices booted 2>/dev/null | grep -q Booted; then
    bb_ok "booted simulator: $(xcrun simctl list devices booted 2>/dev/null |
        sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1)"
else
    bb_skip "no booted simulator — open -a Simulator"
fi

# ── Input app ────────────────────────────────────────────────────────────────

if [[ $# -ge 1 ]]; then
    INPUT="$1"
    bb_require_file "$INPUT"

    printf '\n%sInput: %s%s\n' "$_bb_blue" "$(basename "$INPUT")" "$_bb_reset"

    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT

    case "$INPUT" in
        *.ipa)
            unzip -q "$INPUT" -d "$WORK/unpacked"
            APP="$(find "$WORK/unpacked" -maxdepth 2 -name '*.app' -print -quit)"
            [[ -n "$APP" ]] || bb_die "no .app found inside $INPUT"
            ;;
        *.app)
            APP="$INPUT"
            ;;
        *)
            bb_die "input must be an .ipa or an .app"
            ;;
    esac

    plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null || true; }
    bb_info "bundle id: $(plist_value CFBundleIdentifier)"
    bb_info "version:   $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion))"
    bb_info "platform:  $(plist_value DTPlatformName) $(plist_value MinimumOSVersion)+"

    extensions="$(find "$APP" \( -name '*.appex' \) -maxdepth 3 -type d 2>/dev/null | wc -l | tr -d ' ')"
    bb_info "extensions: $extensions"

    # `cryptid 0` means decrypted. Anything else and static recon is worthless
    # because __TEXT is still scrambled.
    encrypted=0
    checked=0
    already_injected=""
    while IFS= read -r binary; do
        header="$(xxd -l 4 -p "$binary" 2>/dev/null || true)"
        case "$header" in
            cffaedfe | cefaedfe | feedfacf | feedface | cafebabe | bebafeca) ;;
            *) continue ;;
        esac
        checked=$((checked + 1))

        cryptid="$(otool -l "$binary" 2>/dev/null |
            awk '/LC_ENCRYPTION_INFO/ { seen = 1 } seen && /cryptid/ { print $2; exit }')"
        if [[ -n "$cryptid" && "$cryptid" != "0" ]]; then
            encrypted=$((encrypted + 1))
            bb_warn "${binary#"$APP"/} is still FairPlay-encrypted (cryptid $cryptid)"
        fi

        third_party="$(otool -L "$binary" 2>/dev/null |
            awk '/^\t/ { print $1 }' |
            grep -E '^@executable_path/' || true)"
        if [[ -n "$third_party" ]]; then
            already_injected="$already_injected
$third_party"
        fi
    done < <(find "$APP" -type f)

    if [[ "$encrypted" -eq 0 ]]; then
        bb_ok "decrypted: $checked Mach-O checked, cryptid 0 on all"
    else
        fail "$encrypted of $checked Mach-O are still encrypted — decrypt before recon"
    fi

    if [[ -n "$already_injected" ]]; then
        bb_skip "already carries a third-party dylib:"
        printf '%s\n' "$already_injected" | sed '/^$/d' | sort -u | sed 's/^/      /'
    else
        bb_ok "no third-party dylib loaded yet"
    fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────────

printf '\n'
if [[ "$FAILED" -eq 0 ]]; then
    bb_note "OK — nothing blocking"
else
    bb_note "problems found above"
fi
exit "$FAILED"
