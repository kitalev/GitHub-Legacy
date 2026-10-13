#import "ProfileViewController.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHProfileHeaderView.h"
#import "SettingsViewController.h"

@interface ProfileViewController ()
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, assign) CGFloat placeholderHeight;
@end

@implementation ProfileViewController

- (id)init {
    self = [super init];
    if (self) {
        self.title = GHL(@"Профиль");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.frame = CGRectMake(0, 0, 30, 30);
    [self.settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.settingsButton];

    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = GHL(@"Профиль");
    [self reload];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    if (![self showsProfileContent]) {
        CGFloat height = MAX(self.tableView.bounds.size.height, 140);
        if (fabs(height - self.placeholderHeight) > 0.5) {
            [self showSignedOutPlaceholder];
        }
    }
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Профиль");
    if (![self showsProfileContent]) [self showSignedOutPlaceholder];
    [super handleLanguageDidChange];
}

- (void)applyTheme {
    [self.settingsButton setImage:[GHIconRenderer gearIconWithColor:GHSettingsIconColor() size:22] forState:UIControlStateNormal];
    [super applyTheme];
    if (![self showsProfileContent]) [self showSignedOutPlaceholder];
}

- (BOOL)showsProfileContent {
    return [GHAuthManager sharedManager].isAuthenticated;
}

- (NSString *)profileLogin {
    return [super profileLogin] ?: [GHAuthManager sharedManager].currentUserLogin;
}

- (void)openSettings {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)showSignedOutPlaceholder {
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;
    CGFloat height = MAX(self.tableView.bounds.size.height, 140);
    self.placeholderHeight = height;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];

    CGFloat blockHeight = 60;
    CGFloat blockTop = (height - blockHeight) / 2.0;

    UILabel *message = [[UILabel alloc] initWithFrame:CGRectMake(20, blockTop, width - 40, 44)];
    message.text = GHL(@"Войдите в аккаунт в Настройках, чтобы видеть свой профиль");
    message.textColor = GHSecondaryTextColor();
    message.backgroundColor = [UIColor clearColor];
    message.font = [UIFont systemFontOfSize:15];
    message.textAlignment = NSTextAlignmentCenter;
    message.numberOfLines = 0;
    [header addSubview:message];

    UIButton *openSettingsButton = GHMakeButton(GHButtonStylePrimary);
    openSettingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [openSettingsButton setTitle:GHL(@"Открыть настройки") forState:UIControlStateNormal];
    [openSettingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [openSettingsButton sizeToFit];
    CGFloat buttonWidth = MIN(MAX(openSettingsButton.frame.size.width + 32, 200), width - 40);
    openSettingsButton.frame = CGRectMake(floor((width - buttonWidth) / 2.0), blockTop + blockHeight + 4, buttonWidth, 44);
    [header addSubview:openSettingsButton];

    self.tableView.tableHeaderView = header;
}

- (void)reload {
    if (![self showsProfileContent]) {
        [self resetProfileData];
        [self endRefreshing];
        [self.spinner stopAnimating];
        [self showSignedOutPlaceholder];
        [self.tableView reloadData];
        return;
    }

    [self.spinner startAnimating];
    self.headerLoading = YES;
    [self refreshHeader];

    NSString *knownLogin = [GHAuthManager sharedManager].currentUserLogin;
    if (knownLogin.length > 0) [self fetchOrganizationsForLogin:knownLogin];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            strongSelf.userInfo = jsonObject;
            NSString *login = [jsonObject objectForKey:@"login"];
            if ([login isKindOfClass:[NSString class]] && login.length > 0) {
                if (![login isEqualToString:knownLogin]) [strongSelf fetchOrganizationsForLogin:login];
                [GHAuthManager sharedManager].currentUserLogin = login;
            }
        }
        strongSelf.headerLoading = NO;
        [strongSelf refreshHeader];
    }];

    [self fetchPinnedReposWithQuery:[NSString stringWithFormat:@"query { viewer { %@ } }", [self pinnedItemsSelection]]
                            rootKey:@"viewer"];

    [[GHAPIClient sharedClient] starredRepositoriesWithCompletion:^(id jsonObject, NSError *error) {
        [weakSelf handleStarredResponse:jsonObject error:error];
    }];

    [[GHAPIClient sharedClient] repositoriesForCurrentUserWithCompletion:^(id jsonObject, NSError *error) {
        [weakSelf handleReposResponse:jsonObject error:error];
    }];
}

@end
