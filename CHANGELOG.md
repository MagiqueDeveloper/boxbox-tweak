# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The version lives in `src/BBVersion.h` and nowhere else.

## [Unreleased]

### Changed

- Split the single `src/BoxBox.m` into focused modules: `BBLog`, `BBRuntime`,
  `BBPreferences`, `BBPremium`, `BBTabTransitions`, `BBPaywall`. `BoxBox.m` is
  now only the dyld constructor.
- Unified the two swizzling helpers: `BBSwizzle` and `BBHookInstance` share one
  implementation, and both are documented in `BBRuntime.h`.
- Consolidated the duplicated `note` / `warn` / `die` helpers from every script
  into `scripts/lib/common.sh`, with preflight checks and terminal-aware colour.
- `scripts/build.sh` now regenerates the Xcode project on every build instead of
  only when it is missing, so a newly added source file cannot be silently left
  out of the target. The full `xcodebuild` log is kept at `build/xcodebuild.log`.
- `scripts/inject.sh` resolves its output path to an absolute path before
  repacking. Previously a relative `OUT` was written inside the scratch
  directory, which the exit trap then deleted.
- `scripts/inject.sh` verifies the host and every embedded extension
  individually, because `codesign --verify --deep` on the parent can pass while a
  nested binary is invalid.
- `scripts/inject.sh` no longer leaves a `<binary>.bak` inside the injected
  bundle — the pristine input is the backup.
- Compiler warnings are errors, with a stricter warning set, in `project.yml`.

### Added

- `scripts/doctor.sh` (`make doctor`): host, toolchain, repository and input-app
  preflight, including per-Mach-O `cryptid` and already-loaded dylib reporting.
- `scripts/lint.sh` (`make lint`): shell syntax, shellcheck, clang-format, tag /
  `BB_VERSION_STRING` agreement, line endings, trailing whitespace, and a check
  that no build artifacts are tracked.
- `scripts/fmt.sh` (`make fmt`) and `scripts/version.sh`.
- `.clang-format`, `.editorconfig`, `.gitattributes`.
- `docs/ARCHITECTURE.md`, `docs/BUILDING.md`, `docs/RECON.md`.
- `SECURITY.md`, `CODE_OF_CONDUCT.md`, and GitHub issue / PR templates.
- A `ci.yml` workflow running `make lint` and `make build`.

### Removed

- The empty `include/` directory and its `project.yml` source entry. The dylib
  exports no public headers, so it was a scaffold leftover; `src/` is the only
  source root now.
- `release-notes.md`, superseded by this changelog. The release workflow
  generates its notes from the commit history.

## [1.0.0] - 2024-10-24

### Added

- Injectable dylib scaffolding: dyld constructor, swizzling helpers, tagged
  logging.
- Paid-tier unlock via `NSUserDefaults` class hooks plus app-group suite seeding,
  so extension processes read the same state.
- Animated tab transitions on the private selection funnel.
- Launch-funnel subscription cover suppression.
- Host and extension injection with entitlement preservation and innermost-out
  signing; ad-hoc signing throughout, so no developer account is needed.
- `make build`, `make sim`, `make inject`, `make run`, `make install`, `make logs`
  and the `scripts/` equivalents.

[Unreleased]: https://github.com/MagiqueDeveloper/boxbox-tweak/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/MagiqueDeveloper/boxbox-tweak/releases/tag/v1.0.0
