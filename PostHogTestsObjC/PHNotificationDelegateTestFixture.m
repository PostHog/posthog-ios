#import "PHNotificationDelegateTestFixture.h"

#import <objc/message.h>

@implementation PHNotificationDelegateTestFixture

- (void)invokeWithCompletionHandler:(void (^)(void))completionHandler {
    SEL selector = @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:);
    UNUserNotificationCenter *center = (id)[NSObject new];
    UNNotificationResponse *response = (id)[NSObject new];
    ((void (*)(id, SEL, UNUserNotificationCenter *, UNNotificationResponse *, void (^)(void)))objc_msgSend)(
        self, selector, center, response, completionHandler);
}

@end

#define PH_IMPLEMENT_NOTIFICATION_RESPONSE()                                                                    \
    - (void)userNotificationCenter:(UNUserNotificationCenter *)center                                            \
        didReceiveNotificationResponse:(UNNotificationResponse *)response                                       \
                 withCompletionHandler:(void (^)(void))completionHandler {                                      \
        self.invocationCount += 1;                                                                               \
        self.receivedSelector = _cmd;                                                                            \
        completionHandler();                                                                                     \
    }

@implementation PHDirectNotificationDelegateTestFixture
PH_IMPLEMENT_NOTIFICATION_RESPONSE()
@end

@implementation PHDuplicateNotificationDelegateTestFixture
PH_IMPLEMENT_NOTIFICATION_RESPONSE()
@end

@implementation PHInheritedNotificationDelegateBaseTestFixture
PH_IMPLEMENT_NOTIFICATION_RESPONSE()
@end

@implementation PHInheritedNotificationDelegateTestFixture
@end

@implementation PHSuperclassFirstNotificationDelegateBaseTestFixture
PH_IMPLEMENT_NOTIFICATION_RESPONSE()
@end

@implementation PHSuperclassFirstNotificationDelegateTestFixture
@end

@implementation PHMissingNotificationDelegateTestFixture
@end
