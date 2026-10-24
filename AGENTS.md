# Agent guide

BoxBox is an iOS dylib injected into an existing app binary. Read `README.md`
for the workflow; this file is only the conventions.

## Invariants

- **Never mutate the injection target.** `scripts/inject.sh` stages a copy; keep
  it that way. Target apps live in `vendor/` and are gitignored.
- **`BoxBox.xcodeproj` is generated.** Edit `project.yml`; never hand-edit the
  project or commit it.
- **Keep the install_name stable** at `@executable_path/Frameworks/BoxBox.dylib`.
  `inject.sh` and `build.sh` both hardcode it via the `INSTALL_NAME` variable.
- **Preserve entitlements on re-sign.** The read → re-apply dance in `inject.sh`
  is load-bearing; don't simplify it to a bare `codesign -f -s -`.
- Build output goes to `build/`. Nothing generated is committed.

## Shell

Scripts target `/bin/bash` 3.2 as shipped on macOS:

- `set -euo pipefail` is on, so `${arr[@]}` on an empty array is an error —
  prefer plain strings over arrays, or `${arr[@]+"${arr[@]}"}`.
- Keep `printf`-based `note`/`warn`/`die` helpers rather than raw `echo`.
- Scripts must stay idempotent and safe to run twice.

## Adding a hook

1. Write the `bb_`-prefixed method next to `BoxBoxInit()` in `src/BoxBox.m`.
2. Register it with `BBSwizzle` / `BBSwizzleClass` inside `BoxBoxInit()`.
3. Log what you did with `BBLog` — it is the only debugging channel on device.
4. Use `BBDumpMethods` for recon instead of guessing selectors.

Vendored headers go in `include/`; add the include path in `project.yml` if it
is not `include/` or `src/`.
