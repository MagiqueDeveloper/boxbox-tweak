## What this changes

<!-- One or two sentences. If it fixes an issue, link it. -->

## Why

<!-- The reason, not the mechanism. "The extension stayed locked because…" -->

## How it was verified

<!--
Not "it builds". Which of these did you actually run, and what did you see?
  make check
  make sim / CLEAN=1 make sim
  make sim-logs  (paste the [BoxBox] lines)
  make doctor APP=…
-->

## Checklist

- [ ] `make check` is green (lint + build)
- [ ] One logical change; no unrelated reformatting
- [ ] The input IPA / `.app` is still never mutated, and nothing from `build/`
      or `vendor/` is committed
- [ ] New or changed hooks are crash-proof and guarded — a nil
      `NSClassFromString()` at constructor time is normal
- [ ] Every new tunable is registered with `BBRegisterPreferenceDefaults` and
      documented in the README's configuration table
- [ ] `docs/ARCHITECTURE.md`'s hook table is updated if a hook changed
- [ ] `docs/RECON.md` is updated if you learned *how* to reach something new
- [ ] `CHANGELOG.md` has an entry under `Unreleased`
