#import "RepoSearchViewController.h"
#import "GHAPIClient.h"
#import "RepoOverviewViewController.h"
#import "SettingsViewController.h"
#import "GHAvatarLoader.h"
#import "GHIconRenderer.h"
#import "GHThemeManager.h"
#import "IssueDetailViewController.h"
#import "PullRequestDetailViewController.h"
#import "PublicProfileViewController.h"
#import "GHLocalization.h"

static const NSInteger kClearHistoryAlertTag = 3;

static NSString * const kSearchHistoryDefaultsKey = @"GHSearchHistory";
static const NSUInteger kSearchHistoryMaxCount = 15;

typedef NS_ENUM(NSInteger, GHSearchScope) {
    GHSearchScopeRepositories = 0,
    GHSearchScopeIssuesAndPullRequests = 1,
    GHSearchScopeUsers = 2
};

@interface RepoSearchViewController ()
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSMutableArray *results;
@property (nonatomic, assign) GHSearchScope resultsScope;
@property (nonatomic, strong) NSMutableArray *searchHistory;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIToolbar *keyboardDismissToolbar;
@property (nonatomic, strong) UIBarButtonItem *keyboardDismissButton;
@end

@implementation RepoSearchViewController

- (id)init {

    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Поиск");
        _results = [NSMutableArray array];
        [self loadSearchHistory];
    }
    return self;
}

- (void)loadSearchHistory {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kSearchHistoryDefaultsKey];
    _searchHistory = [NSMutableArray arrayWithArray:[saved isKindOfClass:[NSArray class]] ? saved : @[]];
}

- (void)saveSearchHistory {
    [[NSUserDefaults standardUserDefaults] setObject:self.searchHistory forKey:kSearchHistoryDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)recordSearchQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    NSUInteger existingIndex = [self.searchHistory indexOfObjectPassingTest:^BOOL(NSString *item, NSUInteger idx, BOOL *stop) {
        return [item caseInsensitiveCompare:trimmed] == NSOrderedSame;
    }];
    if (existingIndex != NSNotFound) {
        [self.searchHistory removeObjectAtIndex:existingIndex];
    }
    [self.searchHistory insertObject:trimmed atIndex:0];
    while (self.searchHistory.count > kSearchHistoryMaxCount) {
        [self.searchHistory removeLastObject];
    }
    [self saveSearchHistory];
}

- (void)clearSearchHistory {
    [self.searchHistory removeAllObjects];
    [self saveSearchHistory];
    [self.tableView reloadData];
}

- (void)confirmClearSearchHistory {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Очистить историю поиска?")
                                                     message:nil
                                                    delegate:self
                                           cancelButtonTitle:GHL(@"Отмена")
                                           otherButtonTitles:GHL(@"Очистить"), nil];
    alert.tag = kClearHistoryAlertTag;
    [alert show];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView.tag == kClearHistoryAlertTag) {
        if (alertView.cancelButtonIndex != buttonIndex) {
            [self clearSearchHistory];
        }
    }
}

- (BOOL)isShowingHistory {
    return self.searchBar.text.length == 0;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = GHL(@"Название репозитория");
    self.searchBar.delegate = self;

    self.searchBar.scopeButtonTitles = [self localizedScopeButtonTitles];
    self.searchBar.showsScopeBar = YES;
    [self.searchBar sizeToFit];
    self.tableView.tableHeaderView = self.searchBar;

    UITapGestureRecognizer *dismissKeyboardTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                           action:@selector(dismissSearchKeyboard)];
    dismissKeyboardTap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:dismissKeyboardTap];

    [self installKeyboardDismissToolbarOnSearchBar];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.titleView = nil;

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HistoryCell"];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.frame = CGRectMake(0, 0, 30, 30);
    [self.settingsButton addTarget:self action:@selector(settingsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.settingsButton];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(themeDidChange)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(languageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray *)localizedScopeButtonTitles {
    return @[GHL(@"Репозитории"), GHL(@"Задачи/PR"), GHL(@"Люди")];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.title = GHL(@"Поиск");
    self.searchBar.scopeButtonTitles = [self localizedScopeButtonTitles];
    [self updateSearchPlaceholderForScope:(GHSearchScope)self.searchBar.selectedScopeButtonIndex];
    [self.tableView reloadData];
}

- (void)applyTheme {
    UIColor *accent = GHSettingsIconColor();
    [self.settingsButton setImage:[GHIconRenderer gearIconWithColor:accent size:22] forState:UIControlStateNormal];

    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.searchBar.barStyle = [GHThemeManager sharedManager].darkModeEnabled ? UIBarStyleBlack : UIBarStyleDefault;

    self.searchBar.scopeBarBackgroundImage = [self solidColorImage:GHBackgroundColor()];

    self.searchBar.backgroundImage = [self solidColorImage:GHBackgroundColor()];

    if (self.keyboardDismissToolbar) {
        self.keyboardDismissToolbar.tintColor = GHTintColor();
        [self applyToolbarBackground:self.keyboardDismissToolbar];
    }

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

- (void)themeDidChange {
    [self applyTheme];
}

- (void)languageDidChange {
    self.keyboardDismissButton.title = GHL(@"Скрыть");
}

- (void)handlePullToRefresh {
    NSString *query = self.searchBar.text;
    if (query.length == 0) {
        [self.refreshControl endRefreshing];
        return;
    }
    [self performSearchWithQuery:query];
}

- (void)settingsButtonTapped {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

#pragma mark - UISearchBarDelegate

- (void)dismissSearchKeyboard {
    [self.searchBar resignFirstResponder];
}

- (UITextField *)findTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:[UITextField class]]) {
        return (UITextField *)view;
    }
    for (UIView *subview in view.subviews) {
        UITextField *found = [self findTextFieldInView:subview];
        if (found != nil) return found;
    }
    return nil;
}

- (void)installKeyboardDismissToolbarOnSearchBar {
    UITextField *searchField = [self findTextFieldInView:self.searchBar];
    if (searchField == nil) return;

    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    toolbar.translucent = YES;

    toolbar.tintColor = GHTintColor();
    [self applyToolbarBackground:toolbar];

    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                       target:nil
                                                                                       action:NULL];

    UIBarButtonItem *hideButton = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Скрыть")
                                                                     style:UIBarButtonItemStyleDone
                                                                    target:self
                                                                    action:@selector(dismissSearchKeyboard)];
    [hideButton setTitleTextAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:15]} forState:UIControlStateNormal];
    toolbar.items = @[flexibleSpace, hideButton];
    searchField.inputAccessoryView = toolbar;
    self.keyboardDismissToolbar = toolbar;
    self.keyboardDismissButton = hideButton;
}

- (void)applyToolbarBackground:(UIToolbar *)toolbar {
    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
    toolbar.barStyle = isDark ? UIBarStyleBlack : UIBarStyleDefault;

    UIColor *tint = [GHBackgroundColor() colorWithAlphaComponent:0.86];
    UIImage *tintImage = [self solidColorImage:tint];
    [toolbar setBackgroundImage:tintImage
              forToolbarPosition:UIToolbarPositionAny
                      barMetrics:UIBarMetricsDefault];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = searchBar.text;
    if (query.length == 0) return;
    [self performSearchWithQuery:query];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self updateSearchPlaceholderForScope:(GHSearchScope)selectedScope];
    NSString *query = searchBar.text;
    if (query.length > 0) {
        [self performSearchWithQuery:query];
    }
}

- (void)updateSearchPlaceholderForScope:(GHSearchScope)scope {
    switch (scope) {
        case GHSearchScopeIssuesAndPullRequests:
            self.searchBar.placeholder = GHL(@"Заголовок issue или pull request");
            break;
        case GHSearchScopeUsers:
            self.searchBar.placeholder = GHL(@"Логин пользователя или организации");
            break;
        case GHSearchScopeRepositories:
        default:
            self.searchBar.placeholder = GHL(@"Название репозитория");
            break;
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        [self.results removeAllObjects];
        [self.tableView reloadData];
    }
}

- (void)performSearchWithQuery:(NSString *)query {
    [self recordSearchQuery:query];

    [self.spinner startAnimating];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.tableView.allowsSelection = NO;

    GHSearchScope scope = (GHSearchScope)self.searchBar.selectedScopeButtonIndex;

    __weak typeof(self) weakSelf = self;
    GHJSONCompletionBlock completion = ^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];
        strongSelf.navigationItem.leftBarButtonItem = nil;
        [strongSelf.refreshControl endRefreshing];
        strongSelf.tableView.allowsSelection = YES;

        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        NSArray *items = jsonObject[@"items"];
        [strongSelf.results removeAllObjects];
        if ([items isKindOfClass:[NSArray class]]) {
            [strongSelf.results addObjectsFromArray:items];
        }
        strongSelf.resultsScope = scope;
        [strongSelf.tableView reloadData];
    };

    switch (scope) {
        case GHSearchScopeIssuesAndPullRequests:
            [[GHAPIClient sharedClient] searchIssuesAndPullRequestsWithQuery:query completion:completion];
            break;
        case GHSearchScopeUsers:
            [[GHAPIClient sharedClient] searchUsersWithQuery:query completion:completion];
            break;
        case GHSearchScopeRepositories:
        default:
            [[GHAPIClient sharedClient] searchRepositoriesWithQuery:query completion:completion];
            break;
    }
}

- (void)ownerLogin:(NSString **)outOwner repoName:(NSString **)outRepo fromRepositoryURL:(NSString *)repositoryURL {
    NSString *marker = @"/repos/";
    NSRange range = [repositoryURL rangeOfString:marker];
    if (range.location == NSNotFound) return;

    NSString *tail = [repositoryURL substringFromIndex:range.location + range.length];
    NSArray *parts = [tail componentsSeparatedByString:@"/"];
    if (parts.count < 2) return;

    if (outOwner) *outOwner = parts[0];
    if (outRepo) *outRepo = parts[1];
}

#pragma mark - UITableViewDataSource

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([self isShowingHistory] && self.searchHistory.count > 0) return GHL(@"Недавние запросы");
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isShowingHistory]) {

        return self.searchHistory.count + (self.searchHistory.count > 0 ? 1 : 0);
    }
    return self.results.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isShowingHistory]) return 44;
    if (self.resultsScope != GHSearchScopeIssuesAndPullRequests) return 44;
    if (indexPath.row >= (NSInteger)self.results.count) return 44;

    NSDictionary *item = self.results[indexPath.row];
    NSString *title = [item[@"title"] isKindOfClass:[NSString class]] ? item[@"title"] : @"";

    CGFloat width = tableView.bounds.size.width - 60;
    CGSize titleSize = [title sizeWithFont:[UIFont boldSystemFontOfSize:15]
                          constrainedToSize:CGSizeMake(width, 200)
                              lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat maxTwoLineHeight = ceilf(15 * 1.2) * 2;
    CGFloat titleHeight = MIN(titleSize.height, maxTwoLineHeight);

    CGFloat subtitleHeight = ceilf(12 * 1.2);
    CGFloat verticalPadding = 20;

    return titleHeight + subtitleHeight + verticalPadding;
}

- (UITableViewCell *)subtitleCellWithReuseIdentifier:(NSString *)identifier forTableView:(UITableView *)tableView {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isShowingHistory]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HistoryCell" forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textAlignment = NSTextAlignmentLeft;

        if (indexPath.row == self.searchHistory.count) {
            cell.textLabel.text = GHL(@"Очистить историю");
            cell.textLabel.textColor = [UIColor redColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }

        cell.textLabel.text = [NSString stringWithFormat:@"🕓  %@", self.searchHistory[indexPath.row]];
        cell.textLabel.textColor = GHPrimaryTextColor();
        return cell;
    }

    NSDictionary *item = self.results[indexPath.row];

    switch (self.resultsScope) {
        case GHSearchScopeIssuesAndPullRequests: {
            UITableViewCell *cell = [self subtitleCellWithReuseIdentifier:@"IssueCell" forTableView:tableView];
            cell.backgroundColor = GHCellBackgroundColor();
            cell.imageView.image = nil;

            BOOL isPullRequest = [item[@"pull_request"] isKindOfClass:[NSDictionary class]];
            NSString *state = [item[@"state"] isKindOfClass:[NSString class]] ? item[@"state"] : @"open";
            NSString *kindLabel = isPullRequest ? @"PR" : GHL(@"Задача");

            cell.textLabel.text = [item[@"title"] isKindOfClass:[NSString class]] ? item[@"title"] : @"";
            cell.textLabel.textColor = GHPrimaryTextColor();
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.textLabel.numberOfLines = 2;

            NSString *ownerLogin = nil;
            NSString *repoName = nil;
            NSString *repositoryURL = [item[@"repository_url"] isKindOfClass:[NSString class]] ? item[@"repository_url"] : nil;
            [self ownerLogin:&ownerLogin repoName:&repoName fromRepositoryURL:repositoryURL];
            NSString *repoFullName = (ownerLogin.length > 0 && repoName.length > 0)
                ? [NSString stringWithFormat:@"%@/%@", ownerLogin, repoName]
                : @"";

            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ #%@ · %@ · %@",
                                          kindLabel, item[@"number"] ?: @"?", state, repoFullName];
            cell.detailTextLabel.textColor = GHSecondaryTextColor();
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.numberOfLines = 1;
            GHApplyDisclosureIndicator(cell);
            return cell;
        }
        case GHSearchScopeUsers: {
            UITableViewCell *cell = [self subtitleCellWithReuseIdentifier:@"UserCell" forTableView:tableView];
            cell.backgroundColor = GHCellBackgroundColor();

            cell.textLabel.text = [item[@"login"] isKindOfClass:[NSString class]] ? item[@"login"] : @"";
            cell.textLabel.textColor = GHPrimaryTextColor();

            NSString *accountType = [item[@"type"] isKindOfClass:[NSString class]] ? item[@"type"] : @"User";
            cell.detailTextLabel.text = [accountType isEqualToString:@"Organization"] ? GHL(@"Организация") : GHL(@"Пользователь");
            cell.detailTextLabel.textColor = GHSecondaryTextColor();
            GHApplyDisclosureIndicator(cell);

            NSString *avatarURL = [item[@"avatar_url"] isKindOfClass:[NSString class]] ? item[@"avatar_url"] : nil;
            [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:cell.imageView];
            return cell;
        }
        case GHSearchScopeRepositories:
        default: {
            UITableViewCell *cell = [self subtitleCellWithReuseIdentifier:@"RepoCell" forTableView:tableView];
            cell.backgroundColor = GHCellBackgroundColor();

            cell.textLabel.text = item[@"full_name"];
            cell.textLabel.textColor = GHPrimaryTextColor();
            NSNumber *stars = item[@"stargazers_count"];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"★ %@", stars ?: @0];
            cell.detailTextLabel.textColor = GHSecondaryTextColor();
            GHApplyDisclosureIndicator(cell);

            NSDictionary *owner = item[@"owner"];
            NSString *avatarURL = [owner isKindOfClass:[NSDictionary class]] ? owner[@"avatar_url"] : nil;
            [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:cell.imageView];
            return cell;
        }
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self isShowingHistory]) return NO;
    return indexPath.row < (NSInteger)self.searchHistory.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return GHL(@"Удалить");
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.searchHistory.count) return;

    [self.searchHistory removeObjectAtIndex:indexPath.row];
    [self saveSearchHistory];

    if (self.searchHistory.count == 0) {

        [tableView reloadData];
        return;
    }

    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self isShowingHistory]) {
        if (indexPath.row == self.searchHistory.count) {
            [self confirmClearSearchHistory];
            return;
        }
        NSString *query = self.searchHistory[indexPath.row];
        self.searchBar.text = query;
        [self.searchBar resignFirstResponder];
        [self performSearchWithQuery:query];
        return;
    }

    if (indexPath.row >= (NSInteger)self.results.count) return;

    NSDictionary *item = self.results[indexPath.row];

    switch (self.resultsScope) {
        case GHSearchScopeIssuesAndPullRequests: {
            NSString *ownerLogin = nil;
            NSString *repoName = nil;
            NSString *repositoryURL = [item[@"repository_url"] isKindOfClass:[NSString class]] ? item[@"repository_url"] : nil;
            [self ownerLogin:&ownerLogin repoName:&repoName fromRepositoryURL:repositoryURL];

            BOOL isPullRequest = [item[@"pull_request"] isKindOfClass:[NSDictionary class]];
            if (isPullRequest) {
                PullRequestDetailViewController *prVC = [[PullRequestDetailViewController alloc] init];
                prVC.pullRequest = item;
                prVC.ownerLogin = ownerLogin;
                prVC.repoName = repoName;
                prVC.title = [NSString stringWithFormat:@"#%@", item[@"number"] ?: @"?"];
                [self.navigationController pushViewController:prVC animated:YES];
            } else {
                IssueDetailViewController *issueVC = [[IssueDetailViewController alloc] init];
                issueVC.issue = item;
                issueVC.ownerLogin = ownerLogin;
                issueVC.repoName = repoName;
                issueVC.title = [NSString stringWithFormat:@"#%@", item[@"number"] ?: @"?"];
                [self.navigationController pushViewController:issueVC animated:YES];
            }
            return;
        }
        case GHSearchScopeUsers: {
            NSString *login = [item[@"login"] isKindOfClass:[NSString class]] ? item[@"login"] : nil;
            if (login.length == 0) return;
            PublicProfileViewController *profileVC = [[PublicProfileViewController alloc] init];
            profileVC.login = login;
            [self.navigationController pushViewController:profileVC animated:YES];
            return;
        }
        case GHSearchScopeRepositories:
        default: {
            RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
            overviewVC.repo = item;
            overviewVC.title = item[@"name"];
            [self.navigationController pushViewController:overviewVC animated:YES];
            return;
        }
    }
}

@end
