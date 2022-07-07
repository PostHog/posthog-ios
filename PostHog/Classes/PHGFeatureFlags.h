#import <Foundation/Foundation.h>

@class PHGPostHog;


@interface PHGFeatureFlags : NSObject

- (instancetype _Nonnull)initWithPostHog:(PHGPostHog *_Nonnull)posthog;

- (NSArray *)isFeatureEnabled:(NSString *)flagKey;

- (void)reloadFeatureFlags;

@end
