#import <UIKit/UIKit.h>


@interface UIViewController (PHGScreen)

+ (void)phg_swizzleViewDidAppear;
+ (UIViewController *)phg_topViewController;

@end
