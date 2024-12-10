//
//  AppDelegate.m
//  PostHogObjCExample
//
//  Created by Manoel Aranda Neto on 23.10.23.
//

#import "AppDelegate.h"
@import PostHog;

@interface AppDelegate ()

@end

@implementation AppDelegate


- (void)receiveTestNotification {
    NSLog(@"received");
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(receiveTestNotification)
            name:PostHogSDK.didStartNotification
            object:nil];

    PostHogConfig *config = [[PostHogConfig alloc] apiKey:@"_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"];
    config.preloadFeatureFlags = YES;
    [[PostHogSDK shared] debug:YES];
    [[PostHogSDK shared] setup:config];
    
    NSString *event = @"theEvent";
    NSString *distinctId = @"theCustomDistinctId";
    NSDictionary *properties = @{@"source": @"iOS App", @"state": @"running"};
    NSDictionary *userProperties = @{@"userAlive": @YES, @"userAge": @50};
    NSDictionary *userPropertiesSetOnce = @{@"signupDate": @"2024-10-16"};
    NSDictionary *groups = @{@"groupName": @"developers"};

    [[PostHogSDK shared] captureWithEvent:event
                               distinctId:distinctId
                               properties:properties
                            userProperties:userProperties
                    userPropertiesSetOnce:userPropertiesSetOnce
                                   groups:groups
    ];
    
    [[PostHogSDK shared] captureWithEvent:event
                               properties:properties
                            userProperties:userProperties
                    userPropertiesSetOnce:userPropertiesSetOnce
    ];
    
    NSLog(@"getDistinctId: %@", [[PostHogSDK shared] getDistinctId]);
    NSLog(@"getAnonymousId: %@", [[PostHogSDK shared] getAnonymousId]);
    
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    props[@"state"] = @"running";

    NSMutableDictionary *userProps = [NSMutableDictionary dictionary];
    userProps[@"userAge"] = @50;
    
    NSMutableDictionary *userPropsOnce = [NSMutableDictionary dictionary];
    userPropsOnce[@"userAlive"] = @YES;
    
    NSMutableDictionary *groupProps = [NSMutableDictionary dictionary];
    groupProps[@"groupName"] = @"theGroup";

    NSMutableDictionary *registerProps = [NSMutableDictionary dictionary];
    props[@"loggedIn"] = @YES;
    [[PostHogSDK shared] registerProperties:registerProps];
    [[PostHogSDK shared] unregisterProperties:@"test2"];
    
    [[PostHogSDK shared] identify:@"my_new_id"];
    [[PostHogSDK shared] identifyWithDistinctId:@"my_new_id" userProperties:userProps];
    [[PostHogSDK shared] identifyWithDistinctId:@"my_new_id" userProperties:userProps userPropertiesSetOnce:userPropsOnce];
    
    
    [[PostHogSDK shared] optIn];
    [[PostHogSDK shared] optOut];
    NSLog(@"isOptOut: %d", [[PostHogSDK shared] isOptOut]);
    NSLog(@"isFeatureEnabled: %d", [[PostHogSDK shared] isFeatureEnabled:@"myFlag"]);
    NSLog(@"getFeatureFlag: %@", [[PostHogSDK shared] getFeatureFlag:@"myFlag"]);
    NSLog(@"getFeatureFlagPayload: %@", [[PostHogSDK shared] getFeatureFlagPayload:@"myFlag"]);
    
    [[PostHogSDK shared] reloadFeatureFlags];
    [[PostHogSDK shared] reloadFeatureFlagsWithCallback:^(){
        NSLog(@"called");
    }];
    
    [[PostHogSDK shared] capture:@"theEvent"];

    [[PostHogSDK shared] captureWithEvent:@"theEvent"
                               properties:props];

    [[PostHogSDK shared] captureWithEvent:@"theEvent"
                               properties:props
                          userProperties:userProps];

    [[PostHogSDK shared] captureWithEvent:@"theEvent"
                               properties:props
                          userProperties:userProps
                 userPropertiesSetOnce:userPropsOnce];

    [[PostHogSDK shared] captureWithEvent:@"theEvent"
                              distinctId:@"custom_distinct_id"
                               properties:props
                          userProperties:userProps
                 userPropertiesSetOnce:userPropsOnce
                                 groups:groupProps];

    [[PostHogSDK shared] captureWithEvent:@"theEvent"
                              distinctId:@"custom_distinct_id"
                               properties:props
                          userProperties:userProps
                 userPropertiesSetOnce:userPropsOnce
                                 groups:groupProps
                              timestamp:[NSDate date]];


    [[PostHogSDK shared] groupWithType:@"theType" key:@"theKey"];
    [[PostHogSDK shared] groupWithType:@"theType" key:@"theKey" groupProperties:groupProps];
    
    [[PostHogSDK shared] alias:@"theAlias"];
    
    [[PostHogSDK shared] screen:@"theScreen"];
    [[PostHogSDK shared] screenWithTitle:@"theScreen" properties:props];
    
    [[PostHogSDK shared] flush];
    [[PostHogSDK shared] reset];
    [[PostHogSDK shared] close];

    PostHogSDK *postHog = [PostHogSDK with:config];
    
    [postHog capture:@"theCapture"];
    
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
