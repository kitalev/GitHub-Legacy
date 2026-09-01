#import "ProfileRepoListViewController.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

static NSString * const kRepoCellID = @"RepoCell";

@implementation ProfileRepoListViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Репозитории");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kRepoCellID];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.repos.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRepoCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();

    if (self.repos.count == 0) {
        cell.textLabel.text = GHL(@"Репозиториев нет");
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    NSDictionary *repo = self.repos[indexPath.row];
    cell.textLabel.text = repo[@"full_name"];
    cell.textLabel.textColor = GHPrimaryTextColor();
    NSNumber *stars = repo[@"stargazers_count"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"★ %@", stars ?: @0];
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    GHApplyDisclosureIndicator(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.repos.count == 0) return;

    NSDictionary *repo = self.repos[indexPath.row];
    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = repo[@"name"];
    [self.navigationController pushViewController:overviewVC animated:YES];
}

@end
