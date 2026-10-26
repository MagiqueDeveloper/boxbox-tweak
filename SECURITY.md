# Security Policy

## Supported versions

Only the latest tagged release of the dylib is supported. Fixes land on `master`
and in the next tag.

## What this project touches

BoxBox is an injected dylib: by design it runs inside another app's process and
swaps method implementations in that process. That makes the following worth
stating plainly.

- **It is not sandboxed from the host app.** It can read and write anything the
  host app can, including that app's `NSUserDefaults` and its app-group suite.
- **It does not talk to the network.** There is no HTTP client, no telemetry, and
  no remote configuration in `src/`. If you find network code in a build of this
  project, that build is not this project.
- **It does not persist anything of its own.** The only writes are the shared-suite
  flags and the app's own defaults keys, described in
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
- **It is ad-hoc signed, not notarised.** `make build` and `scripts/inject.sh`
  sign with `-` (ad-hoc). Sideloading an ad-hoc signed bundle is the whole point
  of the project, but it means the signature proves nothing about provenance —
  it only satisfies the loader.

## Reports we want

- A hook that can crash, hang, or corrupt state in the host app.
- A hook that runs on a path it was not intended to (for example the paywall
  matcher firing on an unrelated sheet).
- Anything in `src/` that reads, writes or transmits data beyond what is
  documented above.
- A way to make `scripts/inject.sh` damage its input, or produce a bundle that
  installs but is silently invalid.

## How to report

Open a private security advisory through the repository's **Security → Report a
vulnerability** tab rather than a public issue. If that is unavailable, open an
issue that says only that you have a report and would like a private channel.

Please include: the dylib version (`make version`), the host app version, the
iOS version, whether you are on a device or the Simulator, and the `[BoxBox]`
log lines around the problem.

Expect an acknowledgement within a week. This is a hobby project maintained in
spare time — there is no SLA, and no bug bounty.

## Scope

Not in scope: the host app's own security, anything requiring a jailbroken
device to already be compromised, and the legality or terms-of-service
consequences of injecting into an app you do not own. That last one is your call
and your responsibility — see the disclaimer in the [`README`](README.md).
