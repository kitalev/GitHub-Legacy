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
static const NSInteger kFilterSheetTag = 1;
static const NSInteger kLabelSheetTag = 2;

@interface IssueListViewController () <UISearchBarDelegate, UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIButton *filterButton;
@property (nonatomic, copy) NSString *filterQualifier;
@property (nonatomic, copy) NSString *filterTitleKey;
@property (nonatomic, copy) NSString *filterLabel;
@property (nonatomic, copy) NSArray *filterActions;
@property (nonatomic, copy) NSArray *labelNames;
@property (nonatomic, assign) NSInteger searchGeneration;

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
@property (nonatomic, strong) UISegmentedControl *stateControl;
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

    self.stateControl = [[UISegmentedControl alloc] initWithItems:@[GHL(@"Открытые"), GHL(@"Закрытые")]];
    self.stateControl.selectedSegmentIndex = 0;
    self.stateControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.stateControl addTarget:self action:@selector(stateControlChanged) forControlEvents:UIControlEventValueChanged];

    self.filterButton = GHMakeButton(GHButtonStyleSecondary);
    self.filterButton.contentEdgeInsets = UIEdgeInsetsZero;
    self.filterButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.filterButton addTarget:self action:@selector(filterTapped) forControlEvents:UIControlEventTouchUpInside];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 52, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = GHL(@"Поиск по задачам");
    self.searchBar.delegate = self;

    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 96)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    headerView.backgroundColor = GHBackgroundColor();
    [headerView addSubview:self.stateControl];
    [headerView addSubview:self.filterButton];
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

- (void)updateFilterChipTitles {
    [self.stateControl setTitle:GHL(@"Открытые") forSegmentAtIndex:0];
    [self.stateControl setTitle:GHL(@"Закрытые") forSegmentAtIndex:1];
}

- (void)updateFilterChipAppearance {
    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
    self.stateControl.segmentedControlStyle = dark ? UISegmentedControlStyleBar : UISegmentedControlStylePlain;
    self.stateControl.tintColor = dark ? [UIColor colorWithWhite:0.32 alpha:1.0] : nil;
    CGFloat width = self.headerView.bounds.size.width;
    self.stateControl.frame = CGRectMake(10, dark ? 11 : 10, width - 20 - 52, dark ? 30 : 32);
    self.filterButton.frame = CGRectMake(width - 10 - 44, 10, 44, 32);
    BOOL active = self.filterQualifier.length > 0;
    GHStyleButton(self.filterButton, active ? GHButtonStylePrimary : GHButtonStyleSecondary);
    UIImage *icon = [GHIconRenderer filterIconWithColor:active ? [UIColor whiteColor] : GHAccentColor() size:18];
    [self.filterButton setImage:icon forState:UIControlStateNormal];
}

- (BOOL)isFiltering {
    return self.searchQuery.length > 0 || self.filterQualifier.length > 0;
}

- (NSString *)filterDisplayTitle {
    if (self.filterLabel.length > 0) return [NSString stringWithFormat:GHL(@"метка «%@»"), self.filterLabel];
    return self.filterTitleKey.length > 0 ? GHL(self.filterTitleKey) : nil;
}

- (void)filterTapped {
    [self.searchBar resignFirstResponder];
    BOOL signedIn = [GHAuthManager sharedManager].isAuthenticated;
    NSMutableArray *actions = [NSMutableArray array];
    [actions addObject:@[@"Все задачи", @""]];
    if (signedIn) {
        [actions addObject:@[@"Созданные мной", @"author:@me"]];
        [actions addObject:@[@"Назначенные мне", @"assignee:@me"]];
        [actions addObject:@[@"Упоминают меня", @"mentions:@me"]];
    }
    [actions addObject:@[@"Без исполнителя", @"no:assignee"]];
    [actions addObject:@[@"Без комментариев", @"comments:0"]];
    [actions addObject:@[@"По метке…", @"label"]];
    self.filterActions = actions;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:GHL(@"Фильтр задач")
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSArray *action in actions) {
        BOOL current = [action[1] isEqualToString:@"label"] ? self.filterLabel.length > 0
                                                            : [action[1] isEqualToString:self.filterQualifier ?: @""] && self.filterLabel.length == 0;
        [sheet addButtonWithTitle:current ? [@"✓ " stringByAppendingString:GHL(action[0])] : GHL(action[0])];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:GHL(@"Отмена")];
    sheet.tag = kFilterSheetTag;
    [self showActionSheet:sheet];
}

- (void)showActionSheet:(UIActionSheet *)sheet {
    if (self.tabBarController.tabBar && !self.tabBarController.tabBar.hidden) {
        [sheet showFromTabBar:self.tabBarController.tabBar];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0) return;
    if (actionSheet.tag == kLabelSheetTag) {
        if (buttonIndex >= (NSInteger)self.labelNames.count) return;
        NSString *label = self.labelNames[buttonIndex];
        [self applyFilterQualifier:[NSString stringWithFormat:@"label:\"%@\"", label] titleKey:nil label:label];
        return;
    }
    if (buttonIndex >= (NSInteger)self.filterActions.count) return;
    NSArray *action = self.filterActions[buttonIndex];
    if ([action[1] isEqualToString:@"label"]) {
        [self presentLabelPicker];
        return;
    }
    [self applyFilterQualifier:action[1] titleKey:[action[1] length] > 0 ? action[0] : nil label:nil];
}

- (void)presentLabelPicker {
    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] labelsForOwner:self.ownerLogin repo:self.repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *label in [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[]) {
            if ([label isKindOfClass:[NSDictionary class]] && [label[@"name"] isKindOfClass:[NSString class]]) [names addObject:label[@"name"]];
        }
        if (names.count == 0) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Меток нет")
                                                             message:error.localizedDescription ?: GHL(@"В этом репозитории нет меток.")
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }
        strongSelf.labelNames = names;
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:GHL(@"Метка")
                                                           delegate:strongSelf
                                                  cancelButtonTitle:nil
                                             destructiveButtonTitle:nil
                                                  otherButtonTitles:nil];
        for (NSString *name in names) [sheet addButtonWithTitle:GHEmojiForDisplay(name)];
        sheet.cancelButtonIndex = [sheet addButtonWithTitle:GHL(@"Отмена")];
        sheet.tag = kLabelSheetTag;
        [strongSelf showActionSheet:sheet];
    }];
}

- (void)applyFilterQualifier:(NSString *)qualifier titleKey:(NSString *)titleKey label:(NSString *)label {
    self.filterQualifier = qualifier.length > 0 ? qualifier : nil;
    self.filterTitleKey = titleKey;
    self.filterLabel = label;
    [self updateFilterChipAppearance];
    self.searchResults = nil;
    self.searchAttempted = NO;
    if ([self isFiltering]) {
        [self performServerSearch];
    } else {
        self.searchLoading = NO;
        [self loadStateIfNeeded:[self isOpenTabSelected] ? @"open" : @"closed"];
    }
    [self.tableView reloadData];
}

- (void)stateControlChanged {
    BOOL closed = self.stateControl.selectedSegmentIndex == 1;
    if (closed == self.showingClosed) return;
    self.showingClosed = closed;
    [self segmentChanged];
}

- (void)segmentChanged {
    if ([self isFiltering]) {
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
    if (searchText.length == 0 && self.filterQualifier.length > 0) {
        [self performServerSearch];
        return;
    }
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
    if (![self isFiltering]) return;
    NSString *query = self.searchQuery ?: @"";

    NSString *type = @"issue";
    NSString *stateQualifier = [self isOpenTabSelected] ? @"is:open" : @"is:closed";
    NSString *scopedQuery = [NSString stringWithFormat:@"repo:%@/%@ is:%@ %@ %@ %@",
                              self.ownerLogin, self.repoName, type, stateQualifier, self.filterQualifier ?: @"", query];
    NSInteger generation = ++self.searchGeneration;

    self.searchLoading = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] searchIssuesAndPullRequestsWithQuery:scopedQuery completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (generation != strongSelf.searchGeneration) return;
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }

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
    if (self.filterQualifier.length > 0) [self performServerSearch];
    [self.tableView reloadData];
}

- (void)reloadCurrentTab {
    if ([self isFiltering]) {
        [self performServerSearch];
        return;
    }
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
    if ([self isFiltering]) return self.searchResults ?: [NSMutableArray array];
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
        if ([self isFiltering]) {
            NSString *filterTitle = [self filterDisplayTitle];
            NSString *nothing = filterTitle.length > 0 && self.searchQuery.length == 0
                ? [NSString stringWithFormat:GHL(@"Нет задач по фильтру: %@"), filterTitle]
                : GHL(@"Ничего не найдено");
            cell.textLabel.text = self.searchLoading ? GHL(@"Поиск…")
                                 : self.searchAttempted ? nothing
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
    if ([self isFiltering]) return;
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
