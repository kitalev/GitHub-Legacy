#import "GHThemeManager.h"
#import "GHCompat.h"
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
    NSDictionary *titleAttrs = self.darkModeEnabled ? @{GHForegroundColorAttributeName(): [UIColor whiteColor]} : nil;

    UIBarStyle barStyle = self.darkModeEnabled ? UIBarStyleBlack : UIBarStyleDefault;
    [[UINavigationBar appearance] setBarStyle:barStyle];

    BOOL supportsTabBarStyle = [UITabBar instancesRespondToSelector:@selector(setBarStyle:)];
    if (supportsTabBarStyle) {
        [[UITabBar appearance] setBarStyle:barStyle];
    }

    if (supportsBarTintColor) {
        [[UINavigationBar appearance] setBarTintColor:barBackground];
        [[UITabBar appearance] setBarTintColor:barBackground];
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

UIColor *GHAccentColor(void) {
    return [UIColor colorWithRed:0.25 green:0.55 blue:1.0 alpha:1.0];
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

static UIImage *GHButtonBackgroundImage(UIColor *fill, UIColor *stroke) {
    CGFloat radius = 12;
    CGSize size = CGSizeMake(radius * 2 + 1, radius * 2 + 1);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5)
                                                    cornerRadius:radius];
    [fill setFill];
    [path fill];
    if (stroke) {
        [stroke setStroke];
        path.lineWidth = 1;
        [path stroke];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

void GHStyleButton(UIButton *button, GHButtonStyle style) {
    UIColor *tint = GHAccentColor();
    if (style == GHButtonStylePrimary) {
        [button setBackgroundImage:GHButtonBackgroundImage(tint, nil) forState:UIControlStateNormal];
        [button setBackgroundImage:GHButtonBackgroundImage([tint colorWithAlphaComponent:0.75], nil) forState:UIControlStateHighlighted];
        [button setBackgroundImage:GHButtonBackgroundImage([tint colorWithAlphaComponent:0.35], nil) forState:UIControlStateDisabled];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.75] forState:UIControlStateHighlighted];
        [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.8] forState:UIControlStateDisabled];
    } else {
        UIColor *fill = GHCellBackgroundColor();
        UIColor *stroke = GHSeparatorColor();
        [button setBackgroundImage:GHButtonBackgroundImage(fill, stroke) forState:UIControlStateNormal];
        [button setBackgroundImage:GHButtonBackgroundImage([tint colorWithAlphaComponent:0.15], stroke) forState:UIControlStateHighlighted];
        [button setBackgroundImage:GHButtonBackgroundImage(fill, stroke) forState:UIControlStateDisabled];
        [button setTitleColor:tint forState:UIControlStateNormal];
        [button setTitleColor:tint forState:UIControlStateHighlighted];
        [button setTitleColor:GHSecondaryTextColor() forState:UIControlStateDisabled];
    }
}

UIButton *GHMakeButton(GHButtonStyle style) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    GHStyleButton(button, style);
    return button;
}

UIView *GHSignInPlaceholderView(NSString *message, CGFloat width, id target, SEL action) {
    CGFloat labelWidth = width - 40;
    UIFont *messageFont = [UIFont systemFontOfSize:15];
    CGSize messageSize = [message sizeWithFont:messageFont
                              constrainedToSize:CGSizeMake(labelWidth, CGFLOAT_MAX)
                                  lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat labelHeight = ceil(messageSize.height);

    CGFloat buttonY = 24 + labelHeight + 16;
    CGFloat headerHeight = buttonY + 44 + 16;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];

    UILabel *messageLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, labelWidth, labelHeight)];
    messageLabel.text = message;
    messageLabel.textColor = GHSecondaryTextColor();
    messageLabel.backgroundColor = [UIColor clearColor];
    messageLabel.font = messageFont;
    messageLabel.textAlignment = NSTextAlignmentCenter;
    messageLabel.numberOfLines = 0;
    messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:messageLabel];

    UIButton *openSettingsButton = GHMakeButton(GHButtonStylePrimary);
    openSettingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [openSettingsButton setTitle:GHL(@"Открыть настройки") forState:UIControlStateNormal];
    [openSettingsButton addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [openSettingsButton sizeToFit];
    CGFloat buttonWidth = MIN(MAX(openSettingsButton.frame.size.width + 32, 200), width - 40);
    openSettingsButton.frame = CGRectMake(floor((width - buttonWidth) / 2.0), buttonY, buttonWidth, 44);
    openSettingsButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [header addSubview:openSettingsButton];

    return header;
}
