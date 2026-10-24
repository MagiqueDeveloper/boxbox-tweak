#import "BoxBox.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <unistd.h>

NSString *const BBLogTag = @"[BoxBox]";

void BBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@ %@", BBLogTag, message);
}

static void BBSwizzleInstance(Class cls, SEL original, SEL replacement) {
    if (!cls) {
        BBLog(@"swizzle skipped: nil class for %@", NSStringFromSelector(original));
        return;
    }

    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        BBLog(@"swizzle failed on %@: -%@ <-> -%@",
              NSStringFromClass(cls),
              NSStringFromSelector(original),
              NSStringFromSelector(replacement));
        return;
    }

    BOOL added = class_addMethod(cls,
                                 original,
                                 method_getImplementation(replacementMethod),
                                 method_getTypeEncoding(replacementMethod));
    if (added) {
        // `original` was inherited; keep the old implementation under `replacement`.
        class_replaceMethod(cls,
                            replacement,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

void BBSwizzle(Class cls, SEL original, SEL replacement) {
    BBSwizzleInstance(cls, original, replacement);
}

void BBSwizzleClass(Class cls, SEL original, SEL replacement) {
    BBSwizzleInstance(object_getClass(cls), original, replacement);
}

void BBDumpMethods(Class cls) {
    if (!cls) {
        return;
    }

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BBLog(@"%@ has %u methods", NSStringFromClass(cls), count);
    for (unsigned int i = 0; i < count; i++) {
        BBLog(@"  -%@", NSStringFromSelector(method_getName(methods[i])));
    }
    free(methods);
}

#pragma mark - Ultra unlock

// Box Box persists paid-tier state in the shared app-group defaults so the
// widget extension can read it, then re-derives it from RevenueCat and its
// own `/v4/user/profile` response. Forcing the reads (and the writes, so the
// widgets see the same thing) unlocks every Ultra gate from one place.
static NSString *const BBPremiumSuite = @"group.club.boxbox.sharedDefaults";

static NSArray<NSString *> *BBPremiumKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
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

// Cached server response for api.boxboxclub.com/v4/user/profile. Its body is
// {"token":"<subscribed>|<plan>", ...} — e.g. "false|basic". Rewrite to ultra.
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
    json = [json stringByReplacingOccurrencesOfString:@"\"false|" withString:@"\"true|"];
    json = [json stringByReplacingOccurrencesOfString:@"|basic\"" withString:@"|ultra\""];
    json = [json stringByReplacingOccurrencesOfString:@"|pro\"" withString:@"|ultra\""];
    json = [json stringByReplacingOccurrencesOfString:@"|elite\"" withString:@"|ultra\""];
    return [json dataUsingEncoding:NSUTF8StringEncoding] ?: data;
}

// One-shot logging of the interesting keys so recon stays cheap on device.
static void BBLogQuery(NSString *key, id value) {
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    if (![key isKindOfClass:NSString.class]) {
        return;
    }
    if (![key containsString:@"Subscribed"] && ![key containsString:@"_User"] &&
        ![key containsString:@"subscription-v1"]) {
        return;
    }
    @synchronized (seen) {
        if ([seen containsObject:key]) {
            return;
        }
        [seen addObject:key];
        BBLog(@"defaults: %@ = %@", key, value ?: @"(nil)");
    }
}

@interface NSUserDefaults (BBHooks)
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
    BBLogQuery(key, @(unlocked));
    return unlocked;
}

static NSInteger BBSwizzledIntegerForKey(id self, SEL _cmd, NSString *key) {
    NSInteger unlocked = BBIsPremiumKey(key) ? 1 : [self bb_integerForKey:key];
    BBLogQuery(key, @(unlocked));
    return unlocked;
}

static id BBSwizzledObjectForKey(id self, SEL _cmd, NSString *key) {
    if (BBIsPremiumKey(key)) {
        BBLogQuery(key, @YES);
        return @YES;
    }
    id value = [self bb_objectForKey:key];
    if (BBIsSubscriptionKey(key) && [value isKindOfClass:NSData.class]) {
        value = BBUnlockedSubscriptionData(value);
    }
    BBLogQuery(key, value);
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

// A removed key would fall back to `false` for processes we are not injected
// into (the widgets), so re-assert it.
static void BBSwizzledRemoveObjectForKey(id self, SEL _cmd, NSString *key) {
    [self bb_removeObjectForKey:key];
    if (BBIsPremiumKey(key)) {
        [self bb_setBool:YES forKey:key];
    }
}

// Hooks a method that already exists somewhere on `cls` by grafting a fresh
// selector onto it, then exchanging the two implementations. `imp` must have
// the `self, _cmd, ...` signature of `original`.
static void BBHookInstance(Class cls, SEL original, SEL replacement, IMP imp) {
    if (!cls) {
        return;
    }
    Method existing = class_getInstanceMethod(cls, original);
    if (!existing) {
        BBLog(@"cannot hook %@ -%@ (missing)", NSStringFromClass(cls), NSStringFromSelector(original));
        return;
    }
    if (!class_addMethod(cls, replacement, imp, method_getTypeEncoding(existing))) {
        method_setImplementation(class_getInstanceMethod(cls, replacement), imp);
    }
    method_exchangeImplementations(existing, class_getInstanceMethod(cls, replacement));
}

static void BBInstallUltraUnlock(void) {
    Class defaults = NSUserDefaults.class;

    BBHookInstance(defaults, @selector(boolForKey:), @selector(bb_boolForKey:), (IMP)BBSwizzledBoolForKey);
    BBHookInstance(defaults, @selector(integerForKey:), @selector(bb_integerForKey:), (IMP)BBSwizzledIntegerForKey);
    BBHookInstance(defaults, @selector(objectForKey:), @selector(bb_objectForKey:), (IMP)BBSwizzledObjectForKey);
    BBHookInstance(defaults, @selector(dataForKey:), @selector(bb_dataForKey:), (IMP)BBSwizzledDataForKey);

    BBHookInstance(defaults, @selector(setBool:forKey:), @selector(bb_setBool:forKey:), (IMP)BBSwizzledSetBool);
    BBHookInstance(defaults, @selector(setInteger:forKey:), @selector(bb_setInteger:forKey:), (IMP)BBSwizzledSetInteger);
    BBHookInstance(defaults, @selector(setObject:forKey:), @selector(bb_setObject:forKey:), (IMP)BBSwizzledSetObject);
    BBHookInstance(defaults, @selector(removeObjectForKey:), @selector(bb_removeObjectForKey:), (IMP)BBSwizzledRemoveObjectForKey);

    BBLog(@"ultra unlock armed (%lu keys)", (unsigned long)BBPremiumKeys().count);
}

// Seed the shared suite so the widget extension (which does not link us) sees
// the same unlocked state.
static void BBSeedPremiumFlags(void) {
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

#pragma mark - Entry point

// Called by dyld as soon as the dylib is mapped into the host process.
__attribute__((constructor))
static void BoxBoxInit(void) {
    @autoreleasepool {
        BBLog(@"loaded into %@ (pid %d, %@)",
              NSProcessInfo.processInfo.processName,
              getpid(),
              NSProcessInfo.processInfo.operatingSystemVersionString);

        BBInstallUltraUnlock();
        BBSeedPremiumFlags();

        // Install your hooks here, e.g.
        //
        //     Class target = NSClassFromString(@"SomeViewController");
        //     BBSwizzle(target, @selector(viewDidLoad), @selector(bb_viewDidLoad));
        //
        // Note: NSClassFromString() returns nil until the class is linked in.
        // If that bites you, swizzle lazily from +load of a category or use a
        // weak-linked framework's notification instead.
    }
}
