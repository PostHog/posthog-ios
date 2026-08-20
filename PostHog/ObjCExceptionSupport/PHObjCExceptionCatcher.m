#import "PHObjCExceptionCatcher.h"

#import <objc/message.h>

typedef id _Nullable (^PHObjectTransformBlock)(id value);

@implementation PHObjCExceptionCatcher

+ (nullable id)invokeBlockFromBox:(id)box
                         withValue:(id)value
                       onException:(void (^)(NSException *exception))onException {
    @try {
        PHObjectTransformBlock block = ((id (*)(id, SEL))objc_msgSend)(box, NSSelectorFromString(@"block"));
        return block(value);
    } @catch (NSException *exception) {
        onException(exception);
        return nil;
    }
}

@end
