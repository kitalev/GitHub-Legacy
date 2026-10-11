#import "IssueListViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "IssueDetailViewController.h"
#import "GHAPIClient.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHIssueCell.h"
#import "GHAuthManager.h"
#import "GHIssueTemplate.h"
#import "IssueTemplatePickerViewController.h"
#import "NewIssueViewController.h"
#import "SignInOptionsViewController.h"

static NSString * const kIssueCellID = @"IssueCell";
static NSString * const kIssueEmptyCellID = @"IssueEmptyCell";

static const NSInteger kNewIssueLoginAlertTag = 1;
static const NSInteger kNewIssueTemplatesErrorAlertTag = 2;

@interface IssueListViewController () <UISearchBarDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) NSMutableArray *openIssues;
@property (nonatomic, strong) NSMutableArray *closedIssues;
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
@property (nonatomic, strong) UIBarButtonItem *createIssueItem;
@property (nonatomic, strong) GHIssueTemplateSet *templateSet;
@property (nonatomic, assign) BOOL loadingTemplates;
@end

@implementation IssueListViewController

+ (BOOL)issueListInfoFromURL:(NSURL *)url
                  ownerLogin:(NSString **)ownerLogin
                    repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/issues/?(?:[?#].*)?$"
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

+ (BOOL)issueNumberFromURL:(NSURL *)url
                 ownerLogin:(NSString **)ownerLogin
                   repoName:(NSString **)repoName
                     number:(NSInteger *)number {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/issues/([0-9]+)"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    if (number != NULL) *number = [[urlString substringWithRange:[match rangeAtIndex:3]] integerValue];
    return YES;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Задачи");
        _openIssues = [NSMutableArray array];
        _closedIssues = [NSMutableArray array];
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
    self.searchBar.placeholder = GHL(@"Поиск по задачам");
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
    self.createIssueItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                       target:self
                                                                       action:@selector(newIssueTapped)];
    self.navigationItem.rightBarButtonItems = @[self.createIssueItem,
                                                [[UIBarButtonItem alloc] initWithCustomView:self.spinner]];

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

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self loadStateIfNeeded:@"open"];
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Задачи");

    [self updateFilterChipTitles];
    self.searchBar.placeholder = GHL(@"Поиск по задачам");
    [self.tableView reloadData];
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
    [self layoutFilterChips];
}

- (void)layoutFilterChips {
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

- (void)segmentChanged {
    if (self.searchQuery.length > 0) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(performServerSearch) object:nil];
        [self performServerSearch];
    } else {
        [self loadStateIfNeeded:[self isOpenTabSelected] ? @"open" : @"closed"];
    }
    [self.tableView reloadData];
}

#pragma mark - New issue

- (void)newIssueTapped {
    if (![GHAuthManager sharedManager].isAuthenticated) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Нужен вход")
                                                         message:GHL(@"Чтобы создать задачу, войдите в аккаунт в настройках.")
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                               otherButtonTitles:GHL(@"Войти"), nil];
        alert.tag = kNewIssueLoginAlertTag;
        [alert show];
        return;
    }

    if (self.templateSet) {
        [self presentNewIssueFlow];
        return;
    }
    if (self.loadingTemplates) return;

    self.loadingTemplates = YES;
    self.createIssueItem.enabled = NO;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [GHIssueTemplateSet loadForOwner:self.ownerLogin repo:self.repoName completion:^(GHIssueTemplateSet *templateSet, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.loadingTemplates = NO;
        strongSelf.createIssueItem.enabled = YES;
        [strongSelf.spinner stopAnimating];

        if (templateSet == nil) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось загрузить шаблоны задач")
                                                             message:error.localizedDescription
                                                            delegate:strongSelf
                                                   cancelButtonTitle:GHL(@"Отмена")
                                                   otherButtonTitles:GHL(@"Продолжить без шаблона"), nil];
            alert.tag = kNewIssueTemplatesErrorAlertTag;
            [alert show];
            return;
        }

        strongSelf.templateSet = templateSet;
        [strongSelf presentNewIssueFlow];
    }];
}

- (void)presentNewIssueFlow {
    if (!self.templateSet.hasChoices) {
        [self pushComposerWithTemplate:self.templateSet.legacyTemplate];
        return;
    }

    IssueTemplatePickerViewController *pickerVC = [[IssueTemplatePickerViewController alloc] init];
    pickerVC.ownerLogin = self.ownerLogin;
    pickerVC.repoName = self.repoName;
    pickerVC.templateSet = self.templateSet;
    pickerVC.onIssueCreated = [self issueCreatedHandler];
    [self.navigationController pushViewController:pickerVC animated:YES];
}

- (void)pushComposerWithTemplate:(GHIssueTemplate *)issueTemplate {
    NewIssueViewController *composer = [[NewIssueViewController alloc] init];
    composer.ownerLogin = self.ownerLogin;
    composer.repoName = self.repoName;
    composer.issueTemplate = issueTemplate;
    composer.onIssueCreated = [self issueCreatedHandler];
    [self.navigationController pushViewController:composer animated:YES];
}

- (void (^)(NSDictionary *))issueCreatedHandler {
    __weak typeof(self) weakSelf = self;
    return ^(NSDictionary *issue) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.openLoaded = NO;
        strongSelf.openLoadingMore = NO;
        if ([strongSelf isOpenTabSelected] && strongSelf.searchQuery.length == 0) {
            [strongSelf loadStateIfNeeded:@"open"];
        }

        IssueDetailViewController *detailVC = [[IssueDetailViewController alloc] init];
        detailVC.issue = issue;
        detailVC.ownerLogin = strongSelf.ownerLogin;
        detailVC.repoName = strongSelf.repoName;

        NSArray *stack = strongSelf.navigationController.viewControllers;
        NSUInteger index = [stack indexOfObject:strongSelf];
        if (index == NSNotFound) {
            [strongSelf.navigationController pushViewController:detailVC animated:YES];
            return;
        }
        NSArray *newStack = [[stack subarrayWithRange:NSMakeRange(0, index + 1)] arrayByAddingObject:detailVC];
        [strongSelf.navigationController setViewControllers:newStack animated:YES];
    };
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if (alertView.tag == kNewIssueLoginAlertTag) {
        SignInOptionsViewController *signInVC = [[SignInOptionsViewController alloc] init];
        [self.navigationController pushViewController:signInVC animated:YES];
    } else if (alertView.tag == kNewIssueTemplatesErrorAlertTag) {
        [self pushComposerWithTemplate:nil];
    }
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

    NSString *type = @"issue";
    NSString *stateQualifier = [self isOpenTabSelected] ? @"is:open" : @"is:closed";
    NSString *scopedQuery = [NSString stringWithFormat:@"repo:%@/%@ is:%@ %@ %@",
                              self.ownerLogin, self.repoName, type, stateQualifier, query];

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

static const NSInteger kMaxIssuePages = 10;
static const NSInteger kIssuesPerPage = 100;

static const NSInteger kIssuesDisplayBatchSize = 25;

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
    [self fetchIssuesBatchForState:state accumulator:[NSMutableArray array] isInitialLoad:YES];
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
    [self fetchIssuesBatchForState:state accumulator:[NSMutableArray array] isInitialLoad:NO];
}

- (void)fetchIssuesBatchForState:(NSString *)state accumulator:(NSMutableArray *)accumulator isInitialLoad:(BOOL)isInitialLoad {
    BOOL isOpen = [state isEqualToString:@"open"];
    NSInteger rawPage = isOpen ? self.openNextRawPage : self.closedNextRawPage;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] issuesForOwner:self.ownerLogin repo:self.repoName state:state page:rawPage completion:^(id jsonObject, NSError *error) {
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
            if (![entry isKindOfClass:[NSDictionary class]]) continue;

            if ([strongSelf safeDictForKey:@"pull_request" inDict:entry] != nil) continue;
            [accumulator addObject:entry];
        }

        BOOL rawPageWasLast = rawItems.count < kIssuesPerPage;
        NSInteger nextRawPage = rawPage + 1;
        BOOL hitPageCap = nextRawPage > kMaxIssuePages;
        BOOL enoughForBatch = accumulator.count >= kIssuesDisplayBatchSize;

        if (!rawPageWasLast && !hitPageCap && !enoughForBatch) {
            if (isOpen) {
                strongSelf.openNextRawPage = nextRawPage;
            } else {
                strongSelf.closedNextRawPage = nextRawPage;
            }
            [strongSelf fetchIssuesBatchForState:state accumulator:accumulator isInitialLoad:isInitialLoad];
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

        NSMutableArray *target = isOpen ? strongSelf.openIssues : strongSelf.closedIssues;
        if (isInitialLoad) [target removeAllObjects];
        [target addObjectsFromArray:accumulator];

        [strongSelf.spinner stopAnimating];
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }
        [strongSelf.tableView reloadData];
    }];
}

- (NSMutableArray *)visibleIssues {
    if (self.searchQuery.length > 0) return self.searchResults ?: [NSMutableArray array];
    return [self isOpenTabSelected] ? self.openIssues : self.closedIssues;
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
    return MAX([self visibleIssues].count, (NSUInteger)1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *issues = [self visibleIssues];
    BOOL wantOpen = [self isOpenTabSelected];
    BOOL attempted = wantOpen ? self.openLoadAttempted : self.closedLoadAttempted;

    if (issues.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kIssueEmptyCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kIssueEmptyCellID];
        }
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.numberOfLines = 2;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = GHSecondaryTextColor();
        if (self.searchQuery.length > 0) {
            cell.textLabel.text = self.searchLoading ? GHL(@"Поиск…")
                                 : self.searchAttempted ? GHL(@"Ничего не найдено")
                                 : GHL(@"Поиск…");
        } else if (!attempted) {
            cell.textLabel.text = GHL(@"Загрузка…");
        } else {
            cell.textLabel.text = wantOpen ? GHL(@"Открытых issues нет") : GHL(@"Закрытых issues нет");
        }
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    GHIssueCell *cell = [tableView dequeueReusableCellWithIdentifier:kIssueCellID];
    if (!cell) {
        cell = [[GHIssueCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kIssueCellID];
    }
    cell.backgroundColor = GHCellBackgroundColor();

    NSDictionary *issue = issues[indexPath.row];
    [cell configureWithIssue:issue];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSMutableArray *issues = [self visibleIssues];
    if (issues.count == 0) return 44;

    NSDictionary *issue = issues[indexPath.row];
    return [GHIssueCell heightForIssue:issue width:tableView.bounds.size.width];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSMutableArray *issues = [self visibleIssues];
    if (issues.count == 0) return;

    NSDictionary *issue = issues[indexPath.row];
    IssueDetailViewController *detailVC = [[IssueDetailViewController alloc] init];
    detailVC.issue = issue;
    detailVC.ownerLogin = self.ownerLogin;
    detailVC.repoName = self.repoName;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.searchQuery.length > 0) return;
    NSMutableArray *issues = [self visibleIssues];
    if (issues.count == 0 || indexPath.row != (NSInteger)issues.count - 1) return;
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
