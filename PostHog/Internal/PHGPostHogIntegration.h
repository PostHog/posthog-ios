#import <Foundation/Foundation.h>
#import "PHGHTTPClient.h"
#import "PHGIntegration.h"
#import "PHGStorage.h"

@class PHGIdentifyPayload;
@class PHGCapturePayload;
@class PHGScreenPayload;
@class PHGAliasPayload;
@class PHGGroupPayload;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PHGPostHogDidSendRequestNotification;
extern NSString *const PHGPostHogRequestDidSucceedNotification;
extern NSString *const PHGPostHogRequestDidFailNotification;


@interface PHGPostHogIntegration : NSObject <PHGIntegration>

@property (nonatomic, copy) NSString *distinctId;

- (id)initWithPostHog:(PHGPostHog *)posthog httpClient:(PHGHTTPClient *)httpClient fileStorage:(id<PHGStorage>)fileStorage userDefaultsStorage:(id<PHGStorage>)userDefaultsStorage;
- (NSDictionary *)staticContext;
- (NSDictionary *)liveContext;
- (void)saveDistinctId:(NSString *)distinctId;

- (NSDictionary *_Nonnull)getGroups;
- (void)saveGroup:(NSString *_Nonnull)groupType groupKey:(NSString *_Nonnull)groupKey;

- (NSArray *_Nonnull)getFeatureFlags;
- (NSDictionary *)getFeatureFlagsAndValues;
- (NSDictionary *)getFeatureFlagPayloads;
- (void)receivedFeatureFlags:(NSDictionary *)flags payloads:(NSDictionary *)payloads;

@end

NS_ASSUME_NONNULL_END
