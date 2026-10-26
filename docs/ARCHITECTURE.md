# Architecture

BoxBox is one dynamic library that dyld maps into the host app before `main()`.
Everything it does happens through the Objective-C runtime: a constructor
installs a small, fixed set of hooks, and those hooks are the entire feature
surface. There is no configuration file, no network code, and no background
work.

## Modules

| File | Responsibility |
| --- | --- |
| `src/BoxBox.m` | The `__attribute__((constructor))` entry point and nothing else. Fixes the load order. |
| `src/BoxBox.h` | Umbrella header. Import it to get everything. |
| `src/BBLog.{h,m}` | `BBLog` and `BBLogOnce`. `NSLog` under the hood — the only channel that works on a device *and* the simulator, and the one `make logs` / `make sim-logs` filter on. |
| `src/BBRuntime.{h,m}` | `BBSwizzle`, `BBSwizzleClass`, `BBHookInstance`, `BBDumpMethods`, `BBClassName`. All safe to call from a constructor. |
| `src/BBPreferences.{h,m}` | Typed reads of the tweak's own tunables, with registered defaults so an unset key reads as its documented value rather than zero. |
| `src/BBPremium.{h,m}` | The paid-tier unlock: `NSUserDefaults` hooks plus shared-suite seeding. |
| `src/BBTabTransitions.{h,m}` | Cross-fade between tabs on the private selection funnel. |
| `src/BBPaywall.{h,m}` | Suppress the launch funnel's SwiftUI subscription cover. |
| `src/BBVersion.h` | `BB_VERSION_STRING`. Single source of truth; `make lint` and the release workflow both read it. |

A feature is one `BB<Feature>.{h,m}` pair exposing a single `BBInstall<Feature>()`,
called from `BoxBoxInit()`. `src/BBPaywall.m` is the shortest complete example.

## Load order

```objc
BBInstallPremiumUnlock();   // must be armed before the app reads a paid-tier key
BBSeedPremiumFlags();       // writes the shared suite so extensions agree
BBInstallTabTransitions();
BBInstallPaywallSkip();
```

Only the first pair is order-sensitive. The defaults hooks have to be in place
before the app's own startup code reads a premium flag, and the suite has to be
seeded before a widget process reads it off disk.

## Hooks

### Paid tier — `BBPremium.m`

Hooks the **class** `NSUserDefaults`, not a suite, so every instance and every
suite is covered by one set of hooks:

| Selector | Why |
| --- | --- |
| `boolForKey:` | The flags the app gates features on. |
| `integerForKey:` | Some call sites read the same flag as an integer. |
| `objectForKey:` | The general path; also carries the cached profile response. |
| `dataForKey:` | Same response, read as `NSData`. |
| `setBool:forKey:` | The app re-derives its state; without this it writes `false` back. |
| `setInteger:forKey:` | Same, integer path. |
| `setObject:forKey:` | Same, object path. |
| `removeObjectForKey:` | A removed key would revert to `false` for processes we are not injected into. |

Five keys are recognised: `Is_Pro_User`, `Is_Elite_User`, `Is_Ultra_User`,
`Is_Select_User`, `Last_Known_Subscribed`. `BBSeedPremiumFlags()` writes them into
`group.club.boxbox.sharedDefaults` so widget and intent processes that do **not**
link this dylib still read the unlocked state.

`api.boxboxclub.com/v4/user/profile` is cached in defaults under a
`subscription-v1` key as `{"token":"<subscribed>|<plan>"}`. The read hooks rewrite
`"false|` to `"true|` and any plan suffix to `ultra`.

### Tab transitions — `BBTabTransitions.m`

The app's tab bar is a plain `UITabBarController` with no custom animator, so a
tap swaps the content with no animation while only the tab bar's own indicator
animates. The hook is on the private funnel every route reaches —
`_setSelectedViewController:` and
`_setSelectedViewController:performUpdates:` — so taps, `setSelectedIndex:`, and
SwiftUI's programmatic selection are all covered by one pair of hooks.

The transition snapshots the outgoing view as a "ghost" under the incoming one,
so the two genuinely cross-dissolve rather than the content cutting. A
`BBTabSwapping` flag stops the inner funnel from animating a second time when the
outer one calls through, and `UIAccessibilityIsReduceMotionEnabled()` disables the
slide component.

### Paywall — `BBPaywall.m`

`UIViewController -presentViewController:animated:completion:` is hooked and
filtered to exactly one shape: a SwiftUI `PresentationHostingController`
presented `OverFullScreen` by the window's root controller. Anything else passes
straight through, which is what keeps sheets inside the tab bar controller
working.

The cover is not dropped. `SubscriptionWelcomeView` carries its own X button and
the funnel only continues once it is dismissed, so skipping the presentation
would park the app underneath it. Instead the cover is presented transparent and
un-animated, then closed on the next runloop with `accessibilityPerformEscape`
— the presentation's own path, which resets the SwiftUI `isPresented` binding
that a plain `dismissViewControllerAnimated:` leaves stuck on `true`.

## Concurrency

Every hook is installed once, from the constructor, before any app code runs, so
no locking is needed around installation. The hooks themselves run on whatever
thread called them: `NSUserDefaults` reads can come from anywhere, so the hook
bodies stay branch-only and never block. The one piece of shared state that is
not thread-confined, `BBLogOnce`'s seen-set, is guarded with `@synchronized`.

## Failure modes

| Symptom | Cause |
| --- | --- |
| No `[BoxBox] loaded into …` line | The dylib is not in the bundle, or has no load command in *that* binary. Check with `otool -L` on the installed copy. |
| App dies a second after launch, frames alternating between two dylibs | Two tweaks in one process. Both graft the same `bb_*` selectors onto `NSUserDefaults` and recurse until the stack guard trips. Replace the existing dylib rather than adding a second. |
| Extension killed ~11 ms after spawn, `OS_REASON_CODESIGNING` | Signing order. Nested code must be signed before the bundle seal, and `--deep` discards nested entitlements. |
| `duplicate linked dylib` at launch | `insert_dylib` ran twice on the same binary. `scripts/inject.sh` detects this and skips. |
| First tap after launch does nothing | The cover was dismissed by UIKit rather than through its own path, leaving `isPresented` stuck `true`. |
| Widget still locked, host unlocked | The `.appex` did not get the load command. |
