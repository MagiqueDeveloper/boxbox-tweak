//
//  BBRuntime.h
//  BoxBox
//
//  Objective-C runtime helpers. Everything here is safe to call from a
//  constructor, before the app's own classes are linked.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// Exchanges two instance methods on `cls`, tolerating an inherited `original`.
///
/// `replacement` must already exist as a method on `cls` (i.e. it is a category
/// method you wrote). After the call, `original` runs your implementation and
/// `replacement` runs the old one, so your body calls `[self replacement]` to
/// reach the original.
///
/// No-op with a log line when `cls` is nil or either selector is missing.
void BBSwizzle(Class _Nullable cls, SEL original, SEL replacement);

/// Same as `BBSwizzle`, but for class methods (operates on `cls`'s metaclass).
void BBSwizzleClass(Class _Nullable cls, SEL original, SEL replacement);

/// Grafts `replacement` onto `cls` carrying `imp`, then exchanges it with the
/// existing `original`. This is the variant to use when you have a plain C
/// function instead of a category method — the usual case for hooks written in
/// this tweak.
///
/// `imp` must have the `self, _cmd, ...` signature of `original`. No-op with a
/// log line when `cls` is nil or does not respond to `original`.
void BBHookInstance(Class _Nullable cls, SEL original, SEL replacement, IMP imp);

/// Logs `-[Class selector]` for every method declared on `cls`. Recon aid.
void BBDumpMethods(Class _Nullable cls);

/// `NSStringFromClass(object_getClass(object))`, or `@"(nil)"` for nil. Unlike
/// `NSStringFromClass([obj class])` this reports the real dynamic class even for
/// objects that fake `-class`, which is what you want when naming a presented
/// controller.
NSString *BBClassName(id _Nullable object);

NS_ASSUME_NONNULL_END
