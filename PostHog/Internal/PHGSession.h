#import <Foundation/Foundation.h>
#import "PHGStorage.h"

@class PHGSession;


@interface PHGSession : NSObject

- (instancetype _Nonnull)initWithStorage:(id<PHGStorage> _Nonnull)fileStorage userDefaultsStorage:(id<PHGStorage> _Nonnull)userDefaultsStorage;
- (NSString *_Nullable)getId;

- (void)checkAndSetSessionId:(NSTimeInterval)timestamp;
- (void)checkAndSetSessionId;
- (void)resetSession;

@end
