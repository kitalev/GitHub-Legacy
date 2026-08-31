#import "StarredReposViewController.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHStarredRepoCell.h"
#import "GHIconRenderer.h"
#import "SettingsViewController.h"
#import "GHLocalization.h"

@interface StarredReposViewController ()
@property (nonatomic, strong) NSMutableArray *repos;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *settingsButton;
@end

@implementation StarredReposViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {

        self.title = GHL(@"Избранное");
        _repos = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[GHStarredRepoCell class] forCellReuseIdentifier:@"StarredCell"];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.settingsButton.frame = CGRectMake(0, 0, 30, 30);
    [self.settingsButton addTarget:self action:@selector(settingsButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    if (self.viewedLogin.length == 0) {

        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.settingsButton];
    }

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

    if (self.viewedLogin.length == 0) {
        self.title = GHL(@"Избранное");
    }
}

- (void)reload {
    [self updateSignInHeader];

    if (self.viewedLogin.length > 0) {
        [self.spinner startAnimating];
        __weak typeof(self) weakSelf = self;
        [[GHAPIClient sharedClient] starredRepositoriesForUser:self.viewedLogin completion:^(id jsonObject, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf.spinner stopAnimating];
            [strongSelf.refreshControl endRefreshing];
            if (!error && [jsonObject isKindOfClass:[NSArray class]]) {
                [strongSelf.repos removeAllObjects];
                [strongSelf.repos addObjectsFromArray:jsonObject];
                [strongSelf.tableView reloadData];
            }
        }];
        return;
    }

    if (![GHAuthManager sharedManager].isAuthenticated) {
        [self.repos removeAllObjects];
        [self.tableView reloadData];
        [self.refreshControl endRefreshing];
        return;
    }

    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] starredRepositoriesWithCompletion:^(id jsonObject, NSError *error) {
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

#pragma mark - Вход

- (void)openSettingsFromPlaceholder {
    SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)updateSignInHeader {
    if (self.viewedLogin.length > 0 || [GHAuthManager sharedManager].isAuthenticated) {
        self.tableView.tableHeaderView = nil;
        return;
    }
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;
    self.tableView.tableHeaderView = GHSignInPlaceholderView(
        GHL(@"Войдите в аккаунт, чтобы видеть избранные репозитории"),
        width, self, @selector(openSettingsFromPlaceholder));
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if (self.viewedLogin.length == 0 && ![GHAuthManager sharedManager].isAuthenticated) {
        return 0;
    }
    return self.repos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHStarredRepoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StarredCell" forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    [cell configureWithRepo:self.repos[indexPath.row]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [GHStarredRepoCell heightForRepo:self.repos[indexPath.row] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *repo = self.repos[indexPath.row];

    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = repo[@"name"];

    [self.navigationController pushViewController:overviewVC animated:YES];
}

@end
