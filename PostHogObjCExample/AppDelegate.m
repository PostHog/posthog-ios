//
//  AppDelegate.m
//  PostHogObjCExample
//
//  Created by Manoel Aranda Neto on 23.10.23.
//

#import "AppDelegate.h"
#import <PostHog/PostHog.h>

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.

    PostHogConfig *config = [[PostHogConfig alloc] apiKey:@"_6SG-F7I1vCuZ-HdJL3VZQqjBlaSb1_20hDPwqMNnGI"];
    config.preloadFeatureFlags = NO;
    [[PostHogSDK shared] debug:YES];
    [[PostHogSDK shared] setup:config];
    NSLog(@"getDistinctId: %@", [[PostHogSDK shared] getDistinctId]);
    NSLog(@"getAnonymousId: %@", [[PostHogSDK shared] getAnonymousId]);
    
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    props[@"test"] = @"testValue";
    props[@"test2"] = @"testValue2";
    [[PostHogSDK shared] register:props];
    [[PostHogSDK shared] unregister:@"test2"];
    [[PostHogSDK shared] identify:@"my_new_id"];
    [[PostHogSDK shared] flush];
    [[PostHogSDK shared] reset];
    
    
//    [[PostHogSDK shared] close];
    
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
