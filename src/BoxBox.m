//
//  BoxBox.m
//  BoxBox
//
//  Entry point. Everything else lives in a module — see BoxBox.h for the map.
//

#import "BoxBox.h"

#import <Foundation/Foundation.h>
#import <unistd.h>

#pragma mark - Entry point

/// Called by dyld as soon as the dylib is mapped into the host process, before
/// `main()`. All hooks are installed from here.
///
/// Order matters in one respect only: the defaults hooks must be armed before
/// the app reads a paid-tier key, so `BBInstallPremiumUnlock` goes first.
///
/// The log line below is the proof that the tweak is in-process — grep for it
/// before drawing any conclusion from what the screen shows:
///
///     [BoxBox] loaded into BoxBoxClub (pid 1234, Version 18.0, BoxBox 1.0.0)
///
/// Adding a feature: put it in its own `BB<Feature>.{h,m}` pair, expose a single
/// `BBInstall<Feature>()`, and call it here. `NSClassFromString()` returns nil
/// until a class is linked in; if that bites you, hook lazily from the `+load`
/// of a category instead.
__attribute__((constructor)) static void BoxBoxInit(void) {
    @autoreleasepool {
        BBLog(@"loaded into %@ (pid %d, %@, BoxBox %@)", NSProcessInfo.processInfo.processName,
              getpid(), NSProcessInfo.processInfo.operatingSystemVersionString, BB_VERSION_STRING);

        BBInstallPremiumUnlock();
        BBSeedPremiumFlags();
        BBInstallTabTransitions();
        BBInstallPaywallSkip();
    }
}
