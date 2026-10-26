//
//  BBLog.h
//  BoxBox
//
//  Logging. NSLog is the only channel reachable from both a device (through
//  `idevicesyslog`) and the simulator (`xcrun simctl log show`), so every line
//  the tweak emits goes through here with a stable, greppable tag.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Prefix on every line the tweak writes, e.g. `[BoxBox] ultra unlock armed`.
/// Filter logs on this literal.
extern NSString *const BBLogTag;

/// `NSLog` with `BBLogTag` already applied.
void BBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Like `BBLog`, but emits at most once per unique `key` for the lifetime of the
/// process. Use it for per-key diagnostics on hot paths — a defaults read fires
/// thousands of times a session, and the first one is the only interesting one.
void BBLogOnce(NSString *key, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

NS_ASSUME_NONNULL_END
