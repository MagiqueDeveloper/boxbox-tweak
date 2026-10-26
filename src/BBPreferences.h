//
//  BBPreferences.h
//  BoxBox
//
//  Typed reads of the tweak's own tunables.
//
//  Every feature in this dylib can be steered at runtime from the host app's
//  defaults, which makes feel-tuning a `defaults write` away instead of a
//  rebuild:
//
//      defaults write club.boxbox.widgets-ios BBTabTransitionStyle -string slide
//      defaults write club.boxbox.widgets-ios BBPaywallEnabled -bool NO
//
//  Because the dylib runs *inside* the app, `standardUserDefaults` already
//  resolves to the app's own domain — no suite is needed. The values are
//  registered in `registerDefaults:` so an unset key reads as its documented
//  default rather than zero.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Reads a `BOOL`, falling back when the key has never been set.
BOOL BBPreferenceBool(NSString *key, BOOL fallback);

/// Reads a `double`, falling back when the key is unset or holds a non-number.
double BBPreferenceDouble(NSString *key, double fallback);

/// Reads a lowercased, whitespace-trimmed string, falling back when the key is
/// unset, empty, or not a string. Use it for enum-style tunables.
NSString *BBPreferenceString(NSString *key, NSString *fallback);

/// Registers documented defaults for every tunable key, so the app's own
/// `NSUserDefaults` reads agree with ours before anything writes them.
void BBRegisterPreferenceDefaults(NSDictionary<NSString *, id> *defaults);

NS_ASSUME_NONNULL_END
