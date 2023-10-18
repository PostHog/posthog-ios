#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "PHGPostHogUtils.h"
#import "PHGPostHog.h"
#import "UIViewController+PHGScreen.h"
#import "PHGStoreKitCapturer.h"
#import "PHGStorage.h"
#import "PHGMiddleware.h"
#import "PHGPayloadManager.h"
#import "PHGUtils.h"
#import "PHGPayload.h"
#import "PHGIdentifyPayload.h"
#import "PHGCapturePayload.h"
#import "PHGScreenPayload.h"
#import "PHGAliasPayload.h"
#import "PHGGroupPayload.h"

static PHGPostHog *__sharedInstance = nil;


@interface PHGPostHog ()

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, strong) PHGPostHogConfiguration *configuration;
@property (nonatomic, strong) PHGStoreKitCapturer *storeKitCapturer;
@property (nonatomic, strong) PHGPayloadManager *payloadManager;
@property (nonatomic, strong) PHGMiddlewareRunner *runner;

@end


@implementation PHGPostHog

+ (void)setupWithConfiguration:(PHGPostHogConfiguration *)configuration
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __sharedInstance = [[self alloc] initWithConfiguration:configuration];
    });
}

- (instancetype)initWithConfiguration:(PHGPostHogConfiguration *)configuration
{
    NSCParameterAssert(configuration != nil);

    if (self = [self init]) {
        self.configuration = configuration;
        self.enabled = YES;

        // In swift this would not have been OK... But hey.. It's objc
        // TODO: Figure out if this is really the best way to do things here.
        self.payloadManager = [[PHGPayloadManager alloc] initWithPostHog:self];

        self.runner = [[PHGMiddlewareRunner alloc] initWithMiddlewares:
                                                       [configuration.middlewares ?: @[] arrayByAddingObject:self.payloadManager]];

        // Attach to application state change hooks
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

        // Pass through for application state change events
        id<PHGApplicationProtocol> application = configuration.application;
        if (application) {
            for (NSString *name in @[ UIApplicationDidEnterBackgroundNotification,
                                      UIApplicationDidFinishLaunchingNotification,
                                      UIApplicationWillEnterForegroundNotification,
                                      UIApplicationWillTerminateNotification,
                                      UIApplicationWillResignActiveNotification,
                                      UIApplicationDidBecomeActiveNotification ]) {
                [nc addObserver:self selector:@selector(handleAppStateNotification:) name:name object:application];
            }
        }

        if (configuration.recordScreenViews) {
            [UIViewController phg_swizzleViewDidAppear];
        }
        if (configuration.captureInAppPurchases) {
            _storeKitCapturer = [PHGStoreKitCapturer captureTransactionsForPostHog:self];
        }

#if !TARGET_OS_TV
        if (configuration.capturePushNotifications && configuration.launchOptions) {
            NSDictionary *remoteNotification = configuration.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
            if (remoteNotification) {
                [self capturePushNotification:remoteNotification fromLaunch:YES];
            }
        }
#endif
        
        if (configuration.preloadFeatureFlags) {
            [self reloadFeatureFlags];
        }
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -

NSString *const PHGVersionKey = @"PHGVersionKey";
NSString *const PHGBuildKeyV1 = @"PHGBuildKey";
NSString *const PHGBuildKeyV2 = @"PHGBuildKeyV2";

- (void)handleAppStateNotification:(NSNotification *)note
{
    PHGApplicationLifecyclePayload *payload = [[PHGApplicationLifecyclePayload alloc] init];
    payload.notificationName = note.name;
    [self run:PHGEventTypeApplicationLifecycle payload:payload callback:nil];

    if ([note.name isEqualToString:UIApplicationDidFinishLaunchingNotification]) {
        [self _applicationDidFinishLaunchingWithOptions:note.userInfo];
    } else if ([note.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        [self _applicationWillEnterForeground];
    } else if ([note.name isEqualToString: UIApplicationDidEnterBackgroundNotification]) {
      [self _applicationDidEnterBackground];
    }
}

- (void)_applicationDidFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    if (!self.configuration.captureApplicationLifecycleEvents) {
        return;
    }
    // Previously PHGBuildKey was stored an integer. This was incorrect because the CFBundleVersion
    // can be a string. This migrates PHGBuildKey to be stored as a string.
    NSInteger previousBuildV1 = [[NSUserDefaults standardUserDefaults] integerForKey:PHGBuildKeyV1];
    if (previousBuildV1) {
        [[NSUserDefaults standardUserDefaults] setObject:[@(previousBuildV1) stringValue] forKey:PHGBuildKeyV2];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PHGBuildKeyV1];
    }

    NSString *previousVersion = [[NSUserDefaults standardUserDefaults] stringForKey:PHGVersionKey];
    NSString *previousBuildV2 = [[NSUserDefaults standardUserDefaults] stringForKey:PHGBuildKeyV2];

    NSString *currentVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
    NSString *currentBuild = [[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"];

    if (!previousBuildV2) {
        [self capture:@"Application Installed" properties:@{
            @"version" : currentVersion ?: @"",
            @"build" : currentBuild ?: @"",
        }];
    } else if (![currentBuild isEqualToString:previousBuildV2]) {
        [self capture:@"Application Updated" properties:@{
            @"previous_version" : previousVersion ?: @"",
            @"previous_build" : previousBuildV2 ?: @"",
            @"version" : currentVersion ?: @"",
            @"build" : currentBuild ?: @"",
        }];
    }

    [self capture:@"Application Opened" properties:@{
        @"from_background" : @NO,
        @"version" : currentVersion ?: @"",
        @"build" : currentBuild ?: @"",
        @"referring_application" : launchOptions[UIApplicationLaunchOptionsSourceApplicationKey] ?: @"",
        @"url" : launchOptions[UIApplicationLaunchOptionsURLKey] ?: @"",
    }];


    [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:PHGVersionKey];
    [[NSUserDefaults standardUserDefaults] setObject:currentBuild forKey:PHGBuildKeyV2];

    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)_applicationWillEnterForeground
{
    if (!self.configuration.captureApplicationLifecycleEvents) {
        return;
    }
    [self capture:@"Application Opened" properties:@{
        @"from_background" : @YES,
    }];
}

- (void)_applicationDidEnterBackground
{
  if (!self.configuration.captureApplicationLifecycleEvents) {
    return;
  }
  [self capture: @"Application Backgrounded"];
}


#pragma mark - Public API

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%p:%@, %@>", self, [self class], [self dictionaryWithValuesForKeys:@[ @"configuration" ]]];
}

#pragma mark - Identify

- (void)identify:(NSString *)distinctId
{
    [self identify:distinctId properties:nil options:nil];
}

- (void)identify:(NSString *)distinctId properties:(NSDictionary *)properties
{
    [self identify:distinctId properties:properties options:nil];
}

- (void)identify:(NSString *)distinctId properties:(NSDictionary *)properties options:(NSDictionary *)options
{
    NSCAssert2(distinctId.length > 0 || properties.count > 0, @"either distinctId (%@) or properties (%@) must be provided.", distinctId, properties);
    
    NSString *anonId = [options objectForKey:@"$anon_distinct_id"];
    if (anonId == nil) {
        anonId = [self getAnonymousId];
    }

    PHGIdentifyPayload *payload = [[PHGIdentifyPayload alloc] initWithDistinctId:distinctId
                                                                     anonymousId:anonId
                                                                      properties:properties];
    [self run:PHGEventTypeIdentify payload:payload callback:nil];
}

#pragma mark - Capture

- (void)capture:(NSString *)event
{
    [self capture:event properties:nil];
}

- (void)capture:(NSString *)event properties:(NSDictionary *)properties
{
    NSCAssert1(event.length > 0, @"event (%@) must not be empty.", event);
    PHGCapturePayload * payload = [[PHGCapturePayload alloc] initWithEvent:event
                                                                properties:PHGCoerceDictionary(properties)];
    [self run:PHGEventTypeCapture payload:payload callback:nil];
}

#pragma mark - Screen

- (void)screen:(NSString *)screenTitle
{
    [self screen:screenTitle properties:nil];
}

- (void)screen:(NSString *)screenTitle properties:(NSDictionary *)properties
{
    NSCAssert1(screenTitle.length > 0, @"screen name (%@) must not be empty.", screenTitle);
    PHGScreenPayload *payload = [[PHGScreenPayload alloc] initWithName:screenTitle
                                                            properties:PHGCoerceDictionary(properties)];
    [self run:PHGEventTypeScreen payload: payload callback:nil];
}

#pragma mark - Alias

- (void)alias:(NSString *)alias
{
    PHGAliasPayload *payload = [[PHGAliasPayload alloc] initWithAlias:alias];
    [self run:PHGEventTypeAlias payload:payload callback:nil];
}

#pragma mark - Group

- (void)group:(NSString *_Nonnull)groupType groupKey:(NSString *_Nonnull)groupKey
{
    [self group:groupType groupKey:groupKey properties:nil];
}

- (void)group:(NSString *_Nonnull)groupType groupKey:(NSString *_Nonnull)groupKey properties:(NSDictionary *)properties
{
    NSDictionary *currentGroups = [self.payloadManager getGroups];
    
//    TODO: set groups as super property
    [self.payloadManager saveGroup:groupType groupKey:groupKey];

    PHGGroupPayload *payload = [[PHGGroupPayload alloc] initWithType:groupType
                                                            groupKey:groupKey
                                                          properties:PHGCoerceDictionary(properties)];
    [self run:PHGEventTypeGroup payload: payload callback:nil];
    
    NSString *possibleGroupKey = [currentGroups objectForKey:groupType];

    if (![possibleGroupKey isEqualToString:groupKey]){
        [self reloadFeatureFlags];
    }
}

- (id)getFeatureFlag:(NSString *)flagKey
{
    return [self getFeatureFlag:flagKey options:nil];
}

- (id)getFeatureFlag:(NSString *)flagKey options:(NSDictionary *)options
{
    NSDictionary *variants = [self.payloadManager getFlagVariants];
    id variantValue = [variants valueForKey:flagKey];

    id send_event = [options valueForKey:@"send_event"];

    if (send_event == nil || [send_event boolValue] != false) {
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];
        [properties setValue:flagKey forKey:@"$feature_flag"];
        [properties setValue:variantValue forKey:@"$feature_flag_response"];
        
        PHGCapturePayload *payload = [[PHGCapturePayload alloc] initWithEvent:@"$feature_flag_called"
                                                                   properties:PHGCoerceDictionary(properties)];
        [self run:PHGEventTypeCapture payload:payload callback:nil];
    }

    return variantValue;
}

- (bool)isFeatureEnabled:(NSString *)flagKey
{
    return [self isFeatureEnabled:flagKey options:nil];
}

- (bool)isFeatureEnabled:(NSString *)flagKey options:(NSDictionary *)options
{
    NSDictionary *flags = [self.payloadManager getFlagVariants];

    bool isFlagEnabled = true;
    id value = [flags valueForKey:flagKey];
    
    if (value != nil) {
        if ([value isKindOfClass:[NSNumber class]]) {
            isFlagEnabled = [value boolValue];
        }
    } else {
        isFlagEnabled = false;
    }
    
    id send_event = [options valueForKey:@"send_event"];
    
    if (send_event == nil || [send_event boolValue] != false) {
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];

        [properties setValue:flagKey forKey:@"$feature_flag"];
        [properties setValue:@(isFlagEnabled) forKey:@"$feature_flag_response"];
        PHGCapturePayload *payload = [[PHGCapturePayload alloc] initWithEvent:@"$feature_flag_called"
                                                                   properties:PHGCoerceDictionary(properties)];
        [self run:PHGEventTypeCapture payload: payload callback:nil];
    }
    
    return isFlagEnabled;
}

- (NSString *)getFeatureFlagStringPayload:(NSString *)flagKey defaultValue:(NSString *)defaultValue
{
    NSDictionary *payloads = [self.payloadManager getFeatureFlagPayloads];
    id payload = [payloads valueForKey:flagKey];
    
    if( payload == NULL ){
        return defaultValue;
    }
    
    if ([payload isKindOfClass:[NSString class]]) {
        return payload;
    } else {
        NSLog(@"[Posthog]: Could not retrieve value of type: NSString");
        return defaultValue;
    }
}

- (NSInteger)getFeatureFlagIntegerPayload:(NSString *)flagKey defaultValue:(NSInteger)defaultValue
{
    NSDictionary *payloads = [self.payloadManager getFeatureFlagPayloads];
    id payload = [payloads objectForKey:flagKey];
    
    if( payload == NULL ){
        return defaultValue;
    }
    
    if ([payload isKindOfClass:[NSNumber class]]) {
        return [payload integerValue];
    } else {
        NSLog(@"[Posthog]: Could not retrieve value of type: NSInteger");
        return defaultValue;
    }
}

- (double)getFeatureFlagDoublePayload:(NSString *)flagKey defaultValue:(double)defaultValue
{
    NSDictionary *payloads = [self.payloadManager getFeatureFlagPayloads];
    id payload = [payloads objectForKey:flagKey];
    
    if( payload == NULL ){
        return defaultValue;
    }
    
    if ([payload isKindOfClass:[NSNumber class]]) {
        return [payload doubleValue];
    } else {
        NSLog(@"[Posthog]: Could not retrieve value of type: double");
        return defaultValue;
    }

}

- (NSDictionary *)getFeatureFlagDictionaryPayload:(NSString *)flagKey defaultValue:(NSDictionary *)defaultValue
{
    NSDictionary *payloads = [self.payloadManager getFeatureFlagPayloads];
    id payload = [payloads objectForKey:flagKey];
    
    if( payload == NULL ){
        return defaultValue;
    }
    
    if ([payload isKindOfClass:[NSDictionary class]]) {
        NSDictionary* newDict = (NSDictionary*)payload;
        return newDict;
    } else {
        NSLog(@"[Posthog]: Could not retrieve value of type: NSDictionary");
        return defaultValue;
    }
}

- (NSArray *)getFeatureFlagArrayPayload:(NSString *)flagKey defaultValue:(NSArray *)defaultValue
{
    NSDictionary *payloads = [self.payloadManager getFeatureFlagPayloads];
    id payload = [payloads objectForKey:flagKey];
    
    if( payload == NULL ){
        return defaultValue;
    }
    
    if ([payload isKindOfClass:[NSArray class]]) {
        NSArray* newDict = (NSArray*)payload;
        return newDict;
    } else {
        NSLog(@"[Posthog]: Could not retrieve value of type: NSArray");
        return defaultValue;
    }
}

- (void)reloadFeatureFlags
{
    [self run:PHGEventTypeReloadFeatureFlags payload:nil callback:nil];
}

- (void)reloadFeatureFlagsWithCallback:(void(^)(void))callback
{
    [self run:PHGEventTypeReloadFeatureFlags payload:nil callback:^(BOOL earlyExit, NSArray<id<PHGMiddleware>> * _Nonnull remainingMiddlewares) {
        callback();
    }];
}

- (void)capturePushNotification:(NSDictionary *)properties fromLaunch:(BOOL)launch
{
    if (launch) {
        [self capture:@"Push Notification Tapped" properties:properties];
    } else {
        [self capture:@"Push Notification Received" properties:properties];
    }
}

- (void)receivedRemoteNotification:(NSDictionary *)userInfo
{
    if (self.configuration.capturePushNotifications) {
        [self capturePushNotification:userInfo fromLaunch:NO];
    }
    PHGRemoteNotificationPayload *payload = [[PHGRemoteNotificationPayload alloc] init];
    payload.userInfo = userInfo;
    [self run:PHGEventTypeReceivedRemoteNotification payload:payload callback:nil];
}

- (void)failedToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    PHGRemoteNotificationPayload *payload = [[PHGRemoteNotificationPayload alloc] init];
    payload.error = error;
    [self run:PHGEventTypeFailedToRegisterForRemoteNotifications payload:payload callback:nil];
}

- (void)registeredForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    NSParameterAssert(deviceToken != nil);
    PHGRemoteNotificationPayload *payload = [[PHGRemoteNotificationPayload alloc] init];
    payload.deviceToken = deviceToken;
    [self run:PHGEventTypeRegisteredForRemoteNotifications payload:payload callback:nil];
}

- (void)handleActionWithIdentifier:(NSString *)identifier forRemoteNotification:(NSDictionary *)userInfo
{
    PHGRemoteNotificationPayload *payload = [[PHGRemoteNotificationPayload alloc] init];
    payload.actionIdentifier = identifier;
    payload.userInfo = userInfo;
    [self run:PHGEventTypeHandleActionWithForRemoteNotification payload:payload callback:nil];
}

- (void)continueUserActivity:(NSUserActivity *)activity
{
    PHGContinueUserActivityPayload *payload = [[PHGContinueUserActivityPayload alloc] init];
    payload.activity = activity;
    [self run:PHGEventTypeContinueUserActivity payload:payload callback:nil];

    if (!self.configuration.captureDeepLinks) {
        return;
    }

    if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithCapacity:activity.userInfo.count + 2];
        [properties addEntriesFromDictionary:activity.userInfo];
        properties[@"url"] = activity.webpageURL.absoluteString;
        properties[@"title"] = activity.title ?: @"";
        properties = [PHGUtils traverseJSON:properties
                      andReplaceWithFilters:self.configuration.payloadFilters];
        [self capture:@"Deep Link Opened" properties:[properties copy]];
    }
}

- (void)openURL:(NSURL *)url options:(NSDictionary *)options
{
    PHGOpenURLPayload *payload = [[PHGOpenURLPayload alloc] init];
    payload.url = [NSURL URLWithString:[PHGUtils traverseJSON:url.absoluteString
                                        andReplaceWithFilters:self.configuration.payloadFilters]];
    payload.options = options;
    [self run:PHGEventTypeOpenURL payload:payload callback:nil];

    if (!self.configuration.captureDeepLinks) {
        return;
    }

    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithCapacity:options.count + 2];
    [properties addEntriesFromDictionary:options];
    properties[@"url"] = url.absoluteString;
    properties = [PHGUtils traverseJSON:properties
                  andReplaceWithFilters:self.configuration.payloadFilters];
    [self capture:@"Deep Link Opened" properties:[properties copy]];
}

- (void)reset
{
    [self run:PHGEventTypeReset payload:nil callback:nil];
}

- (void)flush
{
    [self run:PHGEventTypeFlush payload:nil callback:nil];
}

- (void)enable
{
    _enabled = YES;
}

- (void)disable
{
    _enabled = NO;
}

- (NSString *)getAnonymousId
{
    return [self.payloadManager getAnonymousId];
}

#pragma mark - Class Methods

+ (instancetype)sharedPostHog
{
    NSCAssert(__sharedInstance != nil, @"library must be initialized before calling this method.");
    return __sharedInstance;
}

+ (void)debug:(BOOL)showDebugLogs
{
    PHGSetShowDebugLogs(showDebugLogs);
}

+ (NSString *)version
{
    // this has to match the actual version, NOT what's in info.plist
    // because Apple only accepts X.X.X as versions in the review process.
    return @"2.1.0";
}

#pragma mark - Helpers

- (void)run:(PHGEventType)eventType payload:(PHGPayload *)payload callback:(RunMiddlewaresCallback _Nullable)callback
{
    if (!self.enabled) {
        return;
    }
    PHGContext *context = [[[PHGContext alloc] initWithPostHog:self] modify:^(id<PHGMutableContext> _Nonnull ctx) {
        ctx.eventType = eventType;
        ctx.payload = payload;
    }];
    [self.runner run:context callback:callback];
}

@end
