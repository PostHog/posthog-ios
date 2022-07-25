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

static int const SESSION_CHANGE_THRESHOLD = 1800;

@interface PHGSession ()

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic) NSTimeInterval sessionStartTimestamp;

@end

@implementation PHGSession

- (instancetype _Nonnull)init
{
    if (self = [super init]) {
        self.sessionId = nil;
        self.sessionStartTimestamp = 0;
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
    NSLog(@"%f", timestamp);
    if (self.sessionId == nil || self.sessionStartTimestamp == 0 || fabs(timestamp - self.sessionStartTimestamp) > SESSION_CHANGE_THRESHOLD) {
        NSLog(@"%f", fabs(timestamp - self.sessionStartTimestamp));
        NSString *newSessionId = createUUIDString();
        self.sessionId = newSessionId;
        self.sessionStartTimestamp = timestamp;
    }
}

- (NSString *)getId
{
    [self checkAndSetSessionId];
    return self.sessionId;
}

@end
