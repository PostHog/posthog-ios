#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHBeforeSendExceptionTestFixture : NSObject

+ (NSObject *)makeThrowingBox:(Class)boxClass;
+ (BOOL)invokeWithoutException:(void (^)(void))block;
+ (void)setBeforeSendBlocks:(NSArray *)blocks onConfig:(NSObject *)config
    NS_SWIFT_NAME(setBeforeSend(_:on:));

@end

NS_ASSUME_NONNULL_END
