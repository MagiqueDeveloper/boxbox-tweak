//
//  BBRuntime.m
//  BoxBox
//

#import "BBRuntime.h"

#import "BBLog.h"

#pragma mark - Swizzling

void BBHookInstance(Class cls, SEL original, SEL replacement, IMP imp) {
    if (!cls) {
        BBLog(@"cannot hook -%@: nil class", NSStringFromSelector(original));
        return;
    }

    Method existing = class_getInstanceMethod(cls, original);
    if (!existing) {
        BBLog(@"cannot hook %@ -%@: no such method", NSStringFromClass(cls),
              NSStringFromSelector(original));
        return;
    }

    // Add the replacement selector if the class does not already carry it;
    // otherwise overwrite the implementation left by an earlier hook.
    if (!class_addMethod(cls, replacement, imp, method_getTypeEncoding(existing))) {
        method_setImplementation(class_getInstanceMethod(cls, replacement), imp);
    }

    method_exchangeImplementations(existing, class_getInstanceMethod(cls, replacement));
}

void BBSwizzle(Class cls, SEL original, SEL replacement) {
    Method replacementMethod = cls ? class_getInstanceMethod(cls, replacement) : NULL;
    if (!replacementMethod) {
        BBLog(@"cannot swizzle %@: -%@ is not declared on the class",
              cls ? NSStringFromClass(cls) : @"(nil)", NSStringFromSelector(replacement));
        return;
    }

    // The two selectors share a signature, so the existing method's type
    // encoding is the right one for the grafted selector.
    BBHookInstance(cls, original, replacement, method_getImplementation(replacementMethod));
}

void BBSwizzleClass(Class cls, SEL original, SEL replacement) {
    if (!cls) {
        BBLog(@"cannot swizzle class method -%@: nil class", NSStringFromSelector(original));
        return;
    }
    BBSwizzle(object_getClass(cls), original, replacement);
}

#pragma mark - Recon

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

NSString *BBClassName(id object) {
    return object ? NSStringFromClass(object_getClass(object)) : @"(nil)";
}
