#import "RepoDetailViewController.h"
#import "GHAPIClient.h"
#import "ReleaseDetailViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

@interface RepoDetailViewController ()
@property (nonatomic, strong) NSMutableArray *releases;
@end

@implementation RepoDetailViewController

+ (BOOL)releaseListInfoFromURL:(NSURL *)url
                     ownerLogin:(NSString **)ownerLogin
                       repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/releases(?:[/?#].*)?$"
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
        _releases = [NSMutableArray array];

        self.title = GHL(@"Релизы");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadReleases) forControlEvents:UIControlEventValueChanged];

    [self loadReleases];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Релизы");
    [self.tableView reloadData];
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

- (void)loadReleases {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] releasesForOwner:self.ownerLogin repo:self.repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.navigationItem.rightBarButtonItem = nil;
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

        if ([jsonObject isKindOfClass:[NSArray class]]) {
            [strongSelf.releases removeAllObjects];
            [strongSelf.releases addObjectsFromArray:jsonObject];
        }
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.releases.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ReleaseCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ReleaseCell"];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    NSDictionary *release = self.releases[indexPath.row];

    id nameValue = release[@"name"];
    id tagValue = release[@"tag_name"];
    NSString *releaseName = [nameValue isKindOfClass:[NSString class]] ? nameValue : nil;
    NSString *tagName = [tagValue isKindOfClass:[NSString class]] ? tagValue : nil;

    cell.textLabel.text = releaseName.length > 0 ? releaseName : (tagName ?: GHL(@"Без названия"));
    cell.textLabel.textColor = GHPrimaryTextColor();
    NSArray *assets = [release[@"assets"] isKindOfClass:[NSArray class]] ? release[@"assets"] : @[];

    long long totalBytes = 0;
    for (NSDictionary *asset in assets) {
        if (![asset isKindOfClass:[NSDictionary class]]) continue;
        NSNumber *size = asset[@"size"];
        if ([size isKindOfClass:[NSNumber class]]) totalBytes += size.longLongValue;
    }
    if (totalBytes > 0) {
        double totalMB = (double)totalBytes / (1024.0 * 1024.0);
        cell.detailTextLabel.text = [NSString stringWithFormat:GHL(@"%lu файл(ов) · %.2f МБ"),
                                                                 (unsigned long)assets.count, totalMB];
    } else {

        cell.detailTextLabel.text = [NSString stringWithFormat:GHL(@"%lu файл(ов)"), (unsigned long)assets.count];
    }
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    GHApplyDisclosureIndicator(cell);

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *release = self.releases[indexPath.row];
    id tagValue = release[@"tag_name"];

    ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
    detailVC.releaseInfo = release;
    detailVC.ownerLogin = self.ownerLogin;
    detailVC.repoName = self.repoName;
    detailVC.title = [tagValue isKindOfClass:[NSString class]] ? tagValue : GHL(@"Релиз");

    [self.navigationController pushViewController:detailVC animated:YES];
}

@end
