#import "CommitHistoryViewController.h"
#import "CommitDetailViewController.h"
#import "GHAPIClient.h"
#import "GHAvatarLoader.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

static NSString * const kCommitCellID = @"CommitCell";

static const NSInteger kCommitsPerPage = 30;

@interface CommitHistoryViewController ()
@property (nonatomic, strong) NSMutableArray *commits;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, assign) NSInteger nextPage;
@property (nonatomic, assign) BOOL hasMoreCommits;
@property (nonatomic, assign) BOOL loadingMore;
@end

@implementation CommitHistoryViewController

+ (BOOL)commitHistoryInfoFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/commits(?:/.*)?$"
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
        self.title = GHL(@"Коммиты");
        _commits = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = 64;

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadCommits) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self loadCommits];
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

- (NSDictionary *)safeDictForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)safeStringForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (void)loadCommits {
    self.nextPage = 1;
    self.hasMoreCommits = YES;
    self.loadingMore = NO;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] commitsForOwner:self.ownerLogin repo:self.repoName page:1 completion:^(id jsonObject, NSError *error) {
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

        [strongSelf.commits removeAllObjects];
        NSArray *page = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        [strongSelf.commits addObjectsFromArray:page];
        strongSelf.hasMoreCommits = page.count >= kCommitsPerPage;
        strongSelf.nextPage = 2;
        [strongSelf.tableView reloadData];
    }];
}

- (void)loadMoreCommitsIfNeeded {
    if (!self.hasMoreCommits || self.loadingMore) return;

    self.loadingMore = YES;

    [self.tableView reloadData];

    NSInteger page = self.nextPage;
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] commitsForOwner:self.ownerLogin repo:self.repoName page:page completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.loadingMore = NO;

        if (error) {

            [strongSelf.tableView reloadData];
            return;
        }

        NSArray *newPage = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        [strongSelf.commits addObjectsFromArray:newPage];
        strongSelf.hasMoreCommits = newPage.count >= kCommitsPerPage;
        strongSelf.nextPage = page + 1;
        [strongSelf.tableView reloadData];
    }];
}

- (NSString *)firstLineOfMessage:(NSString *)message {
    if (message.length == 0) return GHL(@"(без сообщения)");
    NSRange newlineRange = [message rangeOfString:@"\n"];
    if (newlineRange.location == NSNotFound) return message;
    return [message substringToIndex:newlineRange.location];
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
    return self.commits.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCommitCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCommitCellID];
    }

    NSDictionary *commitEntry = self.commits[indexPath.row];
    NSDictionary *commitData = [self safeDictForKey:@"commit" inDict:commitEntry];
    NSDictionary *authorData = [self safeDictForKey:@"author" inDict:commitData];

    NSString *message = [self safeStringForKey:@"message" inDict:commitData];
    NSString *authorName = [self safeStringForKey:@"name" inDict:authorData];
    NSString *date = [self safeStringForKey:@"date" inDict:authorData];

    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.text = [self firstLineOfMessage:message];
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
    cell.textLabel.textColor = GHPrimaryTextColor();

    cell.detailTextLabel.text = authorName.length > 0 ? authorName : @"";
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    cell.detailTextLabel.textColor = GHSecondaryTextColor();

    UILabel *dateLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 40, 20)];
    dateLabel.font = [UIFont systemFontOfSize:12];
    dateLabel.textColor = GHSecondaryTextColor();
    dateLabel.textAlignment = NSTextAlignmentRight;
    dateLabel.backgroundColor = [UIColor clearColor];
    dateLabel.text = [self relativeDateStringFromISOString:date];
    cell.accessoryView = dateLabel;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    NSDictionary *githubAuthor = [self safeDictForKey:@"author" inDict:commitEntry];
    NSString *avatarURL = [self safeStringForKey:@"avatar_url" inDict:githubAuthor];
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:cell.imageView];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.commits.count == 0 || indexPath.row != (NSInteger)self.commits.count - 1) return;
    [self loadMoreCommitsIfNeeded];
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

    NSDictionary *commitEntry = self.commits[indexPath.row];
    NSString *sha = [self safeStringForKey:@"sha" inDict:commitEntry];
    if (sha.length == 0) return;

    CommitDetailViewController *detailVC = [[CommitDetailViewController alloc] init];
    detailVC.ownerLogin = self.ownerLogin;
    detailVC.repoName = self.repoName;
    detailVC.sha = sha;
    [self.navigationController pushViewController:detailVC animated:YES];
}

@end
