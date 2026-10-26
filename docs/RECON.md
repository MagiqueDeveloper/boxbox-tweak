# Recon

How the hook points in this project were found, and how to find new ones. The
short version: **pick the highest, cheapest lever, then prove it from the
console** rather than guessing from a screenshot.

## 0. Get a decrypted binary

An App Store IPA is FairPlay-encrypted: `__TEXT` is scrambled, so static recon is
worthless even though hooks still load. `cryptid 0` means decrypted, anything
else means encrypted.

```sh
make doctor APP=vendor/BoxBoxClub.ipa
```

The doctor checks every Mach-O, not just the executable — a half-decrypted IPA
(host dumped, frameworks not) passes a naive check. Where decrypted IPAs come
from, best first:

1. **A pre-decrypted IPA.** Verify `cryptid 0` and move on. This is the normal
   path.
2. **`ipatool`** — `ipatool auth login`, `purchase`, `download`. Convenient, but
   the result is **still encrypted**; it only saves an iTunes round-trip.
3. **An on-device dumper** on a jailbroken or TrollStore device (`frida-ios-dump`,
   `bakbak`, or a decryptor app), filed back via AirDrop or Files. That step
   happens on the device and is outside this Mac-side loop.

Two rules that save hours:

- **Never trust `strings` on a Swift binary.** Swift inlines string literals of
  15 bytes or fewer into code, so a key like `Is_Pro_User` never appears in
  `__cstring`. Absence from `strings` is not absence from the binary.
- **App code is symbol-stripped.** `image lookup -rn` finds nothing for the app's
  own classes. It still works against system frameworks, which is what you want
  when hooking UIKit. For the app's own classes, use `objc_getClassList`.

## 1. Pick the lever

App state usually lives in one of these, in rough order of how cheaply it can be
faked:

| # | Lever | Why it is cheap |
| --- | --- | --- |
| 1 | **Shared app-group defaults** | Easiest, and it propagates to extensions automatically. |
| 2 | **`NSUserDefaults` in the app's own suite** | Same idea, host only. |
| 3 | **A third-party entitlement SDK** (RevenueCat et al.) | Hookable at the SDK boundary. |
| 4 | **StoreKit 2** `Transaction.currentEntitlements` | Hardest — Swift value types, no defaults lever. |

Box Box Club uses #1. Its paid-tier flags live in
`group.club.boxbox.sharedDefaults`, which is exactly *why* the widget can read
them — and therefore why forcing them unlocks host and widget together.

## 2. Static surface

```sh
unzip -q vendor/BoxBoxClub.ipa -d work
APP=$(find work/Payload -maxdepth 1 -name '*.app' -print -quit)
BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

xcrun dyld_info -objc "$BIN" > objc.txt
grep -E '@interface .*(Manager|Purchase|Subscription|Entitlement)' objc.txt
strings -a "$BIN" | grep -iE 'ultra|premium|pro_|subscri|entitle'
strings -a "$BIN" | grep -E '^[a-z]+\.[a-z0-9.]+[a-z.]+$'   # bundle / product ids
```

Bundled `.storekit` configs, `RevenueCat_*.bundle` and `RCPurchases*` symbols tell
you which SDK owns the gate. This app caches its own
`api.boxboxclub.com/v4/user/profile` response into defaults under a
`subscription-v1` key instead.

## 3. Read what the app persisted

The payoff step: **run the app once**, then read what it wrote.

```sh
C=$(xcrun simctl get_app_container booted club.boxbox.widgets-ios data)
plutil -p "$C/Library/Preferences/"*.plist | grep -iE 'subscri|_user|entitle|token'
```

This is where the five keys came from:

```
Is_Pro_User, Is_Elite_User, Is_Ultra_User, Is_Select_User, Last_Known_Subscribed
```

and where the cached profile response showed its shape:

```json
{"token": "false|basic", ...}
```

A flag living in a `group.<team>.*` suite means the widget or extension reads it
from there — force it once and every process sees it.

**No new key appearing after the paywall or onboarding screen shows** means the
gate is in-memory SwiftUI state, not persisted state. A defaults lever cannot
reach it and you have to intercept the presentation itself instead — which is
what `BBPaywall.m` does.

## 4. Live recon with lldb

Attach to the running app in the simulator. Command files must end with `detach`
so the app is left running.

```sh
#!/usr/bin/env bash
# recon.sh <commands.lldb>
set -euo pipefail
CMD="${1:?usage: recon.sh <commands.lldb>}"
PID="$(pgrep -f 'BoxBoxClub\.app/BoxBoxClub$' | head -1)"
[[ -n "$PID" ]] || { echo "BoxBoxClub is not running in the simulator" >&2; exit 1; }
xcrun lldb --batch -p "$PID" -s "$CMD" \
    | sed -n '/command source/,$p' \
    | grep -v '^\s*[˄│]' \
    | grep -v '^(lldb) expr -l objc++ -- @import'
```

### Enumerate the app's own classes

`image lookup -rn` will not find them, so walk the runtime's class list:

```lldb
expr -l objc++ -- @import ObjectiveC
expr -l objc++ -- @import UIKit
expr -l objc++ -O -- (id)({ NSMutableArray *o=[NSMutableArray array]; unsigned int n=(unsigned int)objc_getClassList(NULL,0); Class *l=(Class*)malloc(sizeof(Class)*n); objc_getClassList(l,n); for(unsigned i=0;i<n;i++){ const char *nm=(const char *)class_getName(l[i]); NSString *s=[NSString stringWithUTF8String:nm]; if([s containsString:@"TabBarController"]||[s containsString:@"TabHosting"]||[s containsString:@"AdaptableTab"]){ [o addObject:[NSString stringWithFormat:@"%s  (super=%s)",nm,(const char *)class_getName((Class)class_getSuperclass(l[i]))]]; } } free(l); [o componentsJoinedByString:@"\n"]; })
```

That is how the tab bar was identified as a plain `UITabBarController` owned by
SwiftUI's `TabViewCoordinator_Phone`, with no custom animator.

### Print the live view tree

```lldb
expr -l objc++ -O -- (id)[(UIViewController *)[[(UIWindowScene *)[[(NSSet *)[[UIApplication sharedApplication] connectedScenes] allObjects] firstObject] windows].firstObject rootViewController] _printHierarchy]
expr -l objc++ -O -- (id)[(UIViewController *)[[(UIWindowScene *)[[(NSSet *)[[UIApplication sharedApplication] connectedScenes] allObjects] firstObject] windows].firstObject rootViewController] presentedViewController]
```

`_printHierarchy` on the root controller names the whole launch funnel's screen
stack in one shot — the fastest way to name a gate. This is how the cover was
identified as `SubscriptionWelcomeView` presented as a
`_TtGC7SwiftUI29PresentationHostingController` over the root hosting controller.

### Find the funnel

```lldb
image lookup -rn "UITabBarController.*setSelected"
```

11 matches on this app, of which these are the ones that matter:

```
-[UITabBarController setSelectedIndex:]
-[UITabBarController setSelectedViewController:]
-[UITabBarController _setSelectedViewController:]
-[UITabBarController _setSelectedViewController:performUpdates:]
-[UITabBarController _setSelectedViewControllerAndNotify:]
-[UITabBarController _setSelectedTabBarItem:]
-[UITabBarController setSelectedTab:]
-[UITabBarController _tabBarItemClicked]
```

Every public route — `setSelectedIndex:`, `setSelectedViewController:`, a tab bar
item tap, SwiftUI's programmatic selection — ends in
`_setSelectedViewController:performUpdates:`. Hooking that one private funnel
covers all of them. That is the whole reason `BBTabTransitions.m` hooks two
selectors instead of eight.

### Parser traps that eat a whole command file

- `expr -l objc++` is required; plain `expr` will not parse ObjC++.
- Use `@import` to pull in frameworks before referring to their types.
- Wrap multi-statement expressions in `(id)({ … })` and end with an expression
  that yields a value — the last statement is what gets printed.
- Do not subscript an `id` or cast a block literal inline; bind it to a typed
  local first.
- Single-letter locals collide with lldb's own variables. Use real names.

## 5. Confirm the lever, then write the hook

Once a key is identified, log it once from the hook and read the line back:

```
[BoxBox] defaults: Is_Ultra_User = 0
```

That single line is the proof the key and the value are real — better than any
amount of inference from a screenshot. `BBLogOnce` exists so this costs nothing
on a hot path.

For a defaults-based gate, hook the `NSUserDefaults` **class** (not a suite) on
read *and* write, and cover removals too: a key that gets removed silently
reverts to `false` for every process you are not injected into. Then seed the
shared suite at load so the widget processes, which do not link this dylib, read
the same state off disk.

The full hook table is in [`ARCHITECTURE.md`](ARCHITECTURE.md).
