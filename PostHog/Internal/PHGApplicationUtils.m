#import "PHGApplicationUtils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@implementation PHGApplicationUtils

+ (instancetype _Nonnull)sharedInstance
{
    static PHGApplicationUtils *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[PHGApplicationUtils alloc] init];
    });

    return sharedInstance;
}

- (UIApplication *)sharedApplication
{
    if (![UIApplication respondsToSelector:@selector(sharedApplication)])
        return nil;

    return [UIApplication performSelector:@selector(sharedApplication)];
}

- (NSArray<UIWindow *> *)windows
{
    UIApplication *app = [self sharedApplication];
    NSMutableArray *result = [NSMutableArray array];

    if (@available(iOS 13.0, tvOS 13.0, *)) {
        NSArray<UIScene *> *scenes = @[];
        
        if (app && [app respondsToSelector:@selector(connectedScenes)]) {
            scenes = [app.connectedScenes allObjects];
        }
        
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && scene.delegate &&
                [scene.delegate respondsToSelector:@selector(window)]) {
                id window = [scene.delegate performSelector:@selector(window)];
                if (window) {
                    [result addObject:window];
                }
            }
        }
    }

    if ([app.delegate respondsToSelector:@selector(window)] && app.delegate.window != nil) {
        [result addObject:app.delegate.window];
    }

    return result;
}

@end

