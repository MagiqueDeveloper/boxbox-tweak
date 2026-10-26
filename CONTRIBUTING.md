# Contributing to BoxBox

Thanks for wanting to help. This project is a single small dylib with a
deliberately narrow surface, so most of the value is in keeping it small,
readable and crash-proof.

## Before you start

```sh
brew install xcodegen insert-dylib shellcheck
make doctor     # tells you what is missing, and what your input app looks like
make check      # lint + build; both must be green before you open a PR
```

You need your own decrypted copy of the app to test against. See
[`docs/RECON.md`](docs/RECON.md).

## Ground rules

1. **Never mutate the input.** Stage a copy. `vendor/` and `build/` are
   gitignored; a bad build must always be re-injectable from a pristine source.
2. **Never commit an IPA, a `.app`, a `.dylib`, or anything from `build/`.**
   `make lint` fails if one is tracked.
3. **Hook bodies must be crash-proof.** A hook that runs during app startup runs
   before the app's own classes are linked, so a nil `NSClassFromString()` is
   normal. Guard, log, and return.
4. **Log every decision** with `BBLog`. On a device, the console is the only
   channel you have; a screenshot only shows the end state, the log shows which
   branch ran.
5. **One tweak per process.** If the input already carries a dylib, replace it
   under its own file name rather than adding a second one — two tweaks grafting
   the same `bb_*` selectors onto `NSUserDefaults` recurse until the stack guard
   trips.
6. **Keep the input clean.** No network code, no background work, no persistent
   daemons. A hook installs at load and does its job when called.

## Adding a feature

A feature is one `BB<Feature>.{h,m}` pair exposing a single
`BBInstall<Feature>()`. `src/BBPaywall.m` is the shortest complete example.

```objc
// src/BBFeature.h
NS_ASSUME_NONNULL_BEGIN
/// One sentence: what this arms, and when to call it.
void BBInstallFeature(void);
NS_ASSUME_NONNULL_END
```

```objc
// src/BBFeature.m
#import "BBFeature.h"

#import "BBLog.h"
#import "BBPreferences.h"
#import "BBRuntime.h"

void BBInstallFeature(void) {
    BBRegisterPreferenceDefaults(@{ @"BBFeatureEnabled": @YES });

    BBHookInstance(SomeClass.class,
                   @selector(someMethod:),
                   @selector(bb_someMethod:),
                   (IMP)BBSwizzledSomeMethod);

    BBLog(@"feature armed");
}
```

Then add the header to `src/BoxBox.h` and the call to `BoxBoxInit()` in
`src/BoxBox.m`. New files are picked up automatically — `scripts/build.sh`
regenerates the Xcode project on every build.

### Choosing the right hook

| Helper | Use when |
| --- | --- |
| `BBHookInstance(cls, original, replacement, imp)` | You have a plain C function. This is the normal case. |
| `BBSwizzle(cls, original, replacement)` | You have a category method already declared on `cls`. |
| `BBSwizzleClass(cls, …)` | The target is a class method (operates on the metaclass). |

Prefer hooking a **funnel** — the one private method every public route reaches
— over hooking each public entry point. `BBTabTransitions.m` hooks two private
selectors and covers taps, programmatic selection and deep links at once.

`BBDumpMethods(cls)` logs a class's method list when you need to find one.

## Style

- Objective-C: 4-space indent, 100 columns, `clang-format` clean
  (`.clang-format`). Run `make fmt` before committing.
- Shell: bash 3.2 compatible — no associative arrays, no `mapfile`. Source
  `scripts/lib/common.sh` for `bb_note` / `bb_step` / `bb_warn` / `bb_die` and
  the preflight helpers rather than re-implementing them. Every script must pass
  `shellcheck -x`.
- Comments explain **why**, not what. If a hook targets private API or works
  around a framework quirk, say which quirk.
- Doc comments (`///`) on everything exported from a header. The build treats
  warnings as errors, including `-Wdocumentation`.

## Testing a change

```sh
make check                                  # lint + build
make sim                                    # simulator: patch, inject, install, launch
make sim-logs                               # what the tweak did
make sim-logs -f                            # follow
CLEAN=1 make sim                            # wipe the container = empty defaults
```

There is no unit-test target: the behaviour under test is the app's own. The
verification loop is the constructor log line plus the app's reaction to it.
`docs/BUILDING.md` has the per-step checks and the common failures.

## Pull requests

- One logical change per PR.
- `make check` green.
- If you add or change a hook, update `docs/ARCHITECTURE.md`'s hook table and
  add a `CHANGELOG.md` entry under `Unreleased`.
- If you discovered *how* to hook something, add it to `docs/RECON.md` — that
  file is the project's memory.

## Releasing

Maintainers only:

1. Bump `BB_VERSION_STRING` in `src/BBVersion.h`. That is the only place the
   version lives; `make lint` and CI compare it against the tag.
2. Move the `Unreleased` entries in `CHANGELOG.md` under the new version.
3. `make check`, then commit and tag:

   ```sh
   git tag v1.0.0 && git push origin v1.0.0
   ```

The release workflow builds the dylib, refuses to publish if the tag and
`src/BBVersion.h` disagree, attaches the binary with a SHA-256 checksum, and
generates the release notes from the commit history. Injected IPAs are never
published — everyone builds their own.
