#import <UIKit/UIKit.h>

@interface DeviceLoginViewController : UIViewController

@property (nonatomic, copy) void (^onLoggedIn)(void);
@property (nonatomic, assign) BOOL opensInApp;

@end
