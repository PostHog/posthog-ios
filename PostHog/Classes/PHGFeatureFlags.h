#import <Foundation/Foundation.h>

@class PHGPostHog;


@interface PHGPayloadManager : NSObject

- (instancetype _Nonnull)initWithPostHog:(PHGPostHog *_Nonnull)posthog;

- (NSArray *)isFeatureEnabled:(NSString *)flagKey;

- (void)reloadFeatureFlags;

@end
