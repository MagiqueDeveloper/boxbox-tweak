#!/usr/bin/env bash
#
# Shows recent BoxBox log lines from a booted simulator, or follows them.
#
#   ./scripts/sim-logs.sh            # last 2 minutes
#   ./scripts/sim-logs.sh -f         # follow (ctrl-c to stop)
#   LAST=30s ./scripts/sim-logs.sh   # a different window
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

UDID="${UDID:-booted}"
PREDICATE='eventMessage CONTAINS "[BoxBox]"'

if [[ "${1:-}" == "-f" || "${1:-}" == "--follow" ]]; then
    exec xcrun simctl spawn "$UDID" log stream --style compact --predicate "$PREDICATE"
fi

exec xcrun simctl spawn "$UDID" log show \
    --last "${LAST:-2m}" --style compact --predicate "$PREDICATE"
