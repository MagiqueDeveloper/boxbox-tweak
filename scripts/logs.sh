#!/usr/bin/env bash
#
# Tails the device console filtered to BoxBox (and optionally one process).
#
#   ./scripts/logs.sh
#   UDID=<device-udid> PROCESS=Foo ./scripts/logs.sh
#
set -euo pipefail

command -v idevicesyslog >/dev/null || {
    echo "idevicesyslog not found (brew install libimobiledevice)" >&2
    exit 1
}

UDID="${UDID:-}"
PROCESS="${PROCESS:-}"

FILTER='BoxBox'
[[ -n "$PROCESS" ]] && FILTER="$FILTER|$PROCESS"

printf '\033[1;34m==>\033[0m tailing device log for %s (ctrl-c to stop)\n' "$FILTER"

if [[ -n "$UDID" ]]; then
    exec idevicesyslog -u "$UDID" | grep -iE --line-buffered "$FILTER"
else
    exec idevicesyslog | grep -iE --line-buffered "$FILTER"
fi
