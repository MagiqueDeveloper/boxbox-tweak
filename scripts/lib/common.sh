#!/usr/bin/env bash
#
# Shared helpers for the BoxBox scripts. This file is *sourced*, never run:
#
#     source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# It provides the repository root and artifact paths, consistent logging, the
# version, and the preflight checks every script needs.
#
# Targets bash 3.2 (the version macOS ships): no associative arrays, no `mapfile`.
# Every script is expected to pass `shellcheck -x`.

# shellcheck shell=bash

# Guard against being sourced twice by the same shell.
if [[ -n "${BB_COMMON_SOURCED:-}" ]]; then
    return 0
fi
BB_COMMON_SOURCED=1

# ── Paths ────────────────────────────────────────────────────────────────────

# Repository root, resolved from this file's location so every script works from
# any working directory.
BB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly BB_ROOT

readonly BB_BUILD_DIR="$BB_ROOT/build"
# The artifact paths below are consumed by the scripts that source this file, so
# they read as unused when this file is analysed on its own.
# shellcheck disable=SC2034
readonly BB_DEVICE_DYLIB="$BB_BUILD_DIR/BoxBox.dylib"
# shellcheck disable=SC2034
readonly BB_SIM_DYLIB="$BB_BUILD_DIR/simulator/BoxBox.dylib"
# shellcheck disable=SC2034
readonly BB_INJECTED_DIR="$BB_BUILD_DIR/injected"

# The path baked into the injected LC_LOAD_DYLIB. Must match LD_DYLIB_INSTALL_NAME
# in project.yml and the copy inject.sh makes inside the app bundle.
# shellcheck disable=SC2034
readonly BB_INSTALL_NAME="@executable_path/Frameworks/BoxBox.dylib"

# ── Logging ──────────────────────────────────────────────────────────────────

# Colour only on a terminal, so redirected and CI logs stay plain.
if [[ -t 1 ]]; then
    _bb_blue=$'\033[1;34m'
    _bb_green=$'\033[1;32m'
    _bb_yellow=$'\033[1;33m'
    _bb_red=$'\033[1;31m'
    _bb_reset=$'\033[0m'
else
    _bb_blue=''
    _bb_green=''
    _bb_yellow=''
    _bb_red=''
    _bb_reset=''
fi

# bb_ok "..."   -> "  ✓ ..."   a check that passed
# bb_fail "..." -> "  ✗ ..."   a check that failed
# bb_skip "..." -> "  · ..."   a check that did not run
# bb_info "..." -> "  · ..."   a fact worth printing
bb_ok() { printf '  %s✓%s %s\n' "$_bb_green" "$_bb_reset" "$*"; }
bb_fail() { printf '  %s✗%s %s\n' "$_bb_red" "$_bb_reset" "$*"; }
bb_skip() { printf '  %s·%s %s\n' "$_bb_yellow" "$_bb_reset" "$*"; }
bb_info() { printf '  %s·%s %s\n' "$_bb_blue" "$_bb_reset" "$*"; }

# bb_note "..."  -> "==> ..."     a step the user should see
# bb_step "..."  -> "    ..."     detail belonging to the current step
# bb_warn "..."  -> "warn: ..."   stderr, does not stop the script
# bb_die  "..."  -> "error: ..."  stderr, exits 1
bb_note() { printf '%s==>%s %s\n' "$_bb_blue" "$_bb_reset" "$*"; }
bb_step() { printf '    %s\n' "$*"; }
bb_warn() { printf '%swarn:%s %s\n' "$_bb_yellow" "$_bb_reset" "$*" >&2; }
bb_die() {
    printf '%serror:%s %s\n' "$_bb_red" "$_bb_reset" "$*" >&2
    exit 1
}

# ── Version ──────────────────────────────────────────────────────────────────

# Prints the tweak version. src/BBVersion.h is the single source of truth — the
# release workflow compares the git tag against it.
bb_version() {
    local version
    version="$(sed -n 's/.*BB_VERSION_STRING[[:space:]]*@"\([^"]*\)".*/\1/p' \
        "$BB_ROOT/src/BBVersion.h" | head -1)"
    [[ -n "$version" ]] || bb_die "no BB_VERSION_STRING found in src/BBVersion.h"
    printf '%s' "$version"
}

# ── Preflight ────────────────────────────────────────────────────────────────

# bb_require_cmd <command> [install hint]
bb_require_cmd() {
    local cmd="$1" hint="${2:-}"
    command -v "$cmd" >/dev/null 2>&1 || bb_die "$cmd not found${hint:+ ($hint)}"
}

# bb_require_file <path> [hint]
bb_require_file() {
    local path="$1" hint="${2:-}"
    [[ -e "$path" ]] || bb_die "no such file: $path${hint:+ — $hint}"
}

# The toolchain the device-side scripts need.
bb_require_xcode() {
    bb_require_cmd xcodebuild "install Xcode"
    bb_require_cmd codesign "install Xcode"
}

# The simulator loop only works on Apple Silicon: the CPU matches iOS, so the
# only mismatch left is the platform load command.
bb_require_arm64() {
    [[ "$(uname -m)" == "arm64" ]] || bb_die "this step needs an Apple Silicon host"
}

# bb_require_booted_simulator [udid]
bb_require_booted_simulator() {
    local udid="${1:-booted}"
    if [[ "$udid" == "booted" ]]; then
        xcrun simctl list devices booted 2>/dev/null | grep -q Booted \
            || bb_die "no booted simulator (open -a Simulator, or pass UDID=<udid>)"
    fi
}

# ── Inputs ───────────────────────────────────────────────────────────────────

# The IPA to operate on when none is named on the command line: $APP, else the
# first .ipa in vendor/, else the first in the repository root. Prints nothing
# and returns 1 when there is none.
bb_default_ipa() {
    local candidate
    if [[ -n "${APP:-}" ]]; then
        printf '%s' "$APP"
        return 0
    fi
    for candidate in "$BB_ROOT/vendor"/*.ipa "$BB_ROOT"/*.ipa; do
        [[ -f "$candidate" ]] || continue
        printf '%s' "$candidate"
        return 0
    done
    return 1
}

# bb_drop_zone — where the decrypted input IPA belongs. Creates it if needed.
bb_drop_zone() {
    mkdir -p "$BB_ROOT/vendor"
    printf '%s' "$BB_ROOT/vendor"
}

# ── Source discovery ─────────────────────────────────────────────────────────

# Every shell script in the repository, one per line. Excludes build output and
# the generated Xcode project.
bb_shell_scripts() {
    find "$BB_ROOT" \
        \( -name build -o -name .git -o -name .opencode -o -name BoxBox.xcodeproj \) -prune -o \
        -name '*.sh' -type f -print | sort
}

# Every Objective-C source in src/, one per line.
bb_objc_sources() {
    find "$BB_ROOT/src" -type f \( -name '*.h' -o -name '*.m' \) | sort
}

# ── Toolchain ────────────────────────────────────────────────────────────────

# Prints the path to clang-format: PATH first, then the copy Xcode ships.
# Returns 1 when neither exists.
bb_clang_format() {
    local from_path from_xcode
    if from_path="$(command -v clang-format 2>/dev/null)" && [[ -n "$from_path" ]]; then
        printf '%s' "$from_path"
        return 0
    fi

    from_xcode="$(xcrun --find clang-format 2>/dev/null || true)"
    if [[ -n "$from_xcode" && -x "$from_xcode" ]]; then
        printf '%s' "$from_xcode"
        return 0
    fi

    return 1
}
