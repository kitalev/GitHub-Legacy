#import "PublicProfileViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "ProfileRepoListViewController.h"
#import "GHUserListViewController.h"
#import "StarredReposViewController.h"

static NSString * const kProfileRepoCellID = @"PublicProfileRepoCell";
static NSString * const kProfilePinnedCellID = @"PublicProfilePinnedCell";

@interface PublicProfileViewController ()
@property (nonatomic, strong) NSDictionary *userInfo;
@property (nonatomic, strong) NSMutableArray *repos;
@property (nonatomic, strong) NSMutableArray *pinnedRepos;
@property (nonatomic, assign) NSInteger starredCount;
@property (nonatomic, assign) BOOL starredCountLoaded;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *loginLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) UILabel *locationLabel;
@property (nonatomic, strong) UIButton *followersStatButton;
@property (nonatomic, strong) UILabel *statsSeparatorLabel;
@property (nonatomic, strong) UIButton *followingStatButton;

@property (nonatomic, strong) UIButton *followButton;
@property (nonatomic, assign) BOOL isFollowingUser;
@property (nonatomic, assign) BOOL followStatusLoaded;
@property (nonatomic, assign) BOOL followActionInProgress;

@property (nonatomic, strong) NSNumber *pendingFollowersOverride;
@end

@implementation PublicProfileViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _repos = [NSMutableArray array];
        _pinnedRepos = [NSMutableArray array];
    }
    return self;
}

- (NSDictionary *)safeDictForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)safeStringForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSNumber *)safeNumberForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.login.length > 0 ? self.login : GHL(@"Профиль");

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kProfileRepoCellID];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kProfilePinnedCellID];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [self buildHeaderSubviews];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(themeDidChange)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.nameLabel.textColor = GHPrimaryTextColor();
    self.loginLabel.textColor = GHProfileHeaderSecondaryTextColor();
    self.bioLabel.textColor = GHSecondaryTextColor();
    self.locationLabel.textColor = GHSecondaryTextColor();
    self.statsSeparatorLabel.textColor = GHProfileHeaderSecondaryTextColor();
    [self styleStatButton:self.followersStatButton];
    [self styleStatButton:self.followingStatButton];
    [self.tableView reloadData];
}

- (void)themeDidChange {
    [self applyTheme];
    [self layoutHeaderWithLoading:NO];
}

- (void)buildHeaderSubviews {
    self.avatarView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 72, 72)];
    self.avatarView.layer.cornerRadius = 36;
    self.avatarView.layer.masksToBounds = YES;
    self.avatarView.backgroundColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;

    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:20];
    self.nameLabel.backgroundColor = [UIColor clearColor];

    self.loginLabel = [[UILabel alloc] init];
    self.loginLabel.font = [UIFont systemFontOfSize:15];
    self.loginLabel.backgroundColor = [UIColor clearColor];

    self.bioLabel = [[UILabel alloc] init];
    self.bioLabel.font = [UIFont systemFontOfSize:14];
    self.bioLabel.numberOfLines = 0;
    self.bioLabel.backgroundColor = [UIColor clearColor];

    self.locationLabel = [[UILabel alloc] init];
    self.locationLabel.font = [UIFont systemFontOfSize:14];
    self.locationLabel.backgroundColor = [UIColor clearColor];

    self.followersStatButton = [self makeStatButton];
    [self.followersStatButton addTarget:self action:@selector(followersStatTapped) forControlEvents:UIControlEventTouchUpInside];

    self.statsSeparatorLabel = [[UILabel alloc] init];
    self.statsSeparatorLabel.font = [UIFont systemFontOfSize:14];
    self.statsSeparatorLabel.text = @"•";
    self.statsSeparatorLabel.backgroundColor = [UIColor clearColor];

    self.followingStatButton = [self makeStatButton];
    [self.followingStatButton addTarget:self action:@selector(followingStatTapped) forControlEvents:UIControlEventTouchUpInside];

    self.followButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.followButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.followButton.layer.cornerRadius = 6;
    self.followButton.layer.masksToBounds = YES;
    self.followButton.layer.borderWidth = 1;
    [self.followButton addTarget:self action:@selector(followButtonTapped) forControlEvents:UIControlEventTouchUpInside];
}

- (UIButton *)makeStatButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    return button;
}

- (void)styleStatButton:(UIButton *)button {
    [button setTitleColor:GHProfileHeaderSecondaryTextColor() forState:UIControlStateNormal];
}

- (void)setStatButton:(UIButton *)button count:(NSNumber *)count caption:(NSString *)caption {
    NSNumber *safeCount = count ?: @0;
    NSString *text = [NSString stringWithFormat:@"%@ %@", safeCount, caption];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange countRange = NSMakeRange(0, [safeCount stringValue].length);
    [attributed addAttribute:NSFontAttributeName value:[UIFont boldSystemFontOfSize:14] range:countRange];
    [attributed addAttribute:NSForegroundColorAttributeName value:GHPrimaryTextColor() range:countRange];
    [attributed addAttribute:NSForegroundColorAttributeName
                        value:GHProfileHeaderSecondaryTextColor()
                        range:NSMakeRange(countRange.length, text.length - countRange.length)];
    [button setAttributedTitle:attributed forState:UIControlStateNormal];
    [button sizeToFit];
}

- (void)reload {
    if (self.login.length == 0) return;

    [self.spinner startAnimating];
    [self layoutHeaderWithLoading:YES];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] publicProfileForUser:self.login completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *info = [jsonObject mutableCopy];
            if (strongSelf.pendingFollowersOverride) {

                info[@"followers"] = strongSelf.pendingFollowersOverride;
                strongSelf.pendingFollowersOverride = nil;
            }
            strongSelf.userInfo = info;
            [strongSelf loadAvatar];
        }
        [strongSelf layoutHeaderWithLoading:NO];
    }];

    if ([GHAuthManager sharedManager].isAuthenticated) {
        self.followStatusLoaded = NO;
        [[GHAPIClient sharedClient] checkFollowingUser:self.login completion:^(NSInteger statusCode, NSString *message, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.isFollowingUser = (statusCode == 204);
            strongSelf.followStatusLoaded = YES;
            [strongSelf layoutHeaderWithLoading:NO];
        }];
    } else {
        self.followStatusLoaded = NO;
        self.isFollowingUser = NO;
    }

    if ([GHAuthManager sharedManager].isAuthenticated) {
        [self fetchPinnedRepos];
    } else {
        [self.pinnedRepos removeAllObjects];
    }

    [[GHAPIClient sharedClient] starredRepositoriesForUser:self.login completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && [jsonObject isKindOfClass:[NSArray class]]) {
            strongSelf.starredCount = [(NSArray *)jsonObject count];
            strongSelf.starredCountLoaded = YES;
            [strongSelf.tableView reloadData];
        }
    }];

    [[GHAPIClient sharedClient] repositoriesForUser:self.login completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.spinner stopAnimating];
        [strongSelf.refreshControl endRefreshing];

        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        [strongSelf.repos removeAllObjects];
        if ([jsonObject isKindOfClass:[NSArray class]]) {
            [strongSelf.repos addObjectsFromArray:jsonObject];
        }
        [strongSelf.tableView reloadData];
    }];
}

- (void)loadAvatar {
    NSString *avatarURLString = [self safeStringForKey:@"avatar_url" inDict:self.userInfo];
    NSURL *avatarURL = [NSURL URLWithString:avatarURLString];
    if (!avatarURL) return;

    NSURLRequest *request = [NSURLRequest requestWithURL:avatarURL];
    __weak typeof(self) weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (connectionError || data.length == 0) return;
        UIImage *image = [UIImage imageWithData:data];
        if (image) {
            strongSelf.avatarView.image = image;
        }
    }];
}

- (void)fetchPinnedRepos {
    NSString *query =
        [NSString stringWithFormat:
         @"query { user(login: \"%@\") { pinnedItems(first: 10, types: REPOSITORY) { nodes { "
          "... on Repository { name nameWithOwner description url homepageUrl "
          "stargazerCount forkCount watchers { totalCount } issues(states: OPEN) { totalCount } "
          "hasIssuesEnabled defaultBranchRef { name } updatedAt "
          "primaryLanguage { name } licenseInfo { name } owner { login } } } } } }", self.login];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] graphQLQuery:query completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.pinnedRepos removeAllObjects];
        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            NSDictionary *data = [strongSelf safeDictForKey:@"data" inDict:jsonObject];
            NSDictionary *user = [strongSelf safeDictForKey:@"user" inDict:data];
            NSDictionary *pinnedItems = [strongSelf safeDictForKey:@"pinnedItems" inDict:user];
            NSArray *nodes = [pinnedItems[@"nodes"] isKindOfClass:[NSArray class]] ? pinnedItems[@"nodes"] : @[];
            for (id node in nodes) {
                if ([node isKindOfClass:[NSDictionary class]]) {
                    [strongSelf.pinnedRepos addObject:[strongSelf normalizedRepoFromGraphQLNode:node]];
                }
            }
        } else if (error) {

            NSLog(@"[GitHubLegacy] Не удалось загрузить закреплённые репозитории пользователя %@: %@", strongSelf.login, error.localizedDescription);
        }
        [strongSelf.tableView reloadData];
    }];
}

- (NSDictionary *)normalizedRepoFromGraphQLNode:(NSDictionary *)node {
    NSString *name = [self safeStringForKey:@"name" inDict:node] ?: @"";
    NSString *fullName = [self safeStringForKey:@"nameWithOwner" inDict:node];
    NSDictionary *ownerNode = [self safeDictForKey:@"owner" inDict:node];
    NSString *ownerLogin = [self safeStringForKey:@"login" inDict:ownerNode] ?: @"";
    NSString *description = [self safeStringForKey:@"description" inDict:node];
    NSString *homepage = [self safeStringForKey:@"homepageUrl" inDict:node];
    NSString *htmlURL = [self safeStringForKey:@"url" inDict:node];
    NSDictionary *defaultBranchRef = [self safeDictForKey:@"defaultBranchRef" inDict:node];
    NSString *defaultBranch = [self safeStringForKey:@"name" inDict:defaultBranchRef];
    NSString *updatedAt = [self safeStringForKey:@"updatedAt" inDict:node];
    NSDictionary *primaryLanguage = [self safeDictForKey:@"primaryLanguage" inDict:node];
    NSString *language = [self safeStringForKey:@"name" inDict:primaryLanguage];
    NSDictionary *licenseInfo = [self safeDictForKey:@"licenseInfo" inDict:node];
    NSString *licenseName = [self safeStringForKey:@"name" inDict:licenseInfo];
    NSDictionary *watchers = [self safeDictForKey:@"watchers" inDict:node];
    NSDictionary *issues = [self safeDictForKey:@"issues" inDict:node];
    id hasIssuesValue = node[@"hasIssuesEnabled"];

    NSMutableDictionary *repo = [NSMutableDictionary dictionary];
    repo[@"name"] = name;
    repo[@"full_name"] = fullName.length > 0 ? fullName : [NSString stringWithFormat:@"%@/%@", ownerLogin, name];
    repo[@"owner"] = @{@"login": ownerLogin};
    repo[@"description"] = description ?: [NSNull null];
    repo[@"homepage"] = homepage ?: [NSNull null];
    repo[@"html_url"] = htmlURL ?: @"";
    repo[@"default_branch"] = defaultBranch.length > 0 ? defaultBranch : @"main";
    repo[@"updated_at"] = updatedAt ?: @"";
    repo[@"language"] = language ?: [NSNull null];
    repo[@"license"] = licenseName.length > 0 ? @{@"name": licenseName} : [NSNull null];
    repo[@"stargazers_count"] = [node[@"stargazerCount"] isKindOfClass:[NSNumber class]] ? node[@"stargazerCount"] : @0;
    repo[@"forks_count"] = [node[@"forkCount"] isKindOfClass:[NSNumber class]] ? node[@"forkCount"] : @0;
    repo[@"watchers_count"] = [watchers[@"totalCount"] isKindOfClass:[NSNumber class]] ? watchers[@"totalCount"] : @0;
    repo[@"open_issues_count"] = [issues[@"totalCount"] isKindOfClass:[NSNumber class]] ? issues[@"totalCount"] : @0;
    repo[@"has_issues"] = @([hasIssuesValue isKindOfClass:[NSNumber class]] ? [hasIssuesValue boolValue] : YES);
    return repo;
}

- (void)layoutHeaderWithLoading:(BOOL)loading {
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;

    NSString *name = [self safeStringForKey:@"name" inDict:self.userInfo];
    NSString *login = [self safeStringForKey:@"login" inDict:self.userInfo] ?: self.login;
    NSString *bio = [self safeStringForKey:@"bio" inDict:self.userInfo];
    NSString *location = [self safeStringForKey:@"location" inDict:self.userInfo];
    NSNumber *followers = [self safeNumberForKey:@"followers" inDict:self.userInfo];
    NSNumber *following = [self safeNumberForKey:@"following" inDict:self.userInfo];

    self.nameLabel.textColor = GHPrimaryTextColor();
    self.loginLabel.textColor = GHProfileHeaderSecondaryTextColor();
    self.bioLabel.textColor = GHSecondaryTextColor();
    self.locationLabel.textColor = GHSecondaryTextColor();
    self.statsSeparatorLabel.textColor = GHProfileHeaderSecondaryTextColor();

    self.nameLabel.text = loading ? GHL(@"Загрузка…") : (name.length > 0 ? name : login);
    self.loginLabel.text = login.length > 0 ? [NSString stringWithFormat:@"@%@", login] : @"";
    self.bioLabel.text = bio.length > 0 ? bio : @"";
    self.locationLabel.text = location.length > 0 ? [NSString stringWithFormat:@"📍 %@", location] : @"";

    CGFloat avatarBottom = CGRectGetMaxY(self.avatarView.frame);
    CGFloat avatarCenterY = CGRectGetMidY(self.avatarView.frame);
    CGFloat leftColumnX = CGRectGetMaxX(self.avatarView.frame) + 12;
    CGFloat leftColumnWidth = width - leftColumnX - 16;

    [self.nameLabel sizeToFit];
    [self.loginLabel sizeToFit];
    CGFloat namesBlockHeight = self.nameLabel.frame.size.height + (self.loginLabel.text.length > 0 ? self.loginLabel.frame.size.height + 2 : 0);
    CGFloat namesTop = avatarCenterY - namesBlockHeight / 2.0;

    self.nameLabel.frame = CGRectMake(leftColumnX, namesTop, leftColumnWidth, self.nameLabel.frame.size.height);
    self.loginLabel.frame = CGRectMake(leftColumnX, CGRectGetMaxY(self.nameLabel.frame) + 2, leftColumnWidth, self.loginLabel.frame.size.height);

    CGSize bioSize = [self.bioLabel.text sizeWithFont:self.bioLabel.font
                                     constrainedToSize:CGSizeMake(width - 32, CGFLOAT_MAX)
                                         lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat bioTop = avatarBottom + 16;
    self.bioLabel.frame = CGRectMake(16, bioTop, width - 32, self.bioLabel.text.length > 0 ? bioSize.height : 0);

    CGFloat locationTop = bioTop + (self.bioLabel.text.length > 0 ? bioSize.height + 8 : 0);
    [self.locationLabel sizeToFit];
    self.locationLabel.frame = CGRectMake(16, locationTop, width - 32, self.locationLabel.text.length > 0 ? self.locationLabel.frame.size.height : 0);

    [self setStatButton:self.followersStatButton count:followers caption:GHL(@"подписчиков")];
    [self setStatButton:self.followingStatButton count:following caption:GHL(@"подписок")];
    [self.statsSeparatorLabel sizeToFit];

    CGFloat statsTop = locationTop + (self.locationLabel.text.length > 0 ? self.locationLabel.frame.size.height + 8 : 0);
    CGFloat statsHeight = loading ? 0 : 20;
    CGFloat statsX = 16;
    self.followersStatButton.frame = CGRectMake(statsX, statsTop, self.followersStatButton.frame.size.width, statsHeight);
    statsX += self.followersStatButton.frame.size.width + 6;
    self.statsSeparatorLabel.frame = CGRectMake(statsX, statsTop, self.statsSeparatorLabel.frame.size.width, statsHeight);
    statsX += self.statsSeparatorLabel.frame.size.width + 6;
    self.followingStatButton.frame = CGRectMake(statsX, statsTop, self.followingStatButton.frame.size.width, statsHeight);
    self.followersStatButton.hidden = loading;
    self.statsSeparatorLabel.hidden = loading;
    self.followingStatButton.hidden = loading;

    BOOL showFollowButton = !loading && [GHAuthManager sharedManager].isAuthenticated;
    [self updateFollowButtonAppearance];
    [self.followButton sizeToFit];
    CGFloat followButtonWidth = showFollowButton ? MAX(self.followButton.frame.size.width + 28, 130) : 0;
    CGFloat followButtonHeight = showFollowButton ? 32 : 0;
    CGFloat followTop = statsTop + statsHeight + (statsHeight > 0 ? 14 : 6);
    self.followButton.frame = CGRectMake(16, followTop, followButtonWidth, followButtonHeight);
    self.followButton.hidden = !showFollowButton;

    CGFloat totalHeight = followTop + followButtonHeight + 16;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, totalHeight)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = [UIColor clearColor];
    [header addSubview:self.avatarView];
    [header addSubview:self.nameLabel];
    [header addSubview:self.loginLabel];
    [header addSubview:self.bioLabel];
    [header addSubview:self.locationLabel];
    [header addSubview:self.followersStatButton];
    [header addSubview:self.statsSeparatorLabel];
    [header addSubview:self.followingStatButton];
    [header addSubview:self.followButton];

    self.tableView.tableHeaderView = header;
}

- (void)updateFollowButtonAppearance {
    self.followButton.enabled = !self.followActionInProgress;

    if (!self.followStatusLoaded) {
        [self.followButton setTitle:GHL(@"…") forState:UIControlStateNormal];
        [self.followButton setTitleColor:GHSecondaryTextColor() forState:UIControlStateNormal];
        self.followButton.backgroundColor = [UIColor clearColor];
        self.followButton.layer.borderColor = GHSeparatorColor().CGColor;
        return;
    }

    if (self.isFollowingUser) {
        [self.followButton setTitle:GHL(@"Отписаться") forState:UIControlStateNormal];
        [self.followButton setTitleColor:GHPrimaryTextColor() forState:UIControlStateNormal];
        self.followButton.backgroundColor = [UIColor clearColor];
        self.followButton.layer.borderColor = GHSeparatorColor().CGColor;
    } else {
        [self.followButton setTitle:GHL(@"Подписаться") forState:UIControlStateNormal];
        [self.followButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        UIColor *tint = GHTintColor() ?: [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
        self.followButton.backgroundColor = tint;
        self.followButton.layer.borderColor = tint.CGColor;
    }
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
            NSNumber *currentFollowers = [strongSelf safeNumberForKey:@"followers" inDict:updatedInfo];
            NSInteger delta = wasFollowing ? -1 : 1;
            NSNumber *newFollowersCount = @(MAX(0, currentFollowers.integerValue + delta));
            updatedInfo[@"followers"] = newFollowersCount;
            strongSelf.userInfo = updatedInfo;

            strongSelf.pendingFollowersOverride = newFollowersCount;
        } else {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:message.length > 0 ? message : GHL(@"Не удалось выполнить действие")
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        }
        [strongSelf layoutHeaderWithLoading:NO];
    };

    if (wasFollowing) {
        [[GHAPIClient sharedClient] unfollowUser:self.login completion:completion];
    } else {
        [[GHAPIClient sharedClient] followUser:self.login completion:completion];
    }
}

- (void)followersStatTapped {
    [self pushUserListShowingFollowers:YES title:GHL(@"Подписчики")];
}

- (void)followingStatTapped {
    [self pushUserListShowingFollowers:NO title:GHL(@"Подписки")];
}

- (void)pushUserListShowingFollowers:(BOOL)showingFollowers title:(NSString *)title {
    if (self.login.length == 0) return;
    GHUserListViewController *listVC = [[GHUserListViewController alloc] init];
    listVC.login = self.login;
    listVC.showingFollowers = showingFollowers;
    listVC.title = title;
    [self.navigationController pushViewController:listVC animated:YES];
}

#pragma mark - Секции

- (BOOL)hasPinnedSection {
    return self.pinnedRepos.count > 0;
}

- (NSInteger)pinnedSectionIndex {
    return 0;
}

- (UIImage *)squareIconWithEmoji:(NSString *)emoji backgroundColor:(UIColor *)bgColor {
    CGFloat size = 30;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:8];
    [bgColor setFill];
    [rounded fill];

    UIFont *font = [UIFont systemFontOfSize:16];
    CGSize textSize = [emoji sizeWithFont:font];
    CGPoint origin = CGPointMake((size - textSize.width) / 2.0, (size - textSize.height) / 2.0);
    [emoji drawAtPoint:origin withFont:font];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasPinnedSection] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self hasPinnedSection] && section == [self pinnedSectionIndex]) return GHL(@"Закреплённые");
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self hasPinnedSection] && section == [self pinnedSectionIndex]) return self.pinnedRepos.count;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasPinnedSection] && indexPath.section == [self pinnedSectionIndex]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kProfilePinnedCellID forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.numberOfLines = 1;

        NSDictionary *repo = self.pinnedRepos[indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"📌 %@", repo[@"full_name"]];
        cell.textLabel.textColor = GHPrimaryTextColor();
        NSString *description = [self safeStringForKey:@"description" inDict:repo];
        NSNumber *stars = repo[@"stargazers_count"];
        cell.detailTextLabel.text = description.length > 0
            ? [NSString stringWithFormat:@"%@ · ★ %@", description, stars ?: @0]
            : [NSString stringWithFormat:@"★ %@", stars ?: @0];
        cell.detailTextLabel.textColor = GHSecondaryTextColor();
        cell.detailTextLabel.numberOfLines = 1;
        GHApplyDisclosureIndicator(cell);
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kProfileRepoCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = nil;

    if (indexPath.row == 0) {
        cell.textLabel.text = GHL(@"Репозитории");
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.imageView.image = [self squareIconWithEmoji:@"📁" backgroundColor:[UIColor colorWithWhite:0.55 alpha:1.0]];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.repos.count];
    } else {
        cell.textLabel.text = GHL(@"Избранное");
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.imageView.image = [self squareIconWithEmoji:@"⭐️" backgroundColor:[UIColor colorWithRed:1.0 green:0.72 blue:0.0 alpha:1.0]];
        cell.detailTextLabel.text = self.starredCountLoaded ? [NSString stringWithFormat:@"%ld", (long)self.starredCount] : @"";
    }
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    GHApplyDisclosureIndicator(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self hasPinnedSection] && indexPath.section == [self pinnedSectionIndex]) {
        NSDictionary *repo = self.pinnedRepos[indexPath.row];
        RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
        overviewVC.repo = repo;
        overviewVC.title = repo[@"name"];
        [self.navigationController pushViewController:overviewVC animated:YES];
        return;
    }

    if (indexPath.row == 0) {
        ProfileRepoListViewController *listVC = [[ProfileRepoListViewController alloc] init];
        listVC.repos = self.repos;
        [self.navigationController pushViewController:listVC animated:YES];
    } else {
        StarredReposViewController *starredVC = [[StarredReposViewController alloc] init];
        starredVC.viewedLogin = self.login;
        starredVC.title = GHL(@"Избранное");
        [self.navigationController pushViewController:starredVC animated:YES];
    }
}

@end
