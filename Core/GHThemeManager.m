#import "GHThemeManager.h"
#import "GHIconRenderer.h"
#import "GHLocalization.h"

NSString * const kGHThemeDidChangeNotification = @"GHThemeDidChangeNotification";
static NSString * const kDarkModeDefaultsKey = @"GHDarkModeEnabled";

@interface UINavigationBar (GHBarTintCompat)
- (void)setBarTintColor:(UIColor *)color;
- (void)setTranslucent:(BOOL)translucent;
@end

@interface UITabBar (GHBarTintCompat)
- (void)setBarTintColor:(UIColor *)color;
- (void)setTranslucent:(BOOL)translucent;

- (void)setBarStyle:(UIBarStyle)barStyle;
@end

@implementation GHThemeManager

+ (instancetype)sharedManager {
    static GHThemeManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHThemeManager alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _darkModeEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kDarkModeDefaultsKey];
    }
    return self;
}

- (void)setDarkModeEnabled:(BOOL)darkModeEnabled {
    if (_darkModeEnabled == darkModeEnabled) return;
    _darkModeEnabled = darkModeEnabled;

    [[NSUserDefaults standardUserDefaults] setBool:darkModeEnabled forKey:kDarkModeDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self applyToWindow:[[UIApplication sharedApplication] keyWindow]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGHThemeDidChangeNotification object:self];
}

- (void)applyToWindow:(UIWindow *)window {

    BOOL supportsBarTintColor = [UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)];

    UIColor *barBackground = self.darkModeEnabled ? [UIColor colorWithWhite:0.11 alpha:1.0] : nil;

    UIColor *barButtonTint = supportsBarTintColor ? (self.darkModeEnabled ? GHTintColor() : nil) : barBackground;
    NSDictionary *titleAttrs = self.darkModeEnabled ? @{NSForegroundColorAttributeName: [UIColor whiteColor]} : nil;

    UIBarStyle barStyle = self.darkModeEnabled ? UIBarStyleBlack : UIBarStyleDefault;
    [[UINavigationBar appearance] setBarStyle:barStyle];

    BOOL supportsTabBarStyle = [UITabBar instancesRespondToSelector:@selector(setBarStyle:)];
    if (supportsTabBarStyle) {
        [[UITabBar appearance] setBarStyle:barStyle];
    }

    if (supportsBarTintColor) {
        [[UINavigationBar appearance] setBarTintColor:barBackground];
        [[UINavigationBar appearance] setTranslucent:NO];
        [[UITabBar appearance] setBarTintColor:barBackground];
        [[UITabBar appearance] setTranslucent:NO];
    }
    [[UINavigationBar appearance] setTintColor:barButtonTint];
    [[UINavigationBar appearance] setTitleTextAttributes:titleAttrs];
    [[UITabBar appearance] setTintColor:barButtonTint];

    void (^styleNav)(UINavigationController *) = ^(UINavigationController *nav) {
        nav.navigationBar.barStyle = barStyle;
        if (supportsBarTintColor) {
            nav.navigationBar.barTintColor = barBackground;
            nav.navigationBar.translucent = NO;
        }
        nav.navigationBar.tintColor = barButtonTint;
        nav.navigationBar.titleTextAttributes = titleAttrs;
    };

    UIViewController *root = window.rootViewController;
    if ([root isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBarController = (UITabBarController *)root;
        if (supportsTabBarStyle) {
            tabBarController.tabBar.barStyle = barStyle;
        }
        if (supportsBarTintColor) {
            tabBarController.tabBar.barTintColor = barBackground;
            tabBarController.tabBar.translucent = NO;
        }
        tabBarController.tabBar.tintColor = barButtonTint;
        for (id vc in tabBarController.viewControllers) {
            if ([vc isKindOfClass:[UINavigationController class]]) {
                styleNav(vc);
            }
        }
    } else if ([root isKindOfClass:[UINavigationController class]]) {
        styleNav((UINavigationController *)root);
    }

    UIStatusBarStyle statusBarStyle = self.darkModeEnabled ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
    [[UIApplication sharedApplication] setStatusBarStyle:statusBarStyle animated:YES];
}

@end

UIColor *GHBackgroundColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.07 alpha:1.0]
        : [UIColor colorWithWhite:0.93 alpha:1.0];
}

UIColor *GHWebViewBackgroundColor(void) {

    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0x12/255.0 green:0x12/255.0 blue:0x12/255.0 alpha:1.0]
        : [UIColor whiteColor];
}

UIColor *GHCellBackgroundColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.15 alpha:1.0]
        : [UIColor whiteColor];
}

UIColor *GHPrimaryTextColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor whiteColor]
        : [UIColor blackColor];
}

UIColor *GHSecondaryTextColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.6 alpha:1.0]
        : [UIColor grayColor];
}

UIColor *GHProfileHeaderSecondaryTextColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.8 alpha:1.0]
        : [UIColor grayColor];
}

UIColor *GHSeparatorColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.22 alpha:1.0]
        : [UIColor colorWithWhite:0.85 alpha:1.0];
}

UIColor *GHTintColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1.0]
        : nil;
}

UIColor *GHReactionAccentColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1.0]
        : [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
}

UIColor *GHReactionPillBackgroundColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.22 alpha:1.0]
        : [UIColor colorWithWhite:0.88 alpha:1.0];
}

UIColor *GHReactionPillBorderColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.32 alpha:1.0]
        : [UIColor colorWithWhite:0.78 alpha:1.0];
}

UIColor *GHReactionSelectedBackgroundColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:0.22]
        : [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:0.14];
}

UIActivityIndicatorViewStyle GHSpinnerStyle(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? UIActivityIndicatorViewStyleWhite
        : UIActivityIndicatorViewStyleGray;
}

UIColor *GHSettingsIconColor(void) {
    if ([GHThemeManager sharedManager].darkModeEnabled) {
        return [UIColor whiteColor];
    }

    BOOL supportsBarTintColor = [UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)];
    if (supportsBarTintColor) {

        return [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
    }
    return [UIColor whiteColor];
}

void GHApplyDisclosureIndicator(UITableViewCell *cell) {
    static UIImage *chevronImage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        chevronImage = [GHIconRenderer disclosureChevronWithColor:[UIColor colorWithWhite:0.62 alpha:1.0]
                                                                size:CGSizeMake(12, 20)];
    });
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = [[UIImageView alloc] initWithImage:chevronImage];
}

UIView *GHThemedSectionHeaderView(NSString *title) {

    if (title.length == 0) {
        UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 8)];

        spacer.backgroundColor = GHBackgroundColor();
        return spacer;
    }

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 30)];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    container.backgroundColor = GHBackgroundColor();

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, 6, 290, 20)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:17];
    label.backgroundColor = [UIColor clearColor];

    label.textColor = [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithWhite:0.6 alpha:1.0]
        : [UIColor colorWithWhite:0.3 alpha:1.0];
    [container addSubview:label];

    return container;
}

CGFloat GHThemedSectionHeaderHeight(NSString *title) {
    return title.length > 0 ? 30 : 8;
}

UIView *GHSignInPlaceholderView(NSString *message, CGFloat width, id target, SEL action) {
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 140)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];

    UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, width - 40, 44)];
    messageLabel.text = message;
    messageLabel.textColor = GHSecondaryTextColor();
    messageLabel.backgroundColor = [UIColor clearColor];
    messageLabel.font = [UIFont systemFontOfSize:15];
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.numberOfLines = 0;
    [header addSubview:messageLabel];

    UIButton *openSettingsButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    openSettingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [openSettingsButton setTitle:GHL(@"Открыть настройки") forState:UIControlStateNormal];
    [openSettingsButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [openSettingsButton sizeToFit];
    CGRect buttonFrame = openSettingsButton.frame;
    buttonFrame.origin = CGPointMake((width - buttonFrame.size.width) / 2.0, 84);
    openSettingsButton.frame = buttonFrame;
    [header addSubview:openSettingsButton];

    return header;
}
