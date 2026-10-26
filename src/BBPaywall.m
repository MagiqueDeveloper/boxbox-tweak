//
//  BBPaywall.m
//  BoxBox
//
//  The launch funnel ends in `SubscriptionWelcomeView` ("120+ widgets", $23.99 /
//  year) presented as a SwiftUI `fullScreenCover` — i.e. a
//  `_TtGC7SwiftUI29PresentationHostingController` over the root hosting
//  controller, with a `_UIOverFullscreenPresentationController`.
//
//  The cover carries its own X button and the funnel only continues once it has
//  been dismissed, so dropping the presentation outright would leave the app
//  parked underneath it. Instead we let the cover present (un-animated, fully
//  transparent) and close it on the spot through its own path, which fires the
//  same `onDismiss` the X button does. The user never sees a frame of it.
//
//  Tunables:
//
//      defaults write club.boxbox.widgets-ios BBPaywallEnabled -bool NO
//      defaults write club.boxbox.widgets-ios BBPaywallMode    -string skip
//

#import "BBPaywall.h"

#import <UIKit/UIKit.h>

#import "BBLog.h"
#import "BBPreferences.h"
#import "BBRuntime.h"

#pragma mark - Tunables

static NSString *const BBPaywallEnabledKey = @"BBPaywallEnabled";
static NSString *const BBPaywallModeKey = @"BBPaywallMode";

/// Present the cover, hide it, close it. The safest default.
static NSString *const BBPaywallDefaultMode = @"flash";

/// Never present the cover at all. Cheaper, but only safe where the app does not
/// gate the funnel on the dismissal callback.
static NSString *const BBPaywallSkipMode = @"skip";

#pragma mark - Matcher

/// `bb_presentViewController:animated:completion:` calls through to the real one.
@interface UIViewController (BBPaywall)
- (void)bb_presentViewController:(UIViewController *)viewController
                        animated:(BOOL)animated
                      completion:(void (^_Nullable)(void))completion;
@end

static BOOL BBPaywallEnabled(void) {
    return BBPreferenceBool(BBPaywallEnabledKey, YES);
}

static NSString *BBPaywallMode(void) {
    return BBPreferenceString(BBPaywallModeKey, BBPaywallDefaultMode);
}

/// Only the root-level SwiftUI cover is the funnel paywall; sheets pushed from
/// inside the tab bar controller have a different presenter and are left alone.
static BOOL BBPaywallIsFunnelCover(UIViewController *presenter, UIViewController *presented) {
    if (!presenter || !presented) {
        return NO;
    }
    if (![BBClassName(presented) containsString:@"PresentationHostingController"]) {
        return NO;
    }
    if (presented.modalPresentationStyle != UIModalPresentationOverFullScreen) {
        return NO;
    }

    UIWindow *window = presenter.view.window;
    return window != nil && window.rootViewController == presenter;
}

/// True once the tab bar controller is in the root's hierarchy — i.e. the app has
/// already moved past onboarding and the cover is only an overlay on the home
/// screen.
static BOOL BBHomeLoaded(UIViewController *root) {
    // `children` is the iOS 17 spelling and the deployment target is 15.0, so the
    // older accessor is the one that exists here. Silence the deprecation notice
    // rather than raise the floor for one lookup.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSArray<UIViewController *> *children = root.childViewControllers;
#pragma clang diagnostic pop

    for (UIViewController *child in children) {
        if ([child isKindOfClass:UITabBarController.class]) {
            return YES;
        }
    }
    return NO;
}

/// Closes the cover the way its own X button does.
///
/// UIKit's dismissal alone leaves SwiftUI's `isPresented` binding stuck on
/// `true`, and the first tap on the screen underneath then goes to reconciling
/// that phantom cover instead of the control the finger is on (the "press it
/// twice" bug). An accessibility escape goes through the presentation's own
/// machinery, so the binding resets.
static void BBCloseCover(UIViewController *cover) {
    cover.presentationController.containerView.alpha = 0.0;

    BOOL escaped = [cover accessibilityPerformEscape];
    if (!escaped) {
        [cover dismissViewControllerAnimated:NO completion:nil];
    }

    BBLog(@"paywall cover closed (escape=%d)", escaped);
}

#pragma mark - Hook

static void BBSwizzledPresent(UIViewController *self, SEL _cmd, UIViewController *viewController,
                              BOOL animated, void (^_Nullable completion)(void)) {
    if (!BBPaywallIsFunnelCover(self, viewController)) {
        [self bb_presentViewController:viewController animated:animated completion:completion];
        return;
    }

    if (!BBPaywallEnabled()) {
        BBLog(@"paywall cover allowed (%@, disabled)", BBClassName(viewController));
        [self bb_presentViewController:viewController animated:animated completion:completion];
        return;
    }

    BOOL home = BBHomeLoaded(self);
    if ([BBPaywallMode() isEqualToString:BBPaywallSkipMode]) {
        BBLog(@"paywall cover skipped (home=%d)", home);
        return;
    }

    // Present it fully transparent, then let it settle for a runloop before
    // closing: no frame of it ever composites, and SwiftUI gets to finish its
    // own presentation bookkeeping first.
    BBLog(@"paywall cover swallowed (home=%d)", home);
    viewController.view.alpha = 0.0;
    [self bb_presentViewController:viewController
                          animated:NO
                        completion:^{
                            dispatch_async(dispatch_get_main_queue(), ^{
                                BBCloseCover(viewController);
                            });
                        }];
}

#pragma mark - Installation

void BBInstallPaywallSkip(void) {
    BBRegisterPreferenceDefaults(@{
        BBPaywallEnabledKey: @YES,
        BBPaywallModeKey: BBPaywallDefaultMode,
    });

    BBHookInstance(UIViewController.class, @selector(presentViewController:animated:completion:),
                   @selector(bb_presentViewController:animated:completion:),
                   (IMP)BBSwizzledPresent);

    BBLog(@"paywall skip armed (%@)", BBPaywallMode());
}
