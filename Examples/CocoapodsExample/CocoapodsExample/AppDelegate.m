#import <PostHog/PHGPostHog.h>
#import "AppDelegate.h"


@interface AppDelegate ()

@end

NSString *const POSTHOG_API_KEY = @"BrpS4SctoaCCsyjlnlun3OzyNJAafdlv__jUWaaJWXg";


@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [PHGPostHog debug:YES];
    PHGPostHogConfiguration *configuration = [PHGPostHogConfiguration configurationWithApiKey:POSTHOG_API_KEY host:@"https://app.posthog.com"];
    configuration.captureApplicationLifecycleEvents = YES;
    configuration.recordScreenViews = YES;
    configuration.flushAt = 1;
    [PHGPostHog setupWithConfiguration:configuration];
    [[PHGPostHog sharedPostHog] identify:@"Prateek" properties:nil options: @{@"$anon_distinct_id":@"test_anonymousId"}];
    [[PHGPostHog sharedPostHog] capture:@"Cocoapods Example Launched"];

    [[PHGPostHog sharedPostHog] group:@"some-group" groupKey:@"id:4" properties: @{@"company_name":@"Awesome Inc"}];

    [[PHGPostHog sharedPostHog] flush];
    NSLog(@"application:didFinishLaunchingWithOptions: %@", launchOptions);
    return YES;
}


- (void)applicationWillResignActive:(UIApplication *)application
{
    NSLog(@"applicationWillResignActive:");
}


- (void)applicationDidEnterBackground:(UIApplication *)application
{
    NSLog(@"applicationDidEnterBackground:");
}


- (void)applicationWillEnterForeground:(UIApplication *)application
{
    NSLog(@"applicationWillEnterForeground:");
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    NSLog(@"applicationDidBecomeActive:");
}


- (void)applicationWillTerminate:(UIApplication *)application
{
    NSLog(@"applicationWillTerminate:");
}

@end
