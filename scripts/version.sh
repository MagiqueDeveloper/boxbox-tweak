#!/usr/bin/env bash
#
# Prints the tweak version. src/BBVersion.h is the single source of truth; the
# release workflow compares the git tag against this value.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

printf '%s\n' "$(bb_version)"
