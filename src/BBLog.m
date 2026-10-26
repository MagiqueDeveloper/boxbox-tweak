//
//  BBLog.m
//  BoxBox
//

#import "BBLog.h"

NSString *const BBLogTag = @"[BoxBox]";

void BBLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"%@ %@", BBLogTag, message);
}

void BBLogOnce(NSString *key, NSString *format, ...) {
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        seen = [NSMutableSet set];
    });

    @synchronized(seen) {
        if (key.length == 0 || [seen containsObject:key]) {
            return;
        }
        [seen addObject:key];
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"%@ %@", BBLogTag, message);
}
