#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

@interface PHNotificationDelegateTestFixture : NSObject <UNUserNotificationCenterDelegate>

@property(nonatomic, assign) NSUInteger invocationCount;
@property(nonatomic, assign, nullable) SEL receivedSelector;

- (void)invokeWithCompletionHandler:(void (^)(void))completionHandler
    NS_SWIFT_NAME(invoke(completionHandler:));

@end

@interface PHDirectNotificationDelegateTestFixture : PHNotificationDelegateTestFixture
@end

@interface PHDuplicateNotificationDelegateTestFixture : PHNotificationDelegateTestFixture
@end

@interface PHInheritedNotificationDelegateBaseTestFixture : PHNotificationDelegateTestFixture
@end

@interface PHInheritedNotificationDelegateTestFixture : PHInheritedNotificationDelegateBaseTestFixture
@end

@interface PHSuperclassFirstNotificationDelegateBaseTestFixture : PHNotificationDelegateTestFixture
@end

@interface PHSuperclassFirstNotificationDelegateTestFixture : PHSuperclassFirstNotificationDelegateBaseTestFixture
@end

@interface PHMissingNotificationDelegateTestFixture : PHNotificationDelegateTestFixture
@end

NS_ASSUME_NONNULL_END
