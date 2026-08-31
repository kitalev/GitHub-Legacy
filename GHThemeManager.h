#import <UIKit/UIKit.h>

extern NSString * const kGHThemeDidChangeNotification;

@interface GHThemeManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) BOOL darkModeEnabled;

- (void)applyToWindow:(UIWindow *)window;

@end

UIColor *GHBackgroundColor(void);
UIColor *GHCellBackgroundColor(void);

UIColor *GHWebViewBackgroundColor(void);
UIColor *GHPrimaryTextColor(void);
UIColor *GHSecondaryTextColor(void);
UIColor *GHProfileHeaderSecondaryTextColor(void);
UIColor *GHSeparatorColor(void);
UIColor *GHTintColor(void);
UIColor *GHReactionAccentColor(void);
UIColor *GHReactionPillBackgroundColor(void);
UIColor *GHReactionPillBorderColor(void);
UIColor *GHReactionSelectedBackgroundColor(void);
UIActivityIndicatorViewStyle GHSpinnerStyle(void);
UIColor *GHSettingsIconColor(void);

void GHApplyDisclosureIndicator(UITableViewCell *cell);

UIView *GHThemedSectionHeaderView(NSString *title);

CGFloat GHThemedSectionHeaderHeight(NSString *title);

UIView *GHSignInPlaceholderView(NSString *message, CGFloat width, id target, SEL action);
