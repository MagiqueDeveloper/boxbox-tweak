//
//  BBPremium.h
//  BoxBox
//
//  Paid-tier unlock. See BBPremium.m for how the gate was located.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Hooks the `NSUserDefaults` class so every read, write and removal of a
/// paid-tier key reports the unlocked value, then arms the subscription-response
/// rewrite. Call once, from the constructor.
void BBInstallPremiumUnlock(void);

/// Writes the unlocked values into the shared app-group suite, so processes that
/// do *not* link this dylib (widgets, intents, the notification service
/// extension) read the same state off disk.
void BBSeedPremiumFlags(void);

NS_ASSUME_NONNULL_END
