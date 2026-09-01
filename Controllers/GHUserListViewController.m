#import "GHUserListViewController.h"
#import "GHAPIClient.h"
#import "GHAvatarLoader.h"
#import "GHThemeManager.h"
#import "PublicProfileViewController.h"
#import "GHLocalization.h"

static NSString * const kUserCellID = @"UserCell";

@interface GHUserListViewController ()
@property (nonatomic, strong) NSMutableArray *users;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL loadAttempted;
@end

@implementation GHUserListViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _users = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kUserCellID];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self load];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    [self.tableView reloadData];
}

- (void)load {
    if (self.login.length == 0) {
        [self.refreshControl endRefreshing];
        return;
    }

    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    GHJSONCompletionBlock completion = ^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.spinner stopAnimating];
        [strongSelf.refreshControl endRefreshing];
        strongSelf.loadAttempted = YES;

        if (!error && [jsonObject isKindOfClass:[NSArray class]]) {
            [strongSelf.users removeAllObjects];
            [strongSelf.users addObjectsFromArray:jsonObject];
        }
        [strongSelf.tableView reloadData];
    };

    if (self.showingFollowers) {
        [[GHAPIClient sharedClient] followersForUser:self.login completion:completion];
    } else {
        [[GHAPIClient sharedClient] followingForUser:self.login completion:completion];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.users.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUserCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.detailTextLabel.text = nil;

    if (self.users.count == 0) {
        cell.textLabel.text = self.loadAttempted
            ? (self.showingFollowers ? GHL(@"Подписчиков нет") : GHL(@"Подписок нет"))
            : GHL(@"Загрузка…");
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary *user = self.users[indexPath.row];
    NSString *login = user[@"login"];
    cell.textLabel.text = login;
    cell.textLabel.textColor = GHPrimaryTextColor();
    GHApplyDisclosureIndicator(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    NSString *avatarURL = [user isKindOfClass:[NSDictionary class]] ? user[@"avatar_url"] : nil;
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:cell.imageView];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.users.count == 0) return;

    NSDictionary *user = self.users[indexPath.row];
    NSString *login = [user isKindOfClass:[NSDictionary class]] ? user[@"login"] : nil;
    if (login.length == 0) return;

    PublicProfileViewController *profileVC = [[PublicProfileViewController alloc] init];
    profileVC.login = login;
    [self.navigationController pushViewController:profileVC animated:YES];
}

@end
