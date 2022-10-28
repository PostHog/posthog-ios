//
//  PHGNotificationNames.h
//  
//

#import <Foundation/Foundation.h>

/**
 * NSNotification name, that is posted after integrations are loaded.
 */
extern NSString *_Nonnull PHGPostHogIntegrationDidStart;

/**
 * NSNotification name posted after feature flags have been successfully loaded.
 */
extern NSString *_Nonnull PHGPostHogFeatureFlagsDidLoadNotification;
