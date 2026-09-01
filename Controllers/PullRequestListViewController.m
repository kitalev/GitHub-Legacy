#import "PullRequestListViewController.h"
#import "PullRequestDetailViewController.h"
#import "GHAPIClient.h"
#import "GHIconRenderer.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHPullRequestCell.h"

static NSString * const kPullRequestCellID = @"PullRequestCell";

@interface PullRequestListViewController ()
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
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
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

    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[GHL(@"Открытые"), GHL(@"Закрытые")]];
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.frame = CGRectMake(10, 8, self.view.bounds.size.width - 20, 30);
    self.segmentedControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.segmentedControl addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];

    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 46)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    headerView.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
    [headerView addSubview:self.segmentedControl];
    self.tableView.tableHeaderView = headerView;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reloadCurrentTab) forControlEvents:UIControlEventValueChanged];

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
    self.headerView.backgroundColor = dark ? [UIColor colorWithWhite:0.13 alpha:1.0] : [UIColor colorWithWhite:0.94 alpha:1.0];
    [self.tableView reloadData];
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
    return mergedAt != nil && ![mergedAt isKindOfClass:[NSNull class]];
}

- (BOOL)isOpenTabSelected {
    return self.segmentedControl.selectedSegmentIndex == 0;
}

- (void)segmentChanged {
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
        [self.refreshControl endRefreshing];
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
            [strongSelf.refreshControl endRefreshing];
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
        [strongSelf.refreshControl endRefreshing];
        [strongSelf.tableView reloadData];
    }];
}

- (NSMutableArray *)visiblePullRequests {
    return [self isOpenTabSelected] ? self.openPullRequests : self.closedPullRequests;
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
        if (!attempted) {
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
