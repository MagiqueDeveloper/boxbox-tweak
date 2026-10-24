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

#pragma mark - Entry point

// Called by dyld as soon as the dylib is mapped into the host process.
__attribute__((constructor))
static void BoxBoxInit(void) {
    @autoreleasepool {
        BBLog(@"loaded into %@ (pid %d, %@)",
              NSProcessInfo.processInfo.processName,
              getpid(),
              NSProcessInfo.processInfo.operatingSystemVersionString);

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
