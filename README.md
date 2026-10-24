# BoxBox

A standalone iOS dylib that is injected into an existing app binary. No jailbreak
required — the injected build is ad-hoc signed, so it runs on a TrollStore'd or
sideloaded device.

The dylib installs a `__attribute__((constructor))` that fires as soon as dyld maps
it into the host process. From there you can swizzle Objective-C methods or hook C
functions. Helper entry points live in [`src/BoxBox.h`](src/BoxBox.h).

## Layout

```
src/           dylib sources; BoxBox.m holds the constructor + hooks
include/       vendored headers (substrate.h, fishhook, ...) as you need them
scripts/       build / inject / install / logs
vendor/        target .ipa / .app you are injecting into (gitignored)
project.yml    xcodegen spec — BoxBox.xcodeproj is generated, not committed
build/         build output; BoxBox.dylib and injected artefacts
```

## Requirements

```sh
brew install xcodegen insert-dylib ideviceinstaller
```

Plus Xcode, and `ldid`/`ldid-procursus` or `codesign` (already on this machine).
`ipatool` (`brew install ipatool`) is handy for pulling App Store IPAs to inject into.

## Workflow

```sh
make build                      # -> build/BoxBox.dylib (arm64, ad-hoc signed)

./scripts/inject.sh Foo.ipa     # -> Foo-injected.ipa   (input untouched)
./scripts/install.sh Foo-injected.ipa

./scripts/logs.sh               # tail device console, filtered to [BoxBox]
```

`make run APP=Foo.ipa` does build → inject → install in one go. All scripts read
`UDID=<device-udid>` when more than one device is attached.

## How injection works

1. `scripts/build.sh` compiles `src/` into `BoxBox.dylib` with
   `-install_name @executable_path/Frameworks/BoxBox.dylib`, then ad-hoc signs it.
2. `scripts/inject.sh` copies the dylib to `App.app/Frameworks/`, appends an
   `LC_LOAD_DYLIB` load command to the app binary via `insert_dylib`, and re-signs.
   The original binary is kept as `App.bak` and the input file is never modified.
3. The host's original entitlements are read with `codesign -d --entitlements`
   and re-applied, because ad-hoc re-signing drops them and some frameworks
   refuse to load without them.

## Writing hooks

Add to `BoxBoxInit()` in `src/BoxBox.m`:

```objc
Class target = NSClassFromString(@"SomeViewController");
BBSwizzle(target, @selector(viewDidLoad), @selector(bb_viewDidLoad));
```

`NSClassFromString()` returns `nil` for classes that are not linked yet. If that
bites you, swizzle from a `+load` category or hook the class lazily.

`BBDumpMethods(cls)` prints a class's method list — handy for recon before you
know what to hook.

## Caveats

- Only `arm64`. arm64e/`ptrauth` targets need extra work.
- Debugging is `idevicedebug` / `lldb` attach, or `os_log` via `BBLog`.
- After an iOS or app update the load command is gone; re-inject.
