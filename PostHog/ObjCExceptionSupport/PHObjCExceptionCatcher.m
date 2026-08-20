#import "PHObjCExceptionCatcher.h"

#import <objc/message.h>

typedef id _Nullable (^PHObjectTransformBlock)(id value);

@implementation PHObjCExceptionCatcher

+ (nullable id)invokeBlockFromBox:(id)box
                         withValue:(id)value
                       onException:(void (^)(NSException *exception))onException {
    @try {
        // The box types are generated from Swift in this target, so this file cannot import
        // PostHog-Swift.h. Resolve their @objc block accessor dynamically and invoke it here so
        // an NSException never unwinds through a Swift frame.
        PHObjectTransformBlock block = ((id (*)(id, SEL))objc_msgSend)(box, NSSelectorFromString(@"block"));
        return block(value);
    } @catch (NSException *exception) {
        onException(exception);
        return nil;
    }
}

@end
