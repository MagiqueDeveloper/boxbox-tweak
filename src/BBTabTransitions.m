//
//  BBTabTransitions.m
//  BoxBox
//
//  The app's tab bar is a plain `UITabBarController` (SwiftUI's
//  `TabViewCoordinator_Phone` owns it; there is no custom animator), so a tap
//  swaps the selected child view controller with no animation at all: the
//  content cuts while only the tab bar's own glass indicator animates.
//
//  We cross-fade the content container ourselves and nudge the incoming tab in
//  from the side it was picked from, leaving the tab bar itself alone.
//
//  Every route into a tab switch ends in the private funnel below —
//  `setSelectedIndex:`, `setSelectedViewController:`, the tab bar's own item
//  clicks and SwiftUI's programmatic selection all reach it — so one hook covers
//  taps and deep links alike.
//
//  Tunables (all read from the host app's defaults, so feel can be adjusted
//  without a rebuild):
//
//      defaults write club.boxbox.widgets-ios BBTabTransitionStyle    -string slide
//      defaults write club.boxbox.widgets-ios BBTabTransitionDuration -float 0.4
//      defaults write club.boxbox.widgets-ios BBTabTransitionEnabled  -bool NO
//

#import "BBTabTransitions.h"

#import <UIKit/UIKit.h>

#import "BBLog.h"
#import "BBPreferences.h"
#import "BBRuntime.h"

#pragma mark - Tunables

static NSString *const BBTabEnabledKey = @"BBTabTransitionEnabled";
static NSString *const BBTabDurationKey = @"BBTabTransitionDuration";
static NSString *const BBTabStyleKey = @"BBTabTransitionStyle";

static const double BBTabDefaultDuration = 0.30;
static NSString *const BBTabDefaultStyle = @"fadeSlide";

/// Shortest duration worth animating; anything below reads as a cut.
static const double BBTabMinimumDuration = 0.01;

#pragma mark - State

/// `bb_` selectors grafted onto `UITabBarController` that call through to the
/// real implementations.
@interface UITabBarController (BBTabTransitions)
- (void)bb_setSelectedViewController:(UIViewController *)viewController;
- (void)bb_setSelectedViewController:(UIViewController *)viewController
                      performUpdates:(BOOL)performUpdates;
@end

/// Views owned by the transition in flight, so a fast tap flushes the previous
/// one instead of stacking animations on top of each other.
static __weak UIView *BBTabGhostView;
static __weak UIView *BBTabIncomingView;

/// True while the real switch runs: the outer funnel calls the inner one, and the
/// inner must not animate a second time.
static BOOL BBTabSwapping = NO;

#pragma mark - Configuration

static BOOL BBTabEnabled(void) {
    return BBPreferenceBool(BBTabEnabledKey, YES);
}

static double BBTabDuration(void) {
    double duration = BBPreferenceDouble(BBTabDurationKey, BBTabDefaultDuration);
    return duration > BBTabMinimumDuration ? duration : BBTabDefaultDuration;
}

/// `"fadeSlide"` (default), `"fade"`, `"slide"` or `"none"`.
static NSString *BBTabStyle(void) {
    return BBPreferenceString(BBTabStyleKey, BBTabDefaultStyle);
}

#pragma mark - Transition

/// Tears down whatever the previous transition left on screen. Called before
/// every new one so the two can never overlap.
static void BBTabFlushInFlight(void) {
    UIView *ghost = BBTabGhostView;
    UIView *incoming = BBTabIncomingView;

    if (ghost) {
        [ghost removeFromSuperview];
        BBTabGhostView = nil;
    }
    if (incoming) {
        incoming.alpha = 1.0;
        incoming.transform = CGAffineTransformIdentity;
        BBTabIncomingView = nil;
    }
}

static BOOL BBTabShouldAnimate(UITabBarController *tabBarController, UIViewController *to) {
    if (BBTabSwapping || !BBTabEnabled() || !tabBarController.isViewLoaded) {
        return NO;
    }
    if (tabBarController.view.window == nil) {
        return NO; // onboarding / splash: nothing on screen to cross-fade yet
    }

    UIViewController *from = tabBarController.selectedViewController;
    return from != nil && to != nil && from != to;
}

/// Runs the real switch, then fades the outgoing content into the incoming tab.
static void BBTabSwap(UITabBarController *tabBarController, UIViewController *to,
                      void (^swap)(void)) {
    UIViewController *from = tabBarController.selectedViewController;
    UIView *container = [tabBarController valueForKey:@"transitionView"] ?: tabBarController.view;

    BBTabFlushInFlight();

    UIView *incoming = to.view; // load before fading, or the first frame is blank

    // The swap removes the old content immediately; the snapshot keeps it on
    // screen underneath so the two tabs actually cross-dissolve.
    UIView *ghost = nil;
    if (from.isViewLoaded && from.view.window && container.bounds.size.width > 0) {
        ghost = [from.view snapshotViewAfterScreenUpdates:NO];
    }

    BBTabSwapping = YES;
    swap();
    BBTabSwapping = NO;

    if (!incoming || !container) {
        BBLog(@"tab switch %@ -> %@: no incoming view, skipped", BBClassName(from),
              BBClassName(to));
        return;
    }

    NSString *style = BBTabStyle();
    BOOL fade = [style isEqualToString:@"fade"] || [style isEqualToString:@"fadeSlide"];
    BOOL slide = !UIAccessibilityIsReduceMotionEnabled() &&
                 ([style isEqualToString:@"slide"] || [style isEqualToString:@"fadeSlide"]);

    // Come in from the side the new tab sits on.
    NSArray<UIViewController *> *tabs = tabBarController.viewControllers ?: @[];
    NSInteger fromIndex = [tabs indexOfObject:from];
    NSInteger toIndex = [tabs indexOfObject:to];
    BOOL forward = (fromIndex == NSNotFound || toIndex == NSNotFound) ? YES : toIndex > fromIndex;
    CGFloat offset =
        slide ? (forward ? 1.0 : -1.0) * MAX(16.0, container.bounds.size.width * 0.05) : 0;

    BBLog(@"tab %ld -> %ld (%@, %.2fs)", (long)fromIndex, (long)toIndex, style, BBTabDuration());

    if (ghost) {
        ghost.frame = container.bounds;
        [container addSubview:ghost];
        BBTabGhostView = ghost;
    }

    if (fade) {
        incoming.alpha = 0.0;
    }
    if (slide) {
        incoming.transform = CGAffineTransformMakeTranslation(offset, 0);
    }
    BBTabIncomingView = incoming;

    [UIView animateWithDuration:BBTabDuration()
        delay:0
        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
        animations:^{
            ghost.alpha = 0.0;
            incoming.alpha = 1.0;
            incoming.transform = CGAffineTransformIdentity;
        }
        completion:^(BOOL finished) {
            if (BBTabGhostView == ghost) {
                [ghost removeFromSuperview];
                BBTabGhostView = nil;
            }
            if (BBTabIncomingView == incoming) {
                incoming.alpha = 1.0;
                incoming.transform = CGAffineTransformIdentity;
                BBTabIncomingView = nil;
            }
        }];
}

#pragma mark - Hooks

static void BBSwizzledSetSelectedViewController(UITabBarController *self, SEL _cmd,
                                                UIViewController *viewController) {
    if (!BBTabShouldAnimate(self, viewController)) {
        [self bb_setSelectedViewController:viewController];
        return;
    }

    BBTabSwap(self, viewController, ^{
        [self bb_setSelectedViewController:viewController];
    });
}

static void BBSwizzledSetSelectedViewControllerPerformUpdates(UITabBarController *self, SEL _cmd,
                                                              UIViewController *viewController,
                                                              BOOL performUpdates) {
    if (!BBTabShouldAnimate(self, viewController)) {
        [self bb_setSelectedViewController:viewController performUpdates:performUpdates];
        return;
    }

    BBTabSwap(self, viewController, ^{
        [self bb_setSelectedViewController:viewController performUpdates:performUpdates];
    });
}

#pragma mark - Installation

void BBInstallTabTransitions(void) {
    BBRegisterPreferenceDefaults(@{
        BBTabEnabledKey: @YES,
        BBTabDurationKey: @(BBTabDefaultDuration),
        BBTabStyleKey: BBTabDefaultStyle,
    });

    // `_setSelectedViewController:performUpdates:` is the inner funnel the public
    // setter delegates to; hooking both keeps the guard in BBTabShouldAnimate
    // from re-animating on the way back through.
    BBHookInstance(UITabBarController.class, NSSelectorFromString(@"_setSelectedViewController:"),
                   @selector(bb_setSelectedViewController:),
                   (IMP)BBSwizzledSetSelectedViewController);
    BBHookInstance(UITabBarController.class,
                   NSSelectorFromString(@"_setSelectedViewController:performUpdates:"),
                   @selector(bb_setSelectedViewController:performUpdates:),
                   (IMP)BBSwizzledSetSelectedViewControllerPerformUpdates);

    BBLog(@"tab transitions armed (%@, %.2fs)", BBTabStyle(), BBTabDuration());
}
