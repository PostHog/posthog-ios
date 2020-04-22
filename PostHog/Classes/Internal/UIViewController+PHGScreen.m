#import "UIViewController+PHGScreen.h"
#import <objc/runtime.h>
#import "PHGPostHog.h"
#import "PHGPostHogUtils.h"


@implementation UIViewController (PHGScreen)

+ (void)phg_swizzleViewDidAppear
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(viewDidAppear:);
        SEL swizzledSelector = @selector(phg_viewDidAppear:);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod =
            class_addMethod(class,
                            originalSelector,
                            method_getImplementation(swizzledMethod),
                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}


+ (UIViewController *)phg_topViewController
{
    UIViewController *root = [[PHGPostHog sharedPostHog] configuration].application.delegate.window.rootViewController;
    return [self phg_topViewController:root];
}

+ (UIViewController *)phg_topViewController:(UIViewController *)rootViewController
{
    UIViewController *presentedViewController = rootViewController.presentedViewController;
    if (presentedViewController != nil) {
        return [self phg_topViewController:presentedViewController];
    }

    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UIViewController *lastViewController = [[(UINavigationController *)rootViewController viewControllers] lastObject];
        return [self phg_topViewController:lastViewController];
    }

    return rootViewController;
}

- (void)phg_viewDidAppear:(BOOL)animated
{
    UIViewController *top = [[self class] phg_topViewController];
    if (!top) {
        PHGLog(@"Could not infer screen.");
        return;
    }

    NSString *name = [top title];
    if (!name || name.length == 0) {
        name = [[[top class] description] stringByReplacingOccurrencesOfString:@"ViewController" withString:@""];
        // Class name could be just "ViewController".
        if (name.length == 0) {
            PHGLog(@"Could not infer screen name.");
            name = @"Unknown";
        }
    }
    [[PHGPostHog sharedPostHog] screen:name properties:nil];

    [self phg_viewDidAppear:animated];
}

@end
