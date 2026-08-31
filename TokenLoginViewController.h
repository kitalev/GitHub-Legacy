#import <UIKit/UIKit.h>

@interface TokenLoginViewController : UIViewController

@property (nonatomic, copy) void (^onLoggedIn)(void);

@end
