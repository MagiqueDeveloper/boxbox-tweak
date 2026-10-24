#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// Prefix used for every log line the dylib emits.
extern NSString *const BBLogTag;

/// Logs to os_log/NSLog with the BoxBox tag already applied.
void BBLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Exchanges two instance methods on `cls`, tolerating inherited implementations.
/// Safe to call from a constructor.
void BBSwizzle(Class cls, SEL original, SEL replacement);

/// Same, but for class methods (metaclass).
void BBSwizzleClass(Class cls, SEL original, SEL replacement);

/// Logs `-[Class selector]` pairs for every method on `cls` (handy for recon).
void BBDumpMethods(Class cls);

NS_ASSUME_NONNULL_END
