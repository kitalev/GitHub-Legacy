#import "GHProfileBaseViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "GHAPIClient.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHURLRouter.h"
#import "GHProfileHeaderView.h"
#import "GHPinnedReposCell.h"
#import "RepoOverviewViewController.h"
#import "ProfileRepoListViewController.h"
#import "GHUserListViewController.h"
#import "StarredReposViewController.h"

static NSString * const kGHProfilePinnedCellID = @"GHProfilePinnedCell";
static NSString * const kGHProfileMenuCellID = @"GHProfileMenuCell";

typedef NS_ENUM(NSInteger, GHProfileMenuRow) {
    GHProfileMenuRowRepositories = 0,
    GHProfileMenuRowOrganizations,
    GHProfileMenuRowStarred,
    GHProfileMenuRowCount
};

@interface GHProfileBaseViewController ()
@property (nonatomic, copy) NSString *extrasLogin;
@end

@implementation GHProfileBaseViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _repos = [NSMutableArray array];
        _pinnedRepos = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    }

    self.headerView = [[GHProfileHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 10)];
    __weak typeof(self) weakSelf = self;
    self.headerView.onFollowersTapped = ^{
        [weakSelf pushUserListShowingFollowers:YES];
    };
    self.headerView.onFollowingTapped = ^{
        [weakSelf pushUserListShowingFollowers:NO];
    };
    self.headerView.onLinkTapped = ^(NSURL *url) {
        [weakSelf openLink:url];
    };

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Subclass hooks

- (NSString *)profileLogin {
    id login = [self.userInfo objectForKey:@"login"];
    return [login isKindOfClass:[NSString class]] ? login : nil;
}

- (NSString *)starredViewedLogin {
    return nil;
}

- (BOOL)showsProfileContent {
    return YES;
}

- (void)reload {
}

- (void)handleLanguageDidChange {
    [self refreshHeader];
    [self.tableView reloadData];
}

#pragma mark - Theme & header

- (void)applyTheme {
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    [self.headerView applyTheme];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)refreshHeader {
    if (![self showsProfileContent]) return;

    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;
    [self loadProfileExtrasIfNeeded];
    [self.headerView configureWithUserInfo:self.userInfo fallbackLogin:[self profileLogin] loading:self.headerLoading];
    CGFloat height = [self.headerView heightForWidth:width];
    self.headerView.frame = CGRectMake(0, 0, width, height);
    [self.headerView setNeedsLayout];
    self.tableView.tableHeaderView = self.headerView;
}

- (void)loadProfileExtrasIfNeeded {
    NSString *login = [self profileLogin];
    if (self.userInfo == nil || login.length == 0 || [login isEqualToString:self.extrasLogin]) return;
    self.extrasLogin = login;
    self.headerView.socialAccounts = nil;
    self.headerView.statusInfo = nil;

    NSString *escaped = [[login stringByReplacingOccurrencesOfString:@"\\" withString:@""] stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    NSString *query = [NSString stringWithFormat:
        @"{user(login:\"%@\"){status{emojiHTML message indicatesLimitedAvailability}"
         "socialAccounts(first:10){nodes{provider displayName url}}}}", escaped];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] graphQLQuery:query completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || ![login isEqualToString:[strongSelf profileLogin]]) return;
        NSDictionary *root = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        NSDictionary *data = [root[@"data"] isKindOfClass:[NSDictionary class]] ? root[@"data"] : root;
        NSDictionary *user = [data[@"user"] isKindOfClass:[NSDictionary class]] ? data[@"user"] : nil;
        if (user == nil) return;
        NSDictionary *social = [user[@"socialAccounts"] isKindOfClass:[NSDictionary class]] ? user[@"socialAccounts"] : nil;
        strongSelf.headerView.socialAccounts = [social[@"nodes"] isKindOfClass:[NSArray class]] ? social[@"nodes"] : nil;
        strongSelf.headerView.statusInfo = [user[@"status"] isKindOfClass:[NSDictionary class]] ? user[@"status"] : nil;
        [strongSelf refreshHeader];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (![self showsProfileContent] || self.tableView.tableHeaderView != self.headerView) return;
    CGFloat width = self.tableView.bounds.size.width;
    if (fabs(self.headerView.frame.size.width - width) > 0.5) {
        [self refreshHeader];
    }
}

- (void)endRefreshing {
    if (GHPullToRefreshAvailable()) {
        [self.refreshControl endRefreshing];
    } else {
        [self.gh_legacyRefreshControl endRefreshing];
    }
}

- (void)resetProfileData {
    self.userInfo = nil;
    [self.repos removeAllObjects];
    [self.pinnedRepos removeAllObjects];
    self.starredCount = 0;
    self.starredCountLoaded = NO;
    self.organizationsCount = 0;
    self.organizationsCountLoaded = NO;
    self.reposLoaded = NO;
}

#pragma mark - Loading helpers

- (NSDictionary *)dictionaryIn:(id)container forKey:(NSString *)key {
    id value = [container isKindOfClass:[NSDictionary class]] ? [container objectForKey:key] : nil;
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)stringIn:(id)container forKey:(NSString *)key {
    id value = [container isKindOfClass:[NSDictionary class]] ? [container objectForKey:key] : nil;
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSNumber *)numberIn:(id)container forKey:(NSString *)key {
    id value = [container isKindOfClass:[NSDictionary class]] ? [container objectForKey:key] : nil;
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (NSString *)pinnedItemsSelection {
    return @"pinnedItems(first: 6, types: REPOSITORY) { nodes { "
            "... on Repository { name nameWithOwner description url homepageUrl "
            "stargazerCount forkCount watchers { totalCount } issues(states: OPEN) { totalCount } "
            "hasIssuesEnabled defaultBranchRef { name } updatedAt "
            "primaryLanguage { name } licenseInfo { name } owner { login avatarUrl } } } }";
}

- (void)fetchPinnedReposWithQuery:(NSString *)query rootKey:(NSString *)rootKey {
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] graphQLQuery:query completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.pinnedRepos removeAllObjects];
        if (!error) {
            NSDictionary *data = [strongSelf dictionaryIn:jsonObject forKey:@"data"];
            NSDictionary *root = [strongSelf dictionaryIn:data forKey:rootKey];
            NSDictionary *pinnedItems = [strongSelf dictionaryIn:root forKey:@"pinnedItems"];
            id nodes = [pinnedItems objectForKey:@"nodes"];
            if ([nodes isKindOfClass:[NSArray class]]) {
                for (id node in nodes) {
                    if ([node isKindOfClass:[NSDictionary class]]) {
                        [strongSelf.pinnedRepos addObject:[strongSelf normalizedRepoFromGraphQLNode:node]];
                    }
                }
            }
        }
        [strongSelf.tableView reloadData];
    }];
}

- (NSDictionary *)normalizedRepoFromGraphQLNode:(NSDictionary *)node {
    NSString *name = [self stringIn:node forKey:@"name"] ?: @"";
    NSString *fullName = [self stringIn:node forKey:@"nameWithOwner"];
    NSDictionary *ownerNode = [self dictionaryIn:node forKey:@"owner"];
    NSString *ownerLogin = [self stringIn:ownerNode forKey:@"login"] ?: @"";
    NSString *ownerAvatar = [self stringIn:ownerNode forKey:@"avatarUrl"];
    NSString *description = [self stringIn:node forKey:@"description"];
    NSString *homepage = [self stringIn:node forKey:@"homepageUrl"];
    NSString *htmlURL = [self stringIn:node forKey:@"url"];
    NSString *defaultBranch = [self stringIn:[self dictionaryIn:node forKey:@"defaultBranchRef"] forKey:@"name"];
    NSString *updatedAt = [self stringIn:node forKey:@"updatedAt"];
    NSString *language = [self stringIn:[self dictionaryIn:node forKey:@"primaryLanguage"] forKey:@"name"];
    NSString *licenseName = [self stringIn:[self dictionaryIn:node forKey:@"licenseInfo"] forKey:@"name"];
    id hasIssuesValue = [node objectForKey:@"hasIssuesEnabled"];

    NSMutableDictionary *owner = [NSMutableDictionary dictionaryWithObject:ownerLogin forKey:@"login"];
    if (ownerAvatar.length > 0) [owner setObject:ownerAvatar forKey:@"avatar_url"];

    NSMutableDictionary *repo = [NSMutableDictionary dictionary];
    [repo setObject:name forKey:@"name"];
    [repo setObject:(fullName.length > 0 ? fullName : [NSString stringWithFormat:@"%@/%@", ownerLogin, name]) forKey:@"full_name"];
    [repo setObject:owner forKey:@"owner"];
    [repo setObject:(description ?: (id)[NSNull null]) forKey:@"description"];
    [repo setObject:(homepage ?: (id)[NSNull null]) forKey:@"homepage"];
    [repo setObject:(htmlURL ?: @"") forKey:@"html_url"];
    [repo setObject:(defaultBranch.length > 0 ? defaultBranch : @"main") forKey:@"default_branch"];
    [repo setObject:(updatedAt ?: @"") forKey:@"updated_at"];
    [repo setObject:(language ?: (id)[NSNull null]) forKey:@"language"];
    [repo setObject:(licenseName.length > 0 ? [NSDictionary dictionaryWithObject:licenseName forKey:@"name"] : (id)[NSNull null]) forKey:@"license"];
    [repo setObject:[self numberIn:node forKey:@"stargazerCount"] forKey:@"stargazers_count"];
    [repo setObject:[self numberIn:node forKey:@"forkCount"] forKey:@"forks_count"];
    [repo setObject:[self numberIn:[self dictionaryIn:node forKey:@"watchers"] forKey:@"totalCount"] forKey:@"watchers_count"];
    [repo setObject:[self numberIn:[self dictionaryIn:node forKey:@"issues"] forKey:@"totalCount"] forKey:@"open_issues_count"];
    [repo setObject:@([hasIssuesValue isKindOfClass:[NSNumber class]] ? [hasIssuesValue boolValue] : YES) forKey:@"has_issues"];
    return repo;
}

- (void)fetchOrganizationsForLogin:(NSString *)login {
    if (login.length == 0) return;
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] organizationsForUser:login completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!error && [jsonObject isKindOfClass:[NSArray class]]) {
            strongSelf.organizationsCount = [(NSArray *)jsonObject count];
            strongSelf.organizationsCountLoaded = YES;
            [strongSelf.tableView reloadData];
        }
    }];
}

- (void)handleStarredResponse:(id)jsonObject error:(NSError *)error {
    if (!error && [jsonObject isKindOfClass:[NSArray class]]) {
        self.starredCount = [(NSArray *)jsonObject count];
        self.starredCountLoaded = YES;
        [self.tableView reloadData];
    }
}

- (void)handleReposResponse:(id)jsonObject error:(NSError *)error {
    [self.spinner stopAnimating];
    [self endRefreshing];

    if (error) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                         message:error.localizedDescription
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }

    [self.repos removeAllObjects];
    if ([jsonObject isKindOfClass:[NSArray class]]) {
        [self.repos addObjectsFromArray:jsonObject];
    }
    self.reposLoaded = YES;
    [self.tableView reloadData];
}

#pragma mark - Navigation

- (void)pushUserListShowingFollowers:(BOOL)showingFollowers {
    NSString *login = [self profileLogin];
    if (login.length == 0) return;
    GHUserListViewController *listVC = [[GHUserListViewController alloc] init];
    listVC.login = login;
    listVC.showingFollowers = showingFollowers;
    listVC.title = showingFollowers ? GHL(@"Подписчики") : GHL(@"Подписки");
    [self.navigationController pushViewController:listVC animated:YES];
}

- (void)openLink:(NSURL *)url {
    if (!url) return;
    NSString *host = url.host.lowercaseString;
    if (([host isEqualToString:@"github.com"] || [host isEqualToString:@"www.github.com"]) &&
        [GHURLRouter routeGitHubURL:url fromViewController:self]) {
        return;
    }
    [[UIApplication sharedApplication] openURL:url];
}

- (void)openRepo:(NSDictionary *)repo {
    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = [repo objectForKey:@"name"];
    [self.navigationController pushViewController:overviewVC animated:YES];
}

#pragma mark - Sections

- (BOOL)hasPinnedSection {
    return self.pinnedRepos.count > 0;
}

- (BOOL)isPinnedSection:(NSInteger)section {
    return [self hasPinnedSection] && section == 0;
}

- (UIView *)pinnedSectionHeaderView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 40)];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[GHIconRenderer pinIconWithColor:GHSecondaryTextColor() size:18]];
    icon.frame = CGRectMake(16, 13, 18, 18);
    [container addSubview:icon];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16 + 18 + 10, 10, container.bounds.size.width - 60, 24)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:18];
    label.textColor = GHPrimaryTextColor();
    label.text = GHL(@"Закреплённые");
    [container addSubview:label];
    return container;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (![self showsProfileContent]) return 0;
    return [self hasPinnedSection] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isPinnedSection:section]) return 1;
    return GHProfileMenuRowCount;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self isPinnedSection:section]) return [self pinnedSectionHeaderView];
    return GHThemedSectionHeaderView(nil);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isPinnedSection:section]) return 40;
    return GHThemedSectionHeaderHeight(nil);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isPinnedSection:indexPath.section]) return [GHPinnedReposCell cellHeight];
    return 50;
}

- (UIImage *)menuIconForRow:(GHProfileMenuRow)row {
    UIColor *white = [UIColor whiteColor];
    switch (row) {
        case GHProfileMenuRowRepositories:
            return [GHIconRenderer tileWithIcon:[GHIconRenderer repoIconWithColor:white size:18]
                                backgroundColor:[UIColor colorWithRed:0.33 green:0.36 blue:0.40 alpha:1.0]
                                           size:30];
        case GHProfileMenuRowOrganizations:
            return [GHIconRenderer tileWithIcon:[GHIconRenderer organizationIconWithColor:white size:18]
                                backgroundColor:[UIColor colorWithRed:0.94 green:0.51 blue:0.24 alpha:1.0]
                                           size:30];
        default:
            return [GHIconRenderer tileWithIcon:[GHIconRenderer starIconWithColor:white size:18 filled:NO]
                                backgroundColor:[UIColor colorWithRed:0.89 green:0.70 blue:0.16 alpha:1.0]
                                           size:30];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isPinnedSection:indexPath.section]) {
        GHPinnedReposCell *cell = [tableView dequeueReusableCellWithIdentifier:kGHProfilePinnedCellID];
        if (!cell) {
            cell = [[GHPinnedReposCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kGHProfilePinnedCellID];
        }
        __weak typeof(self) weakSelf = self;
        cell.onRepoSelected = ^(NSDictionary *repo) {
            [weakSelf openRepo:repo];
        };
        [cell configureWithRepos:self.pinnedRepos];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGHProfileMenuCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kGHProfileMenuCellID];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    }

    GHProfileMenuRow row = indexPath.row;
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = GHPrimaryTextColor();
    cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    cell.imageView.image = [self menuIconForRow:row];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    switch (row) {
        case GHProfileMenuRowRepositories:
            cell.textLabel.text = GHL(@"Репозитории");
            cell.detailTextLabel.text = self.reposLoaded ? [NSString stringWithFormat:@"%lu", (unsigned long)self.repos.count] : @"";
            break;
        case GHProfileMenuRowOrganizations:
            cell.textLabel.text = GHL(@"Организации");
            cell.detailTextLabel.text = self.organizationsCountLoaded ? [NSString stringWithFormat:@"%ld", (long)self.organizationsCount] : @"";
            break;
        default:
            cell.textLabel.text = GHL(@"Избранное");
            cell.detailTextLabel.text = self.starredCountLoaded ? [NSString stringWithFormat:@"%ld", (long)self.starredCount] : @"";
            break;
    }
    GHApplyDisclosureIndicator(cell);
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self isPinnedSection:indexPath.section]) return;

    switch (indexPath.row) {
        case GHProfileMenuRowRepositories: {
            ProfileRepoListViewController *listVC = [[ProfileRepoListViewController alloc] init];
            listVC.repos = self.repos;
            [self.navigationController pushViewController:listVC animated:YES];
            break;
        }
        case GHProfileMenuRowOrganizations: {
            NSString *login = [self profileLogin];
            if (login.length == 0) return;
            GHUserListViewController *listVC = [[GHUserListViewController alloc] init];
            listVC.login = login;
            listVC.showingOrganizations = YES;
            listVC.title = GHL(@"Организации");
            [self.navigationController pushViewController:listVC animated:YES];
            break;
        }
        default: {
            StarredReposViewController *starredVC = [[StarredReposViewController alloc] init];
            starredVC.viewedLogin = [self starredViewedLogin];
            starredVC.title = GHL(@"Избранное");
            [self.navigationController pushViewController:starredVC animated:YES];
            break;
        }
    }
}

@end
