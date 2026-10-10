#import "PublicProfileViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHProfileHeaderView.h"

@interface PublicProfileViewController ()
@property (nonatomic, strong) UIButton *followButton;
@property (nonatomic, assign) BOOL isFollowingUser;
@property (nonatomic, assign) BOOL followStatusLoaded;
@property (nonatomic, assign) BOOL followActionInProgress;
@property (nonatomic, strong) NSNumber *pendingFollowersOverride;
@end

@implementation PublicProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.login.length > 0 ? self.login : GHL(@"Профиль");

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.followButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.followButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.followButton.layer.cornerRadius = 8;
    self.followButton.layer.masksToBounds = YES;
    self.followButton.layer.borderWidth = 1;
    [self.followButton addTarget:self action:@selector(followButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.followButton.hidden = YES;
    self.headerView.actionButton = self.followButton;

    [self applyTheme];
    [self reload];
}

- (NSString *)profileLogin {
    return self.login;
}

- (NSString *)starredViewedLogin {
    return self.login;
}

- (BOOL)isViewerOwnProfile {
    NSString *currentLogin = [GHAuthManager sharedManager].currentUserLogin;
    return currentLogin.length > 0 && [self.login caseInsensitiveCompare:currentLogin] == NSOrderedSame;
}

- (void)refreshHeader {
    BOOL showFollowButton = self.userInfo != nil && [GHAuthManager sharedManager].isAuthenticated && ![self isViewerOwnProfile];
    self.followButton.hidden = !showFollowButton;
    [self updateFollowButtonAppearance];
    [super refreshHeader];
}

- (void)reload {
    if (self.login.length == 0) return;

    [self.spinner startAnimating];
    self.headerLoading = YES;
    [self refreshHeader];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] publicProfileForUser:self.login completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *info = [jsonObject mutableCopy];
            if (strongSelf.pendingFollowersOverride) {
                [info setObject:strongSelf.pendingFollowersOverride forKey:@"followers"];
                strongSelf.pendingFollowersOverride = nil;
            }
            strongSelf.userInfo = info;
        }
        strongSelf.headerLoading = NO;
        [strongSelf refreshHeader];
    }];

    if ([GHAuthManager sharedManager].isAuthenticated && ![self isViewerOwnProfile]) {
        self.followStatusLoaded = NO;
        [[GHAPIClient sharedClient] checkFollowingUser:self.login completion:^(NSInteger statusCode, NSString *message, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.isFollowingUser = (statusCode == 204);
            strongSelf.followStatusLoaded = YES;
            [strongSelf refreshHeader];
        }];
    } else {
        self.followStatusLoaded = NO;
        self.isFollowingUser = NO;
    }

    if ([GHAuthManager sharedManager].isAuthenticated) {
        NSString *escapedLogin = [self.login stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        NSString *query = [NSString stringWithFormat:@"query { user(login: \"%@\") { %@ } }", escapedLogin, [self pinnedItemsSelection]];
        [self fetchPinnedReposWithQuery:query rootKey:@"user"];
    } else {
        [self.pinnedRepos removeAllObjects];
    }

    [self fetchOrganizationsForLogin:self.login];

    [[GHAPIClient sharedClient] starredRepositoriesForUser:self.login completion:^(id jsonObject, NSError *error) {
        [weakSelf handleStarredResponse:jsonObject error:error];
    }];

    [[GHAPIClient sharedClient] repositoriesForUser:self.login completion:^(id jsonObject, NSError *error) {
        [weakSelf handleReposResponse:jsonObject error:error];
    }];
}

#pragma mark - Follow

- (void)updateFollowButtonAppearance {
    self.followButton.enabled = !self.followActionInProgress;

    if (!self.followStatusLoaded) {
        [self.followButton setTitle:GHL(@"…") forState:UIControlStateNormal];
        [self.followButton setTitleColor:GHSecondaryTextColor() forState:UIControlStateNormal];
        self.followButton.backgroundColor = GHCellBackgroundColor();
        self.followButton.layer.borderColor = GHSeparatorColor().CGColor;
        return;
    }

    if (self.isFollowingUser) {
        [self.followButton setTitle:GHL(@"Отписаться") forState:UIControlStateNormal];
        [self.followButton setTitleColor:GHPrimaryTextColor() forState:UIControlStateNormal];
        self.followButton.backgroundColor = GHCellBackgroundColor();
        self.followButton.layer.borderColor = GHSeparatorColor().CGColor;
    } else {
        [self.followButton setTitle:GHL(@"Подписаться") forState:UIControlStateNormal];
        [self.followButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        UIColor *tint = GHTintColor() ?: [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
        self.followButton.backgroundColor = tint;
        self.followButton.layer.borderColor = tint.CGColor;
    }
}

- (void)applyTheme {
    [self updateFollowButtonAppearance];
    [super applyTheme];
}

- (void)followButtonTapped {
    if (self.followActionInProgress || !self.followStatusLoaded) return;
    self.followActionInProgress = YES;
    [self updateFollowButtonAppearance];

    BOOL wasFollowing = self.isFollowingUser;
    __weak typeof(self) weakSelf = self;
    GHStatusCompletionBlock completion = ^(NSInteger statusCode, NSString *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.followActionInProgress = NO;

        BOOL success = !error && statusCode >= 200 && statusCode < 300;
        if (success) {
            strongSelf.isFollowingUser = !wasFollowing;

            NSMutableDictionary *updatedInfo = [strongSelf.userInfo mutableCopy] ?: [NSMutableDictionary dictionary];
            id currentValue = [updatedInfo objectForKey:@"followers"];
            NSInteger currentFollowers = [currentValue isKindOfClass:[NSNumber class]] ? [currentValue integerValue] : 0;
            NSNumber *newFollowersCount = @(MAX(0, currentFollowers + (wasFollowing ? -1 : 1)));
            [updatedInfo setObject:newFollowersCount forKey:@"followers"];
            strongSelf.userInfo = updatedInfo;
            strongSelf.pendingFollowersOverride = newFollowersCount;
        } else {
            NSString *detail = message.length > 0 ? message : GHL(@"Не удалось выполнить действие");
            if (!error && statusCode == 404) {
                detail = [detail stringByAppendingFormat:@"\n\n%@",
                    GHL(@"Возможно, у вашего токена нет прав на подписки. Для classic-токена нужен scope «user:follow», для fine-grained — разрешение «Followers».")];
            }
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:detail
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        }
        [strongSelf refreshHeader];
    };

    if (wasFollowing) {
        [[GHAPIClient sharedClient] unfollowUser:self.login completion:completion];
    } else {
        [[GHAPIClient sharedClient] followUser:self.login completion:completion];
    }
}

@end
