//
//  PHGSession.m
//  PostHog
//
//  Created by Eric Duong on 7/22/22.
//  Copyright © 2022 PostHog. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PHGSession.h"
#import "PHGPostHogUtils.h"
#import "PHGStorage.h"

static int const SESSION_CHANGE_THRESHOLD = 1800;

static NSString *const PHGSessionId = @"PHGSessionId";
static NSString *const kPHGSessionId = @"posthog.sessionId";

static NSString *const PHGSessionLastTimestamp = @"PHGSessionLastTimestamp";
static NSString *const kPHGSessionLastTimestamp = @"posthog.sessionlastTimestamp";

@interface PHGSession ()

@property (nonatomic, strong) id<PHGStorage> fileStorage;
@property (nonatomic, strong) id<PHGStorage> userDefaultsStorage;

@end

@implementation PHGSession

- (instancetype _Nonnull)initWithStorage:(id<PHGStorage>)fileStorage userDefaultsStorage:(id<PHGStorage>)userDefaultsStorage;
{
    if (self = [super init]) {
        self.fileStorage = fileStorage;
        self.userDefaultsStorage = userDefaultsStorage;
        
    }
    return self;
}

- (void)checkAndSetSessionId
{
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    [self checkAndSetSessionId:now];
}

- (void)checkAndSetSessionId:(NSTimeInterval)timestamp
{
    NSString *sessionId = [self getSessionId];
    NSTimeInterval sessionLastTimestamp = [self getSessionLastTimestamp];
    if (sessionId == nil || sessionLastTimestamp == 0 || fabs(timestamp - sessionLastTimestamp) > SESSION_CHANGE_THRESHOLD) {
        NSString *newSessionId = createUUIDString();
        [self saveSessionId:newSessionId sessionLastTimestamp:timestamp];
    }
}

- (void)saveSessionId:(NSString *)sessionId sessionLastTimestamp:(NSTimeInterval)sessionLastTimestamp
{
    
#if TARGET_OS_TV
    [self.userDefaultsStorage setString:sessionId forKey:PHGSessionId];
#else
    [self.fileStorage setString:sessionId forKey:kPHGSessionId];
#endif
    
    NSNumber* nsSessionLastTimestamp = [NSNumber numberWithDouble:sessionLastTimestamp];
#if TARGET_OS_TV
    [self.userDefaultsStorage setString:distinctId forKey:PHGSessionLastTimestamp];
#else
    [self.fileStorage setNumber:nsSessionLastTimestamp forKey:kPHGSessionLastTimestamp];
#endif
}

- (NSString *)getSessionId
{
#if TARGET_OS_TV
    return [[NSUserDefaults standardUserDefaults] valueForKey:PHGSessionId];
#else
    return [self.fileStorage stringForKey:kPHGSessionId];
#endif
}

- (NSTimeInterval)getSessionLastTimestamp
{
    NSNumber *timestamp;
#if TARGET_OS_TV
    timestamp = [[NSUserDefaults standardUserDefaults] numberForKey:PHGSessionLastTimestamp];
#else
    timestamp = [self.fileStorage numberForKey:kPHGSessionLastTimestamp];
#endif
    return [timestamp doubleValue];
}

- (NSString *)getId
{
    [self checkAndSetSessionId];
    return [self getSessionId];
}

- (void)resetSession
{
#if TARGET_OS_TV
        [self.userDefaultsStorage removeKey:PHGSessionId];
        [self.userDefaultsStorage removeKey:PHGSessionLastTimestamp];
#else
        [self.fileStorage removeKey:kPHGSessionId];
        [self.fileStorage removeKey:kPHGSessionLastTimestamp];
#endif
}

@end
