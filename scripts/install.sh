#!/usr/bin/env bash
#
# Installs an injected .ipa or .app onto a connected device.
#
#   ./scripts/install.sh App-injected.ipa
#   UDID=<device-udid> ./scripts/install.sh App-injected.ipa
#
# When neither ideviceinstaller nor ios-deploy is available, prints the
# copy-the-file-to-the-phone alternatives (TrollStore / Sideloadly) and exits.
#
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

fallback() {
    cat >&2 <<EOF
Neither ideviceinstaller nor ios-deploy is installed.

  brew install ideviceinstaller     # IPA over usbmuxd
  brew install ios-deploy           # .app over usbmuxd

Or do it by hand:
  - TrollStore: open the file in Files, or AirDrop it, then "Install".
  - Sideloadly: drop $1 in, sign with your Apple ID, install.
EOF
    exit 1
}

[[ $# -eq 1 ]] || bb_die "usage: $(basename "$0") <App.ipa | App.app>"
TARGET="$1"
bb_require_file "$TARGET"

# The device UDID, not a simulator one: this path talks to real hardware.
UDID="${UDID:-}"

case "$TARGET" in
    *.ipa)
        if command -v ideviceinstaller >/dev/null 2>&1; then
            bb_note "installing via ideviceinstaller"
            if [[ -n "$UDID" ]]; then
                ideviceinstaller -u "$UDID" -i "$TARGET"
            else
                ideviceinstaller -i "$TARGET"
            fi
        elif command -v ios-deploy >/dev/null 2>&1; then
            bb_note "ideviceinstaller missing; unpacking and using ios-deploy"
            WORK="$(mktemp -d)"
            trap 'rm -rf "$WORK"' EXIT
            unzip -q "$TARGET" -d "$WORK"
            APP="$(find "$WORK" -maxdepth 2 -name '*.app' -print -quit)"
            [[ -n "$APP" ]] || bb_die "no .app inside $TARGET"
            if [[ -n "$UDID" ]]; then
                ios-deploy --bundle "$APP" --id "$UDID" --no-wifi
            else
                ios-deploy --bundle "$APP" --no-wifi
            fi
        else
            fallback "$TARGET"
        fi
        ;;
    *.app)
        command -v ios-deploy >/dev/null 2>&1 || fallback "$TARGET"
        bb_note "installing via ios-deploy"
        if [[ -n "$UDID" ]]; then
            ios-deploy --bundle "$TARGET" --id "$UDID" --no-wifi
        else
            ios-deploy --bundle "$TARGET" --no-wifi
        fi
        ;;
    *)
        bb_die "path must be an .ipa or an .app"
        ;;
esac

bb_note "installed"
