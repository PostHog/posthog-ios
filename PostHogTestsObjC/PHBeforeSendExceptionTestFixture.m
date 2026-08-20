#import "PHBeforeSendExceptionTestFixture.h"

#import <objc/message.h>

@implementation PHBeforeSendExceptionTestFixture

+ (NSObject *)makeThrowingBox:(Class)boxClass {
    id block = ^id(__unused id event) {
        [NSException raise:@"PHBeforeSendTestException" format:@"Objective-C beforeSend failure"];
        return nil;
    };
    return ((id (*)(id, SEL, id))objc_msgSend)([boxClass alloc], NSSelectorFromString(@"block:"), block);
}

+ (BOOL)invokeWithoutException:(void (^)(void))block {
    @try {
        block();
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

+ (void)setBeforeSendBlocks:(NSArray *)blocks onConfig:(NSObject *)config {
    SEL selector = NSSelectorFromString(@"setBeforeSend:");
    ((void (*)(id, SEL, NSArray *))objc_msgSend)(config, selector, blocks);
}

@end
