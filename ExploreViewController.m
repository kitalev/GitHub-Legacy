#import "ExploreViewController.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "ReleaseDetailViewController.h"
#import "RepoOverviewViewController.h"
#import "GHTrendingClient.h"
#import "GHThemeManager.h"
#import "GHIconRenderer.h"
#import "SettingsViewController.h"
#import "GHExploreFeedCell.h"
#import "GHLocalization.h"

static NSString * const kExploreCellID = @"ExploreFeedCell";
static NSString * const kPlaceholderCellID = @"ExplorePlaceholderCell";
static NSString * const kTrendingCellID = @"ExploreTrendingCell";

static const NSUInteger kMaxTrendingRepos = 3;

typedef NS_ENUM(NSInteger, GHExploreSection) {
    kExploreSectionTrending = 0,
    kExploreSectionFeed = 1
};

@interface ExploreViewController ()

@property (nonatomic, strong) NSMutableArray *feedEntries;
@property (nonatomic, strong) NSArray *trendingRepos;
@property (nonatomic, assign) BOOL trendingLoading;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, assign) BOOL loadAttempted;
@property (nonatomic, assign) NSInteger pendingReleaseRequests;
@end

@implementation ExploreViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Обзор");
        _feedEntries = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kPlaceholderCellID];
    [self.tableView registerClass:[GHExploreFeedCell class] forCellReuseIdentifier:kExploreCellID];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.frame = CGRectMake(0, 0, 30, 30);
    [self.settingsButton addTarget:self action:@selector(settingsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.settingsButton];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)settingsButtonTapped {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadTrendingReposIfNeeded {
    if (self.trendingLoading) return;
    [self loadTrendingRepos];
}

- (void)loadTrendingRepos {
    self.trendingLoading = YES;
    __weak typeof(self) weakSelf = self;
    [[GHTrendingClient sharedClient] trendingRepositoriesSince:@"weekly" completion:^(NSArray *repos, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.trendingLoading = NO;

        if (error || repos.count == 0) return;

        NSRange range = NSMakeRange(0, MIN(repos.count, kMaxTrendingRepos));
        strongSelf.trendingRepos = [repos subarrayWithRange:range];
        [strongSelf.tableView reloadData];
    }];
}

- (void)applyTheme {
    [self.settingsButton setImage:[GHIconRenderer gearIconWithColor:GHSettingsIconColor() size:22] forState:UIControlStateNormal];
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self reload];

    self.title = GHL(@"Обзор");
}

- (NSDictionary *)safeDictForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)safeStringForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (void)reload {
    [self updateSignInHeader];

    [self loadTrendingReposIfNeeded];

    if (![GHAuthManager sharedManager].isAuthenticated) {
        [self.feedEntries removeAllObjects];
        self.loadAttempted = YES;
        [self.refreshControl endRefreshing];
        [self.tableView reloadData];
        return;
    }

    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] starredRepositoriesWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            [strongSelf.spinner stopAnimating];
            [strongSelf.refreshControl endRefreshing];
            strongSelf.loadAttempted = YES;
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            [strongSelf.tableView reloadData];
            return;
        }

        NSArray *starredRepos = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        if (starredRepos.count == 0) {
            [strongSelf.spinner stopAnimating];
            [strongSelf.refreshControl endRefreshing];
            strongSelf.loadAttempted = YES;
            [strongSelf.feedEntries removeAllObjects];
            [strongSelf.tableView reloadData];
            return;
        }

        [strongSelf fetchLatestReleasesForRepos:starredRepos];
    }];
}

- (void)fetchLatestReleasesForRepos:(NSArray *)starredRepos {
    NSMutableArray *collected = [NSMutableArray array];
    self.pendingReleaseRequests = starredRepos.count;

    __weak typeof(self) weakSelf = self;
    for (NSDictionary *repo in starredRepos) {
        NSDictionary *owner = [self safeDictForKey:@"owner" inDict:repo];
        NSString *ownerLogin = [self safeStringForKey:@"login" inDict:owner];
        NSString *repoName = [self safeStringForKey:@"name" inDict:repo];

        void (^stepDone)(void) = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.pendingReleaseRequests--;
            if (strongSelf.pendingReleaseRequests <= 0) {
                [strongSelf finishFeedWithEntries:collected];
            }
        };

        if (ownerLogin.length == 0 || repoName.length == 0) {
            stepDone();
            continue;
        }

        [[GHAPIClient sharedClient] releasesForOwner:ownerLogin repo:repoName completion:^(id jsonObject, NSError *error) {
            __strong typeof(weakSelf) strongSelfInner = weakSelf;
            if (strongSelfInner && !error && [jsonObject isKindOfClass:[NSArray class]] && [jsonObject count] > 0) {
                id latestRelease = jsonObject[0];
                if ([latestRelease isKindOfClass:[NSDictionary class]]) {
                    NSString *publishedAt = [strongSelfInner safeStringForKey:@"published_at" inDict:latestRelease];

                    if (publishedAt.length > 0) {
                        [collected addObject:@{@"repo": repo, @"release": latestRelease}];
                    }
                }
            }

            stepDone();
        }];
    }
}

- (void)finishFeedWithEntries:(NSMutableArray *)collected {
    [collected sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *dateA = [self safeStringForKey:@"published_at" inDict:a[@"release"]];
        NSString *dateB = [self safeStringForKey:@"published_at" inDict:b[@"release"]];

        return [dateB compare:dateA ?: @""];
    }];

    self.feedEntries = collected;
    self.loadAttempted = YES;
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    [self.tableView reloadData];
}

- (NSString *)relativeDateStringFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return @"";

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return @"";

    NSTimeInterval seconds = -[date timeIntervalSinceNow];
    if (seconds < 0) seconds = 0;

    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    NSInteger months = days / 30;
    NSInteger years = days / 365;

    if (minutes < 1) return GHL(@"сейчас");
    if (minutes < 60) return [NSString stringWithFormat:GHL(@"%ldмин"), (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:GHL(@"%ldч"), (long)hours];
    if (days < 30) return [NSString stringWithFormat:GHL(@"%ldдн"), (long)days];
    if (months < 12) return [NSString stringWithFormat:GHL(@"%ldмес"), (long)months];
    return [NSString stringWithFormat:GHL(@"%ldг"), (long)years];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.trendingRepos.count > 0 ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kExploreSectionTrending && self.trendingRepos.count > 0) {
        return self.trendingRepos.count;
    }

    if (![GHAuthManager sharedManager].isAuthenticated) return 0;
    return MAX(self.feedEntries.count, (NSUInteger)1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kExploreSectionTrending && self.trendingRepos.count > 0) {
        return GHL(@"Популярные репозитории");
    }
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == kExploreSectionFeed && [GHAuthManager sharedManager].isAuthenticated) {
        return GHThemedSectionHeaderView(GHL(@"Новые релизы"));
    }
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == kExploreSectionFeed && [GHAuthManager sharedManager].isAuthenticated) {
        return GHThemedSectionHeaderHeight(GHL(@"Новые релизы"));
    }
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kExploreSectionTrending && self.trendingRepos.count > 0) {
        return [self trendingCellForRowAtIndexPath:indexPath inTableView:tableView];
    }

    BOOL hasRealEntry = self.feedEntries.count > 0;

    if (!hasRealEntry) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPlaceholderCellID forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;

        cell.textLabel.text = self.loadAttempted ? GHL(@"Пока нет новых релизов в избранных репозиториях") : GHL(@"Загрузка…");
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    GHExploreFeedCell *cell = [tableView dequeueReusableCellWithIdentifier:kExploreCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();

    NSDictionary *entry = self.feedEntries[indexPath.row];
    NSDictionary *repo = entry[@"repo"];
    NSDictionary *release = entry[@"release"];
    NSString *publishedAt = [self safeStringForKey:@"published_at" inDict:release];

    [cell configureWithRepo:repo release:release relativeDate:[self relativeDateStringFromISOString:publishedAt]];

    return cell;
}

- (UITableViewCell *)trendingCellForRowAtIndexPath:(NSIndexPath *)indexPath inTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kTrendingCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kTrendingCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.numberOfLines = 1;

    GHTrendingRepo *repo = self.trendingRepos[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@/%@", repo.ownerLogin, repo.repoName];
    cell.textLabel.textColor = GHPrimaryTextColor();
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15];

    NSMutableString *subtitle = [NSMutableString string];
    if (repo.totalStarsText.length > 0) [subtitle appendFormat:@"★ %@", repo.totalStarsText];
    if (repo.language.length > 0) {
        if (subtitle.length > 0) [subtitle appendString:@" · "];
        [subtitle appendString:repo.language];
    }
    if (repo.starsThisWeekText.length > 0) {
        if (subtitle.length > 0) [subtitle appendString:@" · "];
        [subtitle appendString:[NSString stringWithFormat:GHL(@"+%@ за неделю"), repo.starsThisWeekText]];
    }
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.numberOfLines = 1;

    GHApplyDisclosureIndicator(cell);

    cell.imageView.image = [GHIconRenderer dotIconWithColor:[UIColor colorWithWhite:0.6 alpha:1.0] size:10];

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kExploreSectionTrending && self.trendingRepos.count > 0) {
        return 50;
    }

    BOOL hasRealEntry = self.feedEntries.count > 0;
    if (!hasRealEntry) return 60;

    NSDictionary *entry = self.feedEntries[indexPath.row];
    return [GHExploreFeedCell heightForEntryWithRepo:entry[@"repo"] release:entry[@"release"] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == kExploreSectionTrending && self.trendingRepos.count > 0) {
        GHTrendingRepo *trendingRepo = self.trendingRepos[indexPath.row];

        NSMutableDictionary *repoStub = [NSMutableDictionary dictionary];
        repoStub[@"name"] = trendingRepo.repoName ?: @"";
        repoStub[@"owner"] = @{@"login": trendingRepo.ownerLogin ?: @""};
        repoStub[@"full_name"] = [NSString stringWithFormat:@"%@/%@", trendingRepo.ownerLogin, trendingRepo.repoName];
        if (trendingRepo.repoDescription.length > 0) repoStub[@"description"] = trendingRepo.repoDescription;
        if (trendingRepo.language.length > 0) repoStub[@"language"] = trendingRepo.language;

        RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
        overviewVC.repo = repoStub;
        overviewVC.title = trendingRepo.repoName;
        [self.navigationController pushViewController:overviewVC animated:YES];
        return;
    }

    if (self.feedEntries.count == 0) return;

    NSDictionary *entry = self.feedEntries[indexPath.row];
    ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
    detailVC.releaseInfo = entry[@"release"];
    NSString *fullName = [self safeStringForKey:@"full_name" inDict:entry[@"repo"]];
    NSArray *fullNameParts = [fullName componentsSeparatedByString:@"/"];
    if (fullNameParts.count == 2) {
        detailVC.ownerLogin = fullNameParts[0];
        detailVC.repoName = fullNameParts[1];
    }
    [self.navigationController pushViewController:detailVC animated:YES];
}

#pragma mark - Вход

- (void)openSettingsFromPlaceholder {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)updateSignInHeader {
    if ([GHAuthManager sharedManager].isAuthenticated) {
        self.tableView.tableHeaderView = nil;
        return;
    }
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;
    self.tableView.tableHeaderView = GHSignInPlaceholderView(
        GHL(@"Войдите в аккаунт, чтобы видеть новости о релизах репозиториев в избранном"),
        width, self, @selector(openSettingsFromPlaceholder));
}

@end
