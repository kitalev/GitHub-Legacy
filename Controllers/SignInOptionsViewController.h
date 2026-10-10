#import <UIKit/UIKit.h>

@interface SignInOptionsViewController : UITableViewController

@property (nonatomic, copy) void (^onLoggedIn)(void);

@end
