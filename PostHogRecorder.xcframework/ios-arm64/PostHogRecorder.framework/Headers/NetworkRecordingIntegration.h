NS_ASSUME_NONNULL_BEGIN

@protocol NetworkRecordingIntegrationResponder <NSObject>

- (void)urlSessionTaskResume:(NSURLSessionTask *)sessionTask;
- (void)urlSessionTask:(NSURLSessionTask *)sessionTask setState:(NSURLSessionTaskState)newState;

@end


@interface NetworkRecordingIntegration : NSObject

+ (void)swizzleURLSessionTask:(id<NetworkRecordingIntegrationResponder> _Nonnull)responder;

@end

NS_ASSUME_NONNULL_END
