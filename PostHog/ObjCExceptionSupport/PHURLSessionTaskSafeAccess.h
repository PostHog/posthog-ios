#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHURLSessionTaskSafeAccess : NSObject

+ (nullable NSURLRequest *)currentRequestFromTask:(NSURLSessionTask *)task NS_SWIFT_NAME(currentRequest(from:));
+ (BOOL)setCurrentRequest:(NSURLRequest *)request onTask:(NSURLSessionTask *)task key:(NSString *)key NS_SWIFT_NAME(setCurrentRequest(_:on:key:));

@end

NS_ASSUME_NONNULL_END
