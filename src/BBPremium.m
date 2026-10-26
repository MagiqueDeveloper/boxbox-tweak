//
//  BBPremium.m
//  BoxBox
//
//  Box Box persists paid-tier state in the shared app-group defaults so the
//  widget extension can read it, then re-derives it from RevenueCat and from its
//  own `api.boxboxclub.com/v4/user/profile` response. Forcing the reads — and
//  the writes, so the widgets see the same thing — unlocks every Ultra gate from
//  one place.
//
//  Hooking the *class* (rather than a suite) covers every instance and every
//  suite in one shot. Reads, writes and removals are all covered: a removed key
//  silently reverts to `false` for any process we are not injected into.
//

#import "BBPremium.h"

#import "BBLog.h"
#import "BBRuntime.h"

/// App group the host app and its extensions share.
static NSString *const BBPremiumSuite = @"group.club.boxbox.sharedDefaults";

/// Paid-tier flags the app consults, in the suite above.
static NSArray<NSString *> *BBPremiumKeys(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keys = @[
            @"Is_Pro_User",
            @"Is_Elite_User",
            @"Is_Ultra_User",
            @"Is_Select_User",
            @"Last_Known_Subscribed",
        ];
    });
    return keys;
}

static BOOL BBIsPremiumKey(NSString *key) {
    return [key isKindOfClass:NSString.class] && [BBPremiumKeys() containsObject:key];
}

/// Cached server response for `api.boxboxclub.com/v4/user/profile`. Its body is
/// `{"token":"<subscribed>|<plan>", ...}` — e.g. `"false|basic"` — so rewriting
/// both halves is enough to move the account to the top tier.
static BOOL BBIsSubscriptionKey(NSString *key) {
    return [key isKindOfClass:NSString.class] && [key containsString:@"subscription-v1"];
}

static NSData *BBUnlockedSubscriptionData(NSData *data) {
    if (![data isKindOfClass:NSData.class]) {
        return data;
    }

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!json) {
        return data;
    }

    for (NSString *plan in @[@"basic", @"pro", @"elite"]) {
        json = [json stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"|%@\"", plan]
                                               withString:@"|ultra\""];
    }
    json = [json stringByReplacingOccurrencesOfString:@"\"false|" withString:@"\"true|"];

    return [json dataUsingEncoding:NSUTF8StringEncoding] ?: data;
}

/// Logs the interesting keys exactly once each, so the gate can be confirmed
/// from the console instead of guessed — without spamming a hot path.
static void BBLogPremiumQuery(NSString *key, id value) {
    if (![key isKindOfClass:NSString.class]) {
        return;
    }
    if (![key containsString:@"Subscribed"] && ![key containsString:@"_User"] &&
        ![key containsString:@"subscription-v1"]) {
        return;
    }

    BBLogOnce([@"premium:" stringByAppendingString:key], @"defaults: %@ = %@", key,
              value ?: @"(nil)");
}

#pragma mark - Hooks

// The `bb_` selectors call through to the real implementations.
@interface NSUserDefaults (BBPremium)
- (BOOL)bb_boolForKey:(NSString *)key;
- (NSInteger)bb_integerForKey:(NSString *)key;
- (id)bb_objectForKey:(NSString *)key;
- (NSData *)bb_dataForKey:(NSString *)key;
- (void)bb_setBool:(BOOL)value forKey:(NSString *)key;
- (void)bb_setInteger:(NSInteger)value forKey:(NSString *)key;
- (void)bb_setObject:(id)value forKey:(NSString *)key;
- (void)bb_removeObjectForKey:(NSString *)key;
@end

static BOOL BBSwizzledBoolForKey(id self, SEL _cmd, NSString *key) {
    BOOL unlocked = BBIsPremiumKey(key) ? YES : [self bb_boolForKey:key];
    BBLogPremiumQuery(key, @(unlocked));
    return unlocked;
}

static NSInteger BBSwizzledIntegerForKey(id self, SEL _cmd, NSString *key) {
    NSInteger unlocked = BBIsPremiumKey(key) ? 1 : [self bb_integerForKey:key];
    BBLogPremiumQuery(key, @(unlocked));
    return unlocked;
}

static id BBSwizzledObjectForKey(id self, SEL _cmd, NSString *key) {
    if (BBIsPremiumKey(key)) {
        BBLogPremiumQuery(key, @YES);
        return @YES;
    }

    id value = [self bb_objectForKey:key];
    if (BBIsSubscriptionKey(key) && [value isKindOfClass:NSData.class]) {
        value = BBUnlockedSubscriptionData(value);
    }
    BBLogPremiumQuery(key, value);
    return value;
}

static NSData *BBSwizzledDataForKey(id self, SEL _cmd, NSString *key) {
    NSData *value = [self bb_dataForKey:key];
    return BBIsSubscriptionKey(key) ? BBUnlockedSubscriptionData(value) : value;
}

static void BBSwizzledSetBool(id self, SEL _cmd, BOOL value, NSString *key) {
    [self bb_setBool:(BBIsPremiumKey(key) ? YES : value) forKey:key];
}

static void BBSwizzledSetInteger(id self, SEL _cmd, NSInteger value, NSString *key) {
    [self bb_setInteger:(BBIsPremiumKey(key) ? 1 : value) forKey:key];
}

static void BBSwizzledSetObject(id self, SEL _cmd, id value, NSString *key) {
    [self bb_setObject:(BBIsPremiumKey(key) ? @YES : value) forKey:key];
}

/// A removed key would fall back to `false` for processes we are not injected
/// into (the widgets), so re-assert it after the real removal.
static void BBSwizzledRemoveObjectForKey(id self, SEL _cmd, NSString *key) {
    [self bb_removeObjectForKey:key];
    if (BBIsPremiumKey(key)) {
        [self bb_setBool:YES forKey:key];
    }
}

#pragma mark - Installation

void BBInstallPremiumUnlock(void) {
    Class defaults = NSUserDefaults.class;

    BBHookInstance(defaults, @selector(boolForKey:), @selector(bb_boolForKey:),
                   (IMP)BBSwizzledBoolForKey);
    BBHookInstance(defaults, @selector(integerForKey:), @selector(bb_integerForKey:),
                   (IMP)BBSwizzledIntegerForKey);
    BBHookInstance(defaults, @selector(objectForKey:), @selector(bb_objectForKey:),
                   (IMP)BBSwizzledObjectForKey);
    BBHookInstance(defaults, @selector(dataForKey:), @selector(bb_dataForKey:),
                   (IMP)BBSwizzledDataForKey);

    BBHookInstance(defaults, @selector(setBool:forKey:), @selector(bb_setBool:forKey:),
                   (IMP)BBSwizzledSetBool);
    BBHookInstance(defaults, @selector(setInteger:forKey:), @selector(bb_setInteger:forKey:),
                   (IMP)BBSwizzledSetInteger);
    BBHookInstance(defaults, @selector(setObject:forKey:), @selector(bb_setObject:forKey:),
                   (IMP)BBSwizzledSetObject);
    BBHookInstance(defaults, @selector(removeObjectForKey:), @selector(bb_removeObjectForKey:),
                   (IMP)BBSwizzledRemoveObjectForKey);

    BBLog(@"ultra unlock armed (%lu keys)", (unsigned long)BBPremiumKeys().count);
}

void BBSeedPremiumFlags(void) {
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:BBPremiumSuite];
    if (!shared) {
        BBLog(@"app-group defaults unavailable (%@)", BBPremiumSuite);
        return;
    }

    for (NSString *key in BBPremiumKeys()) {
        [shared setBool:YES forKey:key];
    }

    BBLog(@"seeded %@", BBPremiumSuite);
}
