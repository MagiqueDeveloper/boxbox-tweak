# BoxBox

An injectable iOS dylib for [Box Box Club](https://apps.apple.com/us/app/box-box-club-racing-companion/id1621241916).
It hooks a small number of well-chosen points in the host app at load time: it
reads the paid-tier flags the app persists, animates the tab switches the app
leaves unanimated, and closes the launch funnel's subscription cover before it is
ever composited.

No jailbreak. Works on iOS 15.0+ with TrollStore, Sideloadly, or any other
sideloading route that accepts an ad-hoc signed bundle.

[![CI](https://github.com/MagiqueDeveloper/boxbox-tweak/actions/workflows/ci.yml/badge.svg)](https://github.com/MagiqueDeveloper/boxbox-tweak/actions/workflows/ci.yml)

---

## Requirements

| | |
| --- | --- |
| Host | macOS with Xcode 14+ selected (`xcode-select -p`) |
| Target | iOS 15.0+, arm64 |
| Homebrew | `xcodegen`, `insert-dylib` |
| Optional | `ideviceinstaller` / `ios-deploy` (install), `libimobiledevice` (logs), `shellcheck` (lint) |

## Quick start

```sh
git clone https://github.com/MagiqueDeveloper/boxbox-tweak.git
cd boxbox-tweak

brew install xcodegen insert-dylib

# Drop a decrypted copy of the app in vendor/ — it is gitignored and never
# committed. See docs/RECON.md for where decrypted IPAs come from.
cp ~/Downloads/BoxBoxClub.ipa vendor/

make doctor     # verify the host, toolchain, repository and the input app
make sim        # fast loop: build, inject, install, launch in the Simulator
```

`make` on its own lists every target. The same commands are available directly
under `./scripts/`.

### On a device

```sh
make build                                       # -> build/BoxBox.dylib
make inject  APP=vendor/BoxBoxClub.ipa           # -> vendor/BoxBoxClub-injected.ipa
make install APP=vendor/BoxBoxClub-injected.ipa
make logs
```

The input IPA is never modified — injection works on a staged copy — and the
original entitlements are read before the signature is stripped, then re-applied
per component afterwards. The host *and* every embedded `.appex` get the load
command, because an extension runs in its own process and is not covered by host
hooks.

## Repository layout

```
src/                     the dylib
  BoxBox.m                 entry point: the dyld constructor and load order
  BoxBox.h                 umbrella header, module map
  BBLog.{h,m}              BBLog / BBLogOnce, tagged logging
  BBRuntime.{h,m}          swizzling, hooking and recon helpers
  BBPreferences.{h,m}      typed reads of the tweak's own tunables
  BBPremium.{h,m}          paid-tier unlock, shared-suite seeding
  BBTabTransitions.{h,m}   animated tab switches
  BBPaywall.{h,m}          launch-funnel subscription cover suppression
  BBVersion.h              version constant — the single source of truth
scripts/                 build, inject, sign, install, run, lint
  lib/common.sh            shared helpers; every script sources it
docs/                    architecture, build guide, recon notes
```

## Commands

| Command | What it does |
| --- | --- |
| `make doctor` | Check host, toolchain, repository, and — given `APP=` — the input app's `cryptid` and existing load commands |
| `make build` | Build, set the install name, ad-hoc sign → `build/BoxBox.dylib` |
| `make sim` | Patch platform, build for the simulator, inject, install, launch |
| `make inject APP=…` | Inject into an `.ipa`/`.app` and re-sign → `<input>-injected.ipa` |
| `make install APP=…` | Push an injected bundle to a connected device |
| `make logs` | Tail the device console filtered to `BoxBox` |
| `make sim-logs` | Show, or follow with `-f`, BoxBox lines from the Simulator |
| `make lint` | The static checks CI runs: shell syntax, shellcheck, clang-format, version, repo hygiene |
| `make fmt` | Apply `clang-format` to `src/` |
| `make check` | `lint` then `build` |
| `make clean` | Remove build output and the generated `.xcodeproj` |

Variables: `APP`, `UDID`, `SDK` (`iphoneos`/`iphonesimulator`), `CONFIG`
(`Release`/`Debug`), `CLEAN=1`.

## Configuration

Every feature is steerable at runtime through the host app's defaults, so feel
can be tuned without a rebuild. The dylib runs inside the app, so the keys live
in the app's own domain — read the exact bundle identifier from
`make doctor APP=vendor/BoxBoxClub.ipa`.

| Key | Default | Values |
| --- | --- | --- |
| `BBTabTransitionEnabled` | `YES` | `YES` / `NO` |
| `BBTabTransitionDuration` | `0.30` | seconds |
| `BBTabTransitionStyle` | `fadeSlide` | `fadeSlide`, `fade`, `slide`, `none` |
| `BBPaywallEnabled` | `YES` | `YES` / `NO` |
| `BBPaywallMode` | `flash` | `flash` (present, hide, close), `skip` (never present) |

```sh
defaults write <host-bundle-id> BBTabTransitionStyle -string slide
defaults write <host-bundle-id> BBTabTransitionDuration -float 0.4
defaults write <host-bundle-id> BBPaywallEnabled -bool NO
```

## How it works

1. **Build** — `src/` compiles to `BoxBox.dylib` for arm64, ad-hoc signed, with
   its install name set to `@executable_path/Frameworks/BoxBox.dylib`.
2. **Inject** — that path is added as an `LC_LOAD_DYLIB` to the host binary and
   to every `.appex`, then the bundle is signed innermost-out with entitlements
   preserved.
3. **Load** — dyld maps the dylib before `main()`, the constructor installs the
   hooks, and the first log line proves the tweak is in-process:

   ```
   [BoxBox] loaded into BoxBoxClub (pid 1234, Version 18.0, BoxBox 1.0.0)
   ```

`docs/ARCHITECTURE.md` has the module map and the exact hook table.
`docs/RECON.md` documents how each hook point was located.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — modules, hooks, load order, failure modes
- [`docs/BUILDING.md`](docs/BUILDING.md) — prerequisites, every command, troubleshooting
- [`docs/RECON.md`](docs/RECON.md) — how the gates were found, and how to redo it
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — layout conventions, adding a feature
- [`CHANGELOG.md`](CHANGELOG.md) — release history

## Disclaimer

BoxBox is a community project and is **not affiliated with, endorsed by, or
supported by Box Box Club**. It ships no app code and no decrypted IPA — you
supply your own copy of the app. Use it on software you own, and support the
developers by buying the app and any subscription you actually want.

## License

MIT — see [`LICENSE`](LICENSE).
