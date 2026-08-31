#import <UIKit/UIKit.h>

extern NSString * const kGHAppDidEnterBackgroundNotification;
extern NSString * const kGHAppWillEnterForegroundNotification;

extern NSString * const kGHOpenReadmeStateKey;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITabBarController *tabBarController;

@property (nonatomic, strong) NSDictionary *pendingRestoreState;

@end
