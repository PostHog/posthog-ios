#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface PHGApplicationUtils : NSObject

+ (instancetype _Nonnull) sharedInstance;
@property (nonatomic, readonly, nullable) UIApplication *sharedApplication;
@property (nonatomic, readonly, nullable) NSArray<UIWindow *> *windows;

@end
