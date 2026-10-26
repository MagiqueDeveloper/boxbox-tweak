#!/usr/bin/env bash
#
# Static checks. CI runs exactly this, so a green run here means a green run
# there.
#
#   ./scripts/lint.sh                 # every check
#   TAG=v1.0.0 ./scripts/lint.sh      # also assert the tag matches BBVersion.h
#
# Exits non-zero when any check fails.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

FAILURES=0
section() { printf '\n%s==>%s %s\n' "$_bb_blue" "$_bb_reset" "$*"; }
pass() { printf '    %s✓%s %s\n' "$_bb_green" "$_bb_reset" "$*"; }
fail() {
    printf '    %s✗%s %s\n' "$_bb_red" "$_bb_reset" "$*"
    FAILURES=$((FAILURES + 1))
}
skip() { printf '    %s·%s %s\n' "$_bb_yellow" "$_bb_reset" "$*"; }

# ── Shell syntax ─────────────────────────────────────────────────────────────

section "shell syntax"
syntax_failures=0
while IFS= read -r script; do
    if ! bash -n "$script" 2>/dev/null; then
        fail "bash -n ${script#"$BB_ROOT"/}"
        syntax_failures=$((syntax_failures + 1))
    fi
done < <(bb_shell_scripts)
if [[ "$syntax_failures" -eq 0 ]]; then
    pass "every script parses"
fi

# ── ShellCheck ───────────────────────────────────────────────────────────────

section "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck_failures=0
    while IFS= read -r script; do
        # -x follows sources; -P resolves the `source=lib/common.sh` directive
        # regardless of the caller's working directory.
        if ! shellcheck -x -P "$BB_ROOT/scripts" -S style "$script"; then
            fail "shellcheck ${script#"$BB_ROOT"/}"
            shellcheck_failures=$((shellcheck_failures + 1))
        fi
    done < <(bb_shell_scripts)
    if [[ "$shellcheck_failures" -eq 0 ]]; then
        pass "clean"
    fi
else
    skip "shellcheck not installed (brew install shellcheck)"
fi

# ── Objective-C formatting ───────────────────────────────────────────────────

section "clang-format"
FORMAT="$(bb_clang_format || true)"
if [[ -n "$FORMAT" ]]; then
    format_failures=0
    while IFS= read -r file; do
        if ! "$FORMAT" --dry-run --Werror "$file" >/dev/null 2>&1; then
            fail "needs formatting: ${file#"$BB_ROOT"/} (run ./scripts/fmt.sh)"
            format_failures=$((format_failures + 1))
        fi
    done < <(bb_objc_sources)
    if [[ "$format_failures" -eq 0 ]]; then
        pass "clean"
    fi
else
    skip "clang-format not installed"
fi

# ── Version agreement ────────────────────────────────────────────────────────

section "version"
VERSION="$(bb_version)"
pass "src/BBVersion.h says $VERSION"
if [[ -n "${TAG:-}" ]]; then
    if [[ "$TAG" == "v$VERSION" ]]; then
        pass "git tag $TAG matches"
    else
        fail "git tag $TAG does not match BB_VERSION_STRING ($VERSION)"
    fi
else
    skip "no TAG set — skipping the tag comparison"
fi

# ── Repository hygiene ───────────────────────────────────────────────────────

section "repository hygiene"
if git -C "$BB_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    tracked_artifacts="$(git -C "$BB_ROOT" ls-files |
        grep -E '(^|/)(\.DS_Store|build/)|\.(ipa|app|dylib|bak)$' || true)"
    if [[ -n "$tracked_artifacts" ]]; then
        fail "build artifacts are tracked:"
        printf '%s\n' "$tracked_artifacts" | sed 's/^/        /'
    else
        pass "no build artifacts tracked"
    fi

    # CRLF and trailing whitespace in files that must stay clean for diffing.
    PATHS=('*.sh' '*.m' '*.h' '*.yml' 'Makefile' '*.md')
    if git -C "$BB_ROOT" grep -Il $'\r' -- "${PATHS[@]}" >/dev/null 2>&1; then
        fail "CRLF line endings in:"
        git -C "$BB_ROOT" grep -Il $'\r' -- "${PATHS[@]}" | sed 's/^/        /'
    else
        pass "LF line endings"
    fi
    if git -C "$BB_ROOT" grep -Il ' $' -- "${PATHS[@]}" >/dev/null 2>&1; then
        fail "trailing whitespace in:"
        git -C "$BB_ROOT" grep -Il ' $' -- "${PATHS[@]}" | sed 's/^/        /'
    else
        pass "no trailing whitespace"
    fi
else
    skip "not a git repository"
fi

# ── Verdict ──────────────────────────────────────────────────────────────────

printf '\n'
if [[ "$FAILURES" -eq 0 ]]; then
    bb_note "lint passed"
    exit 0
fi
bb_note "$FAILURES check(s) failed"
exit 1
