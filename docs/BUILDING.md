# Building

Everything here is a wrapper around `./scripts/*.sh`; the Makefile adds nothing
except `make` and a target list. If a `make` target misbehaves, run the script it
calls directly — the output is identical.

## Prerequisites

```sh
brew install xcodegen insert-dylib
```

`xcodegen` generates `BoxBox.xcodeproj` from `project.yml`. The project is
generated, never committed, and `scripts/build.sh` regenerates it on **every**
build — that is what keeps a newly added source file from being silently left out
of the target.

Optional, needed only by some paths:

| Tool | Used by |
| --- | --- |
| `ideviceinstaller` | `make install` with an `.ipa` |
| `ios-deploy` | `make install` with an `.app`, and as the `.ipa` fallback |
| `libimobiledevice` (`idevicesyslog`) | `make logs` |
| `shellcheck` | `make lint` |
| `shfmt` | `make fmt` (shell) |

`make doctor` checks all of this and tells you what is missing.

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `APP` | first `*.ipa` in `vendor/`, else the repo root | input `.ipa` / `.app` |
| `UDID` | `booted` | simulator or device to target |
| `SDK` | `iphoneos` | `iphoneos` or `iphonesimulator` |
| `CONFIG` | `Release` | `Release` or `Debug` |
| `CLEAN` | `0` | `CLEAN=1` wipes the simulator container first |
| `DYLIB` | `build/BoxBox.dylib` | dylib `inject.sh` inserts |
| `SIGN_ID` | `-` (ad-hoc) | `codesign` identity |
| `OUT` | `<input>-injected.ipa` | output path |
| `MINOS` | taken from the binary | deployment floor forced by `sim-patch.sh` |
| `LAST` | `2m` | window for `sim-logs.sh` |
| `TAG` | unset | `lint.sh` asserts it equals `v$(BB_VERSION_STRING)` |

## The simulator loop

The fast path. No device, no signing, no repacking.

```sh
make sim
```

1. Unpacks the input into `build/sim/`.
2. `sim-patch.sh` rewrites `LC_BUILD_VERSION` to `iossimulator` on every Mach-O
   and ad-hoc signs innermost-first. A device build has the right CPU on an
   Apple Silicon host, so the platform load command is the only real mismatch.
3. Builds the dylib with `SDK=iphonesimulator`.
4. Injects and installs it, terminates any running copy, installs and launches.

Then read what it did:

```sh
make sim-logs          # last 2 minutes
make sim-logs -f       # follow
LAST=30s make sim-logs
```

Useful flags:

```sh
UDID=<udid> make sim   # pick a simulator explicitly
CLEAN=1 make sim       # uninstall first: an empty data container
make sim APP=build/sim/Foo.app   # skip the unpack step
```

**Resolve the UDID once and reuse it.** `booted` means "whichever simulator
happens to be up", and the device list routinely holds several instances of one
model name. When more than one is running, pick the booted entry explicitly:

```sh
xcrun simctl list devices booted
UDID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX make sim
```

`simctl install` over an existing bundle is an *upgrade* and keeps the data
container. Only `uninstall` — or `CLEAN=1` — resets it. If you are testing
defaults-driven behaviour, you almost always want `CLEAN=1`.

`simctl` has no tap command. Drive navigation with a deep link
(`xcrun simctl openurl <udid> <scheme>://…`) or walk the funnel yourself.

## The device path

```sh
make build                                        # build/BoxBox.dylib
make inject APP=vendor/BoxBoxClub.ipa             # vendor/BoxBoxClub-injected.ipa
make install APP=vendor/BoxBoxClub-injected.ipa
make logs
```

`make run APP=…` chains all three.

`inject.sh` in detail:

1. Unpacks the `.ipa` into a scratch directory (an `.app` is copied instead). The
   input is never touched.
2. Reads the host's entitlements — **before** `insert_dylib --strip-codesig`
   destroys the signature. A dropped `application-groups` entitlement silently
   breaks data sharing with the extensions.
3. Copies the dylib to `Frameworks/` and inserts
   `@executable_path/Frameworks/BoxBox.dylib` as an `LC_LOAD_DYLIB` on the host,
   skipping the insert if the binary already links it.
4. Does the same for every `PlugIns/*.appex` and `Extensions/*.appex`, walking
   the right number of `../` back out to the app's `Frameworks/`.
5. Signs innermost-out: dylib, then `--deep` on the bundle, then each extension
   with its entitlements re-applied (because `--deep` discards them), then the
   bundle seal last.
6. Verifies the host and each extension individually, then repacks `Payload/` and
   checks the archive.

## Verifying a build

A constructor that crashes still prints its first log lines and `simctl launch`
still reports a pid, so a launch that "looks fine" is not proof. Confirm the
dylib is really in the installed bundle *and* really loaded:

```sh
B=$(xcrun simctl appinfo "$UDID" <bundle-id> | awk -F'"' '/ Path =/ { print $2 }')
otool -L "$B/<Executable>" | grep -i BoxBox          # load command present
ls -l "$B/Frameworks/BoxBox.dylib"                   # dylib shipped in the bundle
xcrun simctl spawn "$UDID" log show --last 3m \
  --predicate 'eventMessage CONTAINS "[BoxBox]"'
```

Then confirm it *stayed* up:

```sh
sleep 10; pgrep -f 'BoxBoxClub.app/BoxBoxClub$' || echo "died after launch"
ls -t ~/Library/Logs/DiagnosticReports/*.ips | head -3
```

An `.ips` file timestamped seconds after launch is the real verdict — open it and
read `faultingThread`, not just the app's own log output.

## Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `xcodegen: missing source directory` | `project.yml` references a path that does not exist. |
| Link error: undefined `_BBInstall…` | The project was generated before the file was added. `scripts/build.sh` regenerates every time; if you invoked `xcodebuild` directly, run `make project` first. |
| `The executable has code for these platforms: [iOS, arm64]` | A device build is being installed on the simulator. Use `make sim`, which patches the platform. |
| `duplicate linked dylib` at launch | `insert_dylib` ran twice. `inject.sh` detects an existing load command and skips — check whether the input was already tweaked (`make doctor APP=…`). |
| Extension exits ~11 ms after spawn, `OS_REASON_CODESIGNING` | Signing order. Nested code must be signed before the bundle seal, and `--deep` throws nested entitlements away. |
| Extension SIGKILLed but the host works | The `.appex` never got the load command, or was not re-signed. |
| Nothing in the log at all | The dylib is not loaded in *that* binary. `otool -L` the installed copy. |
| App dies a second after launch, frames alternating between two dylibs | Two tweaks in one process. Replace the existing dylib instead of adding a second. |
| Widget still locked, host unlocked | The extension did not get the load command. |
| `xcrun simctl` cannot find the device | `UDID` is stale. `xcrun simctl list devices booted`. |
| Screenshot is all black | The display buffer is not up yet. Shoot again after a few seconds — a blank frame is tens of KB, real UI is ~1 MB. |
