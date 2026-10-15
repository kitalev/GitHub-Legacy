#import <UIKit/UIKit.h>

@interface GHProfileHeaderView : UIView

@property (nonatomic, copy) void (^onFollowersTapped)(void);
@property (nonatomic, copy) void (^onFollowingTapped)(void);
@property (nonatomic, copy) void (^onLinkTapped)(NSURL *url);

@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, copy) NSArray *socialAccounts;
@property (nonatomic, copy) NSDictionary *statusInfo;

- (void)configureWithUserInfo:(NSDictionary *)userInfo fallbackLogin:(NSString *)login loading:(BOOL)loading;
- (CGFloat)heightForWidth:(CGFloat)width;
- (void)applyTheme;

@end
