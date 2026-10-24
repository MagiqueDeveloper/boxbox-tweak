#!/usr/bin/env bash
#
# Installs an injected .ipa/.app onto a connected device.
#
#   ./scripts/install.sh Foo-injected.ipa
#   UDID=<device-udid> ./scripts/install.sh Foo-injected.ipa
#
# If neither ideviceinstaller nor ios-deploy is available, prints the
# copy-the-file-to-the-phone alternatives (TrollStore / Sideloadly).
#
set -euo pipefail

note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

fallback() {
    cat >&2 <<EOF
Neither ideviceinstaller nor ios-deploy is installed.

  brew install ideviceinstaller     # IPA over usbmuxd
  brew install ios-deploy           # .app over usbmuxd

Or do it by hand:
  - TrollStore: open the file in Files / AirDrop it, then "Install".
  - Sideloadly: drop $1 in, sign with your Apple ID, install.
EOF
    exit 1
}

[[ $# -eq 1 ]] || die "usage: $(basename "$0") <path/to/App.ipa|App.app>"
TARGET="$1"
[[ -e "$TARGET" ]] || die "no such file: $TARGET"

UDID="${UDID:-}"

case "$TARGET" in
    *.ipa)
        if command -v ideviceinstaller >/dev/null; then
            note "installing via ideviceinstaller"
            if [[ -n "$UDID" ]]; then
                ideviceinstaller -u "$UDID" -i "$TARGET"
            else
                ideviceinstaller -i "$TARGET"
            fi
        elif command -v ios-deploy >/dev/null; then
            note "ideviceinstaller missing; unpacking and using ios-deploy"
            WORK="$(mktemp -d)"
            trap 'rm -rf "$WORK"' EXIT
            unzip -q "$TARGET" -d "$WORK"
            APP="$(find "$WORK" -maxdepth 2 -name '*.app' -print -quit)"
            [[ -n "$APP" ]] || die "no .app inside $TARGET"
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
        if command -v ios-deploy >/dev/null; then
            note "installing via ios-deploy"
            if [[ -n "$UDID" ]]; then
                ios-deploy --bundle "$TARGET" --id "$UDID" --no-wifi
            else
                ios-deploy --bundle "$TARGET" --no-wifi
            fi
        else
            fallback "$TARGET"
        fi
        ;;
    *)
        die "path must be an .ipa or .app"
        ;;
esac

note "installed"
