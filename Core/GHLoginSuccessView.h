#import <UIKit/UIKit.h>

@interface GHLoginSuccessView : UIView

@property (nonatomic, copy) void (^onDone)(void);

- (void)applyTheme;
- (void)presentForLogin:(NSString *)login avatarURL:(NSString *)avatarURL;

@end
