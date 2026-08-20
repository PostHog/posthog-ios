#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHObjCExceptionCatcher : NSObject

+ (nullable id)invokeBlockFromBox:(id)box
                         withValue:(id)value
                       onException:(void (^)(NSException *exception))onException
    NS_SWIFT_NAME(invokeBlock(from:with:onException:));

@end

NS_ASSUME_NONNULL_END
