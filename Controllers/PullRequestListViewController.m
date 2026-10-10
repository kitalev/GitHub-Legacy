#import "PullRequestListViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "PullRequestDetailViewController.h"
#import "GHAPIClient.h"
#import "GHIconRenderer.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHPullRequestCell.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kPullRequestCellID = @"PullRequestCell";

@interface PullRequestListViewController () <UISearchBarDelegate>
@property (nonatomic, strong) NSMutableArray *openPullRequests;
@property (nonatomic, strong) NSMutableArray *closedPullRequests;
@property (nonatomic, assign) BOOL openLoaded;
@property (nonatomic, assign) BOOL closedLoaded;
@property (nonatomic, assign) BOOL openLoadAttempted;
@property (nonatomic, assign) BOOL closedLoadAttempted;

@property (nonatomic, assign) NSInteger openNextRawPage;
@property (nonatomic, assign) NSInteger closedNextRawPage;
@property (nonatomic, assign) BOOL openHasMore;
@property (nonatomic, assign) BOOL closedHasMore;
@property (nonatomic, assign) BOOL openLoadingMore;
@property (nonatomic, assign) BOOL closedLoadingMore;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *openChip;
@property (nonatomic, strong) UIButton *closedChip;
@property (nonatomic, assign) BOOL showingClosed;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *searchQuery;
@property (nonatomic, strong) NSMutableArray *searchResults;
@property (nonatomic, assign) BOOL searchAttempted;
@property (nonatomic, assign) BOOL searchLoading;
@property (nonatomic, strong) UIView *headerView;
@end

@implementation PullRequestListViewController

+ (BOOL)pullRequestListInfoFromURL:(NSURL *)url
                        ownerLogin:(NSString **)ownerLogin
                          repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/pulls/?(?:[?#].*)?$"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    return YES;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Пул-реквесты");
        _openPullRequests = [NSMutableArray array];
        _closedPullRequests = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.openChip = [self makeFilterChip];
    [self.openChip addTarget:self action:@selector(openChipTapped) forControlEvents:UIControlEventTouchUpInside];
    self.closedChip = [self makeFilterChip];
    [self.closedChip addTarget:self action:@selector(closedChipTapped) forControlEvents:UIControlEventTouchUpInside];
    [self updateFilterChipTitles];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 52, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = GHL(@"Поиск по pull request'ам");
    self.searchBar.delegate = self;

    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 96)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    headerView.backgroundColor = GHBackgroundColor();
    [headerView addSubview:self.openChip];
    [headerView addSubview:self.closedChip];
    [headerView addSubview:self.searchBar];
    self.tableView.tableHeaderView = headerView;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(reloadCurrentTab) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(reloadCurrentTab) forControlEvents:UIControlEventValueChanged];
    }

    self.headerView = headerView;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self loadStateIfNeeded:@"open"];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.headerView.backgroundColor = GHBackgroundColor();
    [self updateFilterChipAppearance];

    self.searchBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
    self.searchBar.backgroundImage = [self solidColorImage:self.headerView.backgroundColor];
    self.searchBar.tintColor = GHTintColor();

    [self.tableView reloadData];
}

- (UIImage *)solidColorImage:(UIColor *)color {
    CGRect rect = CGRectMake(0, 0, 1, 1);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    [color setFill];
    UIRectFill(rect);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
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

- (BOOL)isMerged:(NSDictionary *)pr {
    id mergedAt = pr[@"merged_at"];
    if (mergedAt != nil && ![mergedAt isKindOfClass:[NSNull class]]) return YES;

    id nested = pr[@"pull_request"];
    if ([nested isKindOfClass:[NSDictionary class]]) {
        id nestedMergedAt = nested[@"merged_at"];
        return nestedMergedAt != nil && ![nestedMergedAt isKindOfClass:[NSNull class]];
    }

    return NO;
}

- (BOOL)isOpenTabSelected {
    return !self.showingClosed;
}

- (UIButton *)makeFilterChip {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
    chip.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    chip.layer.cornerRadius = 16;
    chip.layer.masksToBounds = YES;
    chip.layer.borderWidth = 1;
    chip.contentEdgeInsets = UIEdgeInsetsMake(0, 16, 0, 16);
    return chip;
}

- (void)updateFilterChipTitles {
    [self.openChip setTitle:GHL(@"Открытые") forState:UIControlStateNormal];
    [self.closedChip setTitle:GHL(@"Закрытые") forState:UIControlStateNormal];
    CGFloat x = 12;
    for (UIButton *chip in @[self.openChip, self.closedChip]) {
        [chip sizeToFit];
        CGFloat width = MAX(chip.bounds.size.width, 64);
        chip.frame = CGRectMake(x, 12, width, 32);
        x += width + 8;
    }
}

- (void)updateFilterChipAppearance {
    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
    UIColor *activeColor = [UIColor colorWithRed:0.03 green:0.41 blue:0.85 alpha:1.0];
    UIColor *inactiveBackground = dark ? [UIColor colorWithWhite:1.0 alpha:0.08] : [UIColor colorWithWhite:0.0 alpha:0.05];
    NSArray *chips = @[self.openChip, self.closedChip];
    for (NSUInteger i = 0; i < chips.count; i++) {
        UIButton *chip = chips[i];
        BOOL active = (i == 1) == self.showingClosed;
        chip.backgroundColor = active ? activeColor : inactiveBackground;
        chip.layer.borderColor = (active ? activeColor : GHSeparatorColor()).CGColor;
        [chip setTitleColor:(active ? [UIColor whiteColor] : GHPrimaryTextColor()) forState:UIControlStateNormal];
        [chip setTitleColor:(active ? [UIColor colorWithWhite:1.0 alpha:0.6] : GHSecondaryTextColor()) forState:UIControlStateHighlighted];
    }
}

- (void)openChipTapped {
    if (!self.showingClosed) return;
    self.showingClosed = NO;
    [self updateFilterChipAppearance];
    [self segmentChanged];
}

- (void)closedChipTapped {
    if (self.showingClosed) return;
    self.showingClosed = YES;
    [self updateFilterChipAppearance];
    [self segmentChanged];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchQuery = searchText;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performServerSearch) object:nil];
    if (searchText.length == 0) {
        self.searchResults = nil;
        self.searchAttempted = NO;
        self.searchLoading = NO;
        [self.tableView reloadData];
        return;
    }

    [self performSelector:@selector(performServerSearch) withObject:nil afterDelay:0.4];
}

- (void)performServerSearch {
    NSString *query = self.searchQuery;
    if (query.length == 0) return;

    NSString *stateQualifier = [self isOpenTabSelected] ? @"is:open" : @"is:closed";
    NSString *scopedQuery = [NSString stringWithFormat:@"repo:%@/%@ is:pr %@ %@",
                              self.ownerLogin, self.repoName, stateQualifier, query];

    self.searchLoading = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    NSString *requestQuery = self.searchQuery;
    [[GHAPIClient sharedClient] searchIssuesAndPullRequestsWithQuery:scopedQuery completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf.searchQuery isEqualToString:requestQuery]) return;

        strongSelf.searchLoading = NO;
        strongSelf.searchAttempted = YES;

        NSArray *items = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject[@"items"] : nil;
        strongSelf.searchResults = [NSMutableArray arrayWithArray:[items isKindOfClass:[NSArray class]] ? items : @[]];
        [strongSelf.tableView reloadData];
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = nil;
    self.searchQuery = nil;
    self.searchResults = nil;
    self.searchAttempted = NO;
    self.searchLoading = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performServerSearch) object:nil];
    [searchBar resignFirstResponder];
    [self.tableView reloadData];
}

- (void)segmentChanged {
    if (self.searchQuery.length > 0) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performServerSearch) object:nil];
        [self performServerSearch];
        [self.tableView reloadData];
        return;
    }
    [self loadStateIfNeeded:[self isOpenTabSelected] ? @"open" : @"closed"];
    [self.tableView reloadData];
}

- (void)reloadCurrentTab {
    NSString *state = [self isOpenTabSelected] ? @"open" : @"closed";
    if ([state isEqualToString:@"open"]) {
        self.openLoaded = NO;
        self.openLoadingMore = NO;
    } else {
        self.closedLoaded = NO;
        self.closedLoadingMore = NO;
    }
    [self loadStateIfNeeded:state];
}

static const NSInteger kMaxPullRequestPages = 10;
static const NSInteger kPullRequestsPerPage = 100;

static const NSInteger kPullRequestsDisplayBatchSize = 25;

- (void)loadStateIfNeeded:(NSString *)state {
    BOOL isOpen = [state isEqualToString:@"open"];
    if (isOpen ? self.openLoaded : self.closedLoaded) {
        if (GHPullToRefreshAvailable()) { [self.refreshControl endRefreshing]; } else { [self.gh_legacyRefreshControl endRefreshing]; }
        return;
    }

    if (isOpen) {
        self.openNextRawPage = 1;
        self.openHasMore = YES;
    } else {
        self.closedNextRawPage = 1;
        self.closedHasMore = YES;
    }

    [self.spinner startAnimating];
    [self fetchPullRequestsBatchForState:state accumulator:[NSMutableArray array] isInitialLoad:YES];
}

- (void)loadMoreIfNeededForState:(NSString *)state {
    BOOL isOpen = [state isEqualToString:@"open"];
    BOOL loaded = isOpen ? self.openLoaded : self.closedLoaded;
    BOOL hasMore = isOpen ? self.openHasMore : self.closedHasMore;
    BOOL loadingMore = isOpen ? self.openLoadingMore : self.closedLoadingMore;
    if (!loaded || !hasMore || loadingMore) return;

    if (isOpen) {
        self.openLoadingMore = YES;
    } else {
        self.closedLoadingMore = YES;
    }
    [self.tableView reloadData];
    [self fetchPullRequestsBatchForState:state accumulator:[NSMutableArray array] isInitialLoad:NO];
}

- (void)fetchPullRequestsBatchForState:(NSString *)state accumulator:(NSMutableArray *)accumulator isInitialLoad:(BOOL)isInitialLoad {
    BOOL isOpen = [state isEqualToString:@"open"];
    NSInteger rawPage = isOpen ? self.openNextRawPage : self.closedNextRawPage;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] pullRequestsForOwner:self.ownerLogin repo:self.repoName state:state page:rawPage completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            [strongSelf.spinner stopAnimating];
            if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }
            if (isOpen) {
                strongSelf.openLoadAttempted = YES;
                strongSelf.openLoadingMore = NO;
            } else {
                strongSelf.closedLoadAttempted = YES;
                strongSelf.closedLoadingMore = NO;
            }
            [strongSelf.tableView reloadData];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        NSArray *rawItems = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        for (id entry in rawItems) {
            if ([entry isKindOfClass:[NSDictionary class]]) {
                [accumulator addObject:entry];
            }
        }

        BOOL rawPageWasLast = rawItems.count < kPullRequestsPerPage;
        NSInteger nextRawPage = rawPage + 1;
        BOOL hitPageCap = nextRawPage > kMaxPullRequestPages;
        BOOL enoughForBatch = accumulator.count >= kPullRequestsDisplayBatchSize;

        if (!rawPageWasLast && !hitPageCap && !enoughForBatch) {
            if (isOpen) {
                strongSelf.openNextRawPage = nextRawPage;
            } else {
                strongSelf.closedNextRawPage = nextRawPage;
            }
            [strongSelf fetchPullRequestsBatchForState:state accumulator:accumulator isInitialLoad:isInitialLoad];
            return;
        }

        BOOL hasMore = !rawPageWasLast && !hitPageCap;
        if (isOpen) {
            strongSelf.openNextRawPage = nextRawPage;
            strongSelf.openHasMore = hasMore;
            strongSelf.openLoaded = YES;
            strongSelf.openLoadAttempted = YES;
            strongSelf.openLoadingMore = NO;
        } else {
            strongSelf.closedNextRawPage = nextRawPage;
            strongSelf.closedHasMore = hasMore;
            strongSelf.closedLoaded = YES;
            strongSelf.closedLoadAttempted = YES;
            strongSelf.closedLoadingMore = NO;
        }

        NSMutableArray *target = isOpen ? strongSelf.openPullRequests : strongSelf.closedPullRequests;
        if (isInitialLoad) [target removeAllObjects];
        [target addObjectsFromArray:accumulator];

        [strongSelf.spinner stopAnimating];
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }
        [strongSelf.tableView reloadData];
    }];
}

- (NSMutableArray *)visiblePullRequests {
    if (self.searchQuery.length > 0) return self.searchResults ?: [NSMutableArray array];
    return [self isOpenTabSelected] ? self.openPullRequests : self.closedPullRequests;
}

- (NSString *)relativeDateStringFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return @"";

    NSDateFormatter *isoFormatter = GHISODateFormatter();

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return @"";

    NSTimeInterval seconds = -[date timeIntervalSinceNow];
    if (seconds < 0) seconds = 0;

    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    NSInteger months = days / 30;
    NSInteger years = days / 365;

    if (minutes < 1) return @"now";
    if (minutes < 60) return [NSString stringWithFormat:@"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:@"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:@"%ldd", (long)days];
    if (months < 12) return [NSString stringWithFormat:@"%ldmo", (long)months];
    return [NSString stringWithFormat:@"%ldy", (long)years];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX([self visiblePullRequests].count, (NSUInteger)1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *pullRequests = [self visiblePullRequests];
    BOOL wantOpen = [self isOpenTabSelected];
    BOOL attempted = wantOpen ? self.openLoadAttempted : self.closedLoadAttempted;

    if (pullRequests.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PullRequestEmptyCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PullRequestEmptyCell"];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.textLabel.numberOfLines = 1;
        if (self.searchQuery.length > 0) {
            cell.textLabel.text = self.searchLoading ? GHL(@"Поиск…")
                                 : self.searchAttempted ? GHL(@"Ничего не найдено")
                                 : GHL(@"Поиск…");
        } else if (!attempted) {
            cell.textLabel.text = GHL(@"Загрузка…");
        } else {
            cell.textLabel.text = wantOpen ? GHL(@"Открытых pull request'ов нет") : GHL(@"Закрытых pull request'ов нет");
        }
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    GHPullRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:kPullRequestCellID];
    if (!cell) {
        cell = [[GHPullRequestCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kPullRequestCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();

    NSDictionary *pr = pullRequests[indexPath.row];
    [cell configureWithPullRequest:pr isMerged:[self isMerged:pr]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *pullRequests = [self visiblePullRequests];
    if (pullRequests.count == 0) return 44;

    NSDictionary *pr = pullRequests[indexPath.row];
    return [GHPullRequestCell heightForPullRequest:pr width:tableView.bounds.size.width];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSMutableArray *pullRequests = [self visiblePullRequests];
    if (pullRequests.count == 0) return;

    NSDictionary *pr = pullRequests[indexPath.row];
    PullRequestDetailViewController *detailVC = [[PullRequestDetailViewController alloc] init];
    detailVC.pullRequest = pr;
    detailVC.ownerLogin = self.ownerLogin;
    detailVC.repoName = self.repoName;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.searchQuery.length > 0) return;
    NSMutableArray *pullRequests = [self visiblePullRequests];
    if (pullRequests.count == 0 || indexPath.row != (NSInteger)pullRequests.count - 1) return;
    [self loadMoreIfNeededForState:[self isOpenTabSelected] ? @"open" : @"closed"];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    BOOL isOpen = [self isOpenTabSelected];
    BOOL loadingMore = isOpen ? self.openLoadingMore : self.closedLoadingMore;
    if (!loadingMore) return nil;

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    UIActivityIndicatorView *footerSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    footerSpinner.center = CGPointMake(CGRectGetMidX(footer.bounds), CGRectGetMidY(footer.bounds));
    footerSpinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
        | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [footerSpinner startAnimating];
    [footer addSubview:footerSpinner];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    BOOL isOpen = [self isOpenTabSelected];
    BOOL loadingMore = isOpen ? self.openLoadingMore : self.closedLoadingMore;
    return loadingMore ? 44.0 : 0.0;
}

@end
