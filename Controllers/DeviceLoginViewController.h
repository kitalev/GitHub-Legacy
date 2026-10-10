#import <UIKit/UIKit.h>

@interface DeviceLoginViewController : UIViewController

@property (nonatomic, copy) void (^onLoggedIn)(void);

@end
