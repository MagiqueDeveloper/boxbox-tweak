#!/usr/bin/env bash
#
# Tails the device console, filtered to BoxBox (and optionally one process).
# A device has no `log stream`; idevicesyslog is the only way in.
#
#   ./scripts/logs.sh
#   UDID=<device-udid> PROCESS=BoxBoxClub ./scripts/logs.sh
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

bb_require_cmd idevicesyslog "brew install libimobiledevice"

UDID="${UDID:-}"
PROCESS="${PROCESS:-}"

FILTER='BoxBox'
[[ -n "$PROCESS" ]] && FILTER="$FILTER|$PROCESS"

bb_note "tailing device log for $FILTER (ctrl-c to stop)"

if [[ -n "$UDID" ]]; then
    exec idevicesyslog -u "$UDID" | grep -iE --line-buffered "$FILTER"
else
    exec idevicesyslog | grep -iE --line-buffered "$FILTER"
fi
