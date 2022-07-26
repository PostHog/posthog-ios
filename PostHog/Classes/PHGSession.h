#import <Foundation/Foundation.h>
#import "PHGStorage.h"

@class PHGSession;


@interface PHGSession : NSObject

- (instancetype _Nonnull)initWithStorage:(id<PHGStorage>)fileStorage userDefaultsStorage:(id<PHGStorage>)userDefaultsStorage;
- (NSString *_Nullable)getId;

- (void)checkAndSetSessionId:(NSTimeInterval)timestamp;
- (void)checkAndSetSessionId;

@end
