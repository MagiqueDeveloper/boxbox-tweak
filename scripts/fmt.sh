#!/usr/bin/env bash
#
# Applies clang-format (and shfmt, when installed) in place.
#
#   ./scripts/fmt.sh
#
# Style is defined by .clang-format; ./scripts/lint.sh is what CI runs.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

FORMAT="$(bb_clang_format || true)"
[[ -n "$FORMAT" ]] || bb_die "clang-format not found (install LLVM, or use the copy in Xcode)"

count=0
while IFS= read -r file; do
    bb_step "${file#"$BB_ROOT"/}"
    "$FORMAT" -i "$file"
    count=$((count + 1))
done < <(bb_objc_sources)
bb_note "formatted $count Objective-C files"

if command -v shfmt >/dev/null 2>&1; then
    count=0
    while IFS= read -r file; do
        bb_step "${file#"$BB_ROOT"/}"
        shfmt -i 4 -ci -w "$file"
        count=$((count + 1))
    done < <(bb_shell_scripts)
    bb_note "formatted $count shell scripts"
else
    bb_skip "shfmt not installed — shell scripts left alone (brew install shfmt)"
fi
