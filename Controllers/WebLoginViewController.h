#import <UIKit/UIKit.h>

@interface WebLoginViewController : UIViewController

@property (nonatomic, strong) NSURL *startURL;
@property (nonatomic, assign) BOOL finishesOnSignIn;
@property (nonatomic, copy) void (^onSignedIn)(void);

@end
