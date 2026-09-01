#import "ForkListViewController.h"
#import "GHAPIClient.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHStarredRepoCell.h"
#import "GHLocalization.h"

static NSString * const kForkCellID = @"ForkCell";

static NSString * const kForkEmptyCellID = @"ForkEmptyCell";

static const NSInteger kForksPerPage = 30;

static const NSInteger kMaxForksRawPages = 10;

static const NSInteger kForksDisplayBatchSize = 25;

static const NSInteger kPeriodActionSheetTag = 1;
static const NSInteger kSortActionSheetTag = 2;

@interface ForkListViewController ()
@property (nonatomic, strong) NSMutableArray *forks;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger nextRawPage;
@property (nonatomic, assign) BOOL hasMoreForks;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL loadAttempted;

@property (nonatomic, assign) BOOL loadInProgress;

@property (nonatomic, copy) NSString *selectedSortValue;
@property (nonatomic, assign) NSInteger selectedPeriodYears;
@property (nonatomic, strong) UIButton *periodButton;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UIView *headerView;

@property (nonatomic, strong) UIActionSheet *presentedActionSheet;
@end

@implementation ForkListViewController

+ (BOOL)forkListInfoFromURL:(NSURL *)url
                  ownerLogin:(NSString **)ownerLogin
                    repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *forksRegex = nil;
    static NSRegularExpression *networkMembersRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        forksRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/forks/?(?:[?#].*)?$"
                                                                 options:NSRegularExpressionCaseInsensitive
                                                                   error:nil];
        networkMembersRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/network/members/?(?:[?#].*)?$"
                                                                          options:NSRegularExpressionCaseInsensitive
                                                                            error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [forksRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) {
        match = [networkMembersRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    }
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    return YES;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Форки");
        _forks = [NSMutableArray array];
        _selectedSortValue = @"newest";
        _selectedPeriodYears = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[GHStarredRepoCell class] forCellReuseIdentifier:kForkCellID];
    self.tableView.tableHeaderView = [self buildHeaderView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reloadForks) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self reloadForks];
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Форки");
    [self updateFilterButtonTitles];
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Заголовок с фильтрами

- (UIView *)buildHeaderView {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.periodButton = [self filterButtonWithFrame:CGRectMake(10, 8, (headerView.bounds.size.width - 26) / 2.0, 36)];
    [self.periodButton addTarget:self action:@selector(periodButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.periodButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerView addSubview:self.periodButton];

    self.sortButton = [self filterButtonWithFrame:CGRectMake(headerView.bounds.size.width / 2.0 + 3, 8, (headerView.bounds.size.width - 26) / 2.0, 36)];
    [self.sortButton addTarget:self action:@selector(sortButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.sortButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleWidth;
    [headerView addSubview:self.sortButton];

    self.headerView = headerView;
    [self updateFilterButtonTitles];
    return headerView;
}

- (UIButton *)filterButtonWithFrame:(CGRect)frame {

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.7;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 6, 0, 6);
    return button;
}

- (NSString *)periodDisplayNameForYears:(NSInteger)years {
    if (years == 0) return GHL(@"Всё время");
    if (years == 1) return GHL(@"Последний год");
    return [NSString stringWithFormat:GHL(@"Последние %ld года"), (long)years];
}

- (NSString *)sortDisplayNameForValue:(NSString *)value {
    if ([value isEqualToString:@"stargazers"]) return GHL(@"По звёздам");
    if ([value isEqualToString:@"oldest"]) return GHL(@"Сначала старые");
    return GHL(@"Сначала новые");
}

- (void)updateFilterButtonTitles {

    NSString *periodTitle = [NSString stringWithFormat:@"%@ ▾", [self periodDisplayNameForYears:self.selectedPeriodYears]];
    NSString *sortTitle = [NSString stringWithFormat:@"%@ ▾", [self sortDisplayNameForValue:self.selectedSortValue]];
    [self.periodButton setTitle:periodTitle forState:UIControlStateNormal];
    [self.sortButton setTitle:sortTitle forState:UIControlStateNormal];
}

- (void)periodButtonTapped {
    if (self.presentedActionSheet) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                          destructiveButtonTitle:nil
                                               otherButtonTitles:GHL(@"Всё время"),
                                                                  GHL(@"Последний год"),
                                                                  GHL(@"Последние 2 года"), nil];
    sheet.tag = kPeriodActionSheetTag;
    self.presentedActionSheet = sheet;
    [sheet showInView:[self actionSheetHostView]];
}

- (void)sortButtonTapped {
    if (self.presentedActionSheet) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                          destructiveButtonTitle:nil
                                               otherButtonTitles:GHL(@"Сначала новые"),
                                                                  GHL(@"По звёздам"),
                                                                  GHL(@"Сначала старые"), nil];
    sheet.tag = kSortActionSheetTag;
    self.presentedActionSheet = sheet;
    [sheet showInView:[self actionSheetHostView]];
}

- (UIView *)actionSheetHostView {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    return keyWindow ?: self.view.window ?: self.navigationController.view ?: self.view;
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet == self.presentedActionSheet) self.presentedActionSheet = nil;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (actionSheet.tag == kPeriodActionSheetTag) {
        NSArray *years = @[@0, @1, @2];
        if ((NSUInteger)buttonIndex >= years.count) return;
        NSInteger newValue = [years[buttonIndex] integerValue];
        if (newValue == self.selectedPeriodYears) return;
        self.selectedPeriodYears = newValue;
        [self updateFilterButtonTitles];

        [self reloadForks];
        return;
    }

    if (actionSheet.tag == kSortActionSheetTag) {
        NSArray *values = @[@"newest", @"stargazers", @"oldest"];
        if ((NSUInteger)buttonIndex >= values.count) return;
        NSString *newValue = values[buttonIndex];
        if ([newValue isEqualToString:self.selectedSortValue]) return;
        self.selectedSortValue = newValue;
        [self updateFilterButtonTitles];
        [self reloadForks];
        return;
    }
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();

    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
    self.headerView.backgroundColor = isDark ? [UIColor colorWithWhite:0.13 alpha:1.0] : [UIColor colorWithWhite:0.94 alpha:1.0];

    for (UIButton *button in @[self.periodButton, self.sortButton]) {
        [button setBackgroundImage:nil forState:UIControlStateNormal];
        button.backgroundColor = GHCellBackgroundColor();
        [button setTitleColor:GHPrimaryTextColor() forState:UIControlStateNormal];
        button.layer.borderColor = GHSeparatorColor().CGColor;
    }

    [self.tableView reloadData];
}

- (BOOL)passesPeriodFilter:(NSDictionary *)fork {
    if (self.selectedPeriodYears == 0) return YES;

    NSString *createdAt = [fork[@"created_at"] isKindOfClass:[NSString class]] ? fork[@"created_at"] : nil;
    if (createdAt.length == 0) return YES;

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    NSDate *date = [isoFormatter dateFromString:createdAt];
    if (!date) return YES;

    NSTimeInterval secondsInPeriod = self.selectedPeriodYears * 365.25 * 24 * 60 * 60;
    return -[date timeIntervalSinceNow] <= secondsInPeriod;
}

- (void)reloadForks {
    self.nextRawPage = 1;
    self.hasMoreForks = YES;
    self.loadingMore = NO;
    self.loadAttempted = NO;
    self.loadInProgress = YES;
    [self.forks removeAllObjects];
    [self.tableView reloadData];
    [self.spinner startAnimating];
    [self fetchForksBatchWithAccumulator:[NSMutableArray array] isInitialLoad:YES];
}

- (void)fetchForksBatchWithAccumulator:(NSMutableArray *)accumulator isInitialLoad:(BOOL)isInitialLoad {
    NSInteger requestedPage = self.nextRawPage;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] forksForOwner:self.ownerLogin
                                          repo:self.repoName
                                          sort:self.selectedSortValue
                                          page:requestedPage
                                    completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            [strongSelf.spinner stopAnimating];
            [strongSelf.refreshControl endRefreshing];
            strongSelf.loadingMore = NO;
            strongSelf.loadAttempted = YES;
            strongSelf.loadInProgress = NO;
            if (isInitialLoad) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                                 message:error.localizedDescription
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                [alert show];
            }
            [strongSelf.tableView reloadData];
            return;
        }

        NSArray *pageEntries = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        for (NSDictionary *fork in pageEntries) {
            if (![fork isKindOfClass:[NSDictionary class]]) continue;
            if ([strongSelf passesPeriodFilter:fork]) [accumulator addObject:fork];
        }

        BOOL rawPageWasLast = pageEntries.count < kForksPerPage;
        NSInteger nextRawPage = strongSelf.nextRawPage + 1;
        BOOL hitPageCap = nextRawPage > kMaxForksRawPages;
        BOOL enoughForBatch = accumulator.count >= kForksDisplayBatchSize;

        if (!rawPageWasLast && !hitPageCap && !enoughForBatch) {
            strongSelf.nextRawPage = nextRawPage;
            [strongSelf fetchForksBatchWithAccumulator:accumulator isInitialLoad:isInitialLoad];
            return;
        }

        strongSelf.nextRawPage = nextRawPage;
        strongSelf.hasMoreForks = !rawPageWasLast && !hitPageCap;
        strongSelf.loadAttempted = YES;
        strongSelf.loadingMore = NO;
        strongSelf.loadInProgress = NO;

        if (isInitialLoad) [strongSelf.forks removeAllObjects];
        [strongSelf.forks addObjectsFromArray:accumulator];

        [strongSelf.spinner stopAnimating];
        [strongSelf.refreshControl endRefreshing];
        [strongSelf.tableView reloadData];
    }];
}

- (void)loadMoreForksIfNeeded {
    if (!self.hasMoreForks || self.loadingMore) return;
    self.loadingMore = YES;
    [self.tableView reloadData];
    [self fetchForksBatchWithAccumulator:[NSMutableArray array] isInitialLoad:NO];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.forks.count > 0) return self.forks.count;

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kForkEmptyCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kForkEmptyCellID];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = GHSecondaryTextColor();
        if (self.loadInProgress || !self.loadAttempted) {
            cell.textLabel.text = GHL(@"Загрузка…");
        } else {
            cell.textLabel.text = self.selectedPeriodYears > 0
                ? GHL(@"За выбранный период форков не найдено — попробуйте расширить период")
                : GHL(@"У репозитория пока нет форков");
        }
        return cell;
    }

    GHStarredRepoCell *cell = [tableView dequeueReusableCellWithIdentifier:kForkCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    [cell configureWithRepo:self.forks[indexPath.row]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0) {

        CGFloat headerHeight = self.tableView.tableHeaderView.frame.size.height;
        return MAX(120, tableView.bounds.size.height - headerHeight);
    }
    return [GHStarredRepoCell heightForRepo:self.forks[indexPath.row] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0 || indexPath.row != (NSInteger)self.forks.count - 1) return;
    [self loadMoreForksIfNeeded];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (!self.loadingMore) return nil;

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
    return self.loadingMore ? 44.0 : 0.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *repo = self.forks[indexPath.row];
    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = repo[@"name"];
    [self.navigationController pushViewController:overviewVC animated:YES];
}

@end
