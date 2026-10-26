//
//  BBPreferences.m
//  BoxBox
//

#import "BBPreferences.h"

static NSUserDefaults *BBPreferences(void) {
    return NSUserDefaults.standardUserDefaults;
}

BOOL BBPreferenceBool(NSString *key, BOOL fallback) {
    NSUserDefaults *defaults = BBPreferences();
    return [defaults objectForKey:key] != nil ? [defaults boolForKey:key] : fallback;
}

double BBPreferenceDouble(NSString *key, double fallback) {
    NSUserDefaults *defaults = BBPreferences();
    id value = [defaults objectForKey:key];
    if (![value respondsToSelector:@selector(doubleValue)]) {
        return fallback;
    }

    double number = [value doubleValue];
    return isfinite(number) ? number : fallback;
}

NSString *BBPreferenceString(NSString *key, NSString *fallback) {
    id value = [BBPreferences() objectForKey:key];
    if (![value isKindOfClass:NSString.class]) {
        return fallback;
    }

    NSString *trimmed =
        [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed.lowercaseString : fallback;
}

void BBRegisterPreferenceDefaults(NSDictionary<NSString *, id> *defaults) {
    [BBPreferences() registerDefaults:defaults];
}
