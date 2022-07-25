#import <Foundation/Foundation.h>

@class PHGSession;


@interface PHGSession : NSObject

- (instancetype _Nonnull)init;
- (NSString *)getId;

- (void)checkAndSetSessionId:(NSTimeInterval)timestamp;
- (void)checkAndSetSessionId;

@end
