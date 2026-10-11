#import "RepoDetailViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "GHAPIClient.h"
#import "ReleaseDetailViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import <QuartzCore/QuartzCore.h>

static NSString *GHReleaseSafeString(NSDictionary *dict, NSString *key) {
    id value = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL GHReleaseBool(NSDictionary *dict, NSString *key) {
    id value = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static NSString *GHReleaseShortAge(NSString *isoString) {
    if (isoString.length == 0) return @"";

    static NSDateFormatter *isoFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isoFormatter = [[NSDateFormatter alloc] init];
        isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        isoFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return @"";

    NSTimeInterval seconds = MAX(0, -[date timeIntervalSinceNow]);
    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    BOOL russian = [[GHLocalization sharedManager].languageCode isEqualToString:@"ru"];

    if (minutes < 1) return russian ? @"сейчас" : @"now";
    if (minutes < 60) return [NSString stringWithFormat:russian ? @"%ld мин" : @"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:russian ? @"%ld ч" : @"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:russian ? @"%ld дн" : @"%ldd", (long)days];
    if (days < 365) return [NSString stringWithFormat:russian ? @"%ld мес" : @"%ldmo", (long)(days / 30)];
    return [NSString stringWithFormat:russian ? @"%ld г" : @"%ldy", (long)(days / 365)];
}

static UIColor *GHReleaseLatestColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0]
        : [UIColor colorWithRed:0.10 green:0.50 blue:0.22 alpha:1.0];
}

static UIColor *GHReleasePreReleaseColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.86 green:0.48 blue:0.15 alpha:1.0]
        : [UIColor colorWithRed:0.74 green:0.34 blue:0.00 alpha:1.0];
}

static const CGFloat kGHReleaseListRowHeight = 78.0;
static const CGFloat kGHReleaseListSidePadding = 16.0;

@interface GHReleaseListCell : UITableViewCell
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *ageLabel;
@property (nonatomic, strong) UILabel *dotLabel;
@property (nonatomic, strong) UILabel *statusLabel;
- (void)configureWithRelease:(NSDictionary *)release isLatest:(BOOL)isLatest;
@end

@implementation GHReleaseListCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:18];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_nameLabel];

        _ageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _ageLabel.backgroundColor = [UIColor clearColor];
        _ageLabel.font = [UIFont systemFontOfSize:15];
        [self.contentView addSubview:_ageLabel];

        _dotLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _dotLabel.backgroundColor = [UIColor clearColor];
        _dotLabel.font = [UIFont systemFontOfSize:15];
        _dotLabel.text = @"·";
        [self.contentView addSubview:_dotLabel];

        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.backgroundColor = [UIColor clearColor];
        _statusLabel.font = [UIFont systemFontOfSize:15];
        [self.contentView addSubview:_statusLabel];
    }
    return self;
}

- (void)configureWithRelease:(NSDictionary *)release isLatest:(BOOL)isLatest {
    self.backgroundColor = GHCellBackgroundColor();
    self.contentView.backgroundColor = GHCellBackgroundColor();

    NSString *name = GHReleaseSafeString(release, @"name");
    NSString *tag = GHReleaseSafeString(release, @"tag_name");
    self.nameLabel.text = name.length > 0 ? name : (tag.length > 0 ? tag : GHL(@"Без названия"));
    self.nameLabel.textColor = GHPrimaryTextColor();

    NSString *dateString = GHReleaseSafeString(release, @"published_at");
    if (dateString.length == 0) dateString = GHReleaseSafeString(release, @"created_at");
    self.ageLabel.text = GHReleaseShortAge(dateString);
    self.ageLabel.textColor = GHSecondaryTextColor();
    self.dotLabel.textColor = GHSecondaryTextColor();

    NSString *status = nil;
    UIColor *statusColor = nil;
    if (GHReleaseBool(release, @"draft")) {
        status = GHL(@"Черновик");
        statusColor = GHSecondaryTextColor();
    } else if (GHReleaseBool(release, @"prerelease")) {
        status = GHL(@"Пре-релиз");
        statusColor = GHReleasePreReleaseColor();
    } else if (isLatest) {
        status = GHL(@"Последний релиз");
        statusColor = GHReleaseLatestColor();
    }
    self.statusLabel.text = status;
    self.statusLabel.textColor = statusColor;
    self.statusLabel.hidden = status.length == 0;
    self.dotLabel.hidden = status.length == 0 || self.ageLabel.text.length == 0;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textWidth = width - kGHReleaseListSidePadding * 2;

    self.nameLabel.frame = CGRectMake(kGHReleaseListSidePadding, 14, textWidth, 24);

    CGFloat y = 44;
    CGFloat x = kGHReleaseListSidePadding;
    CGSize ageSize = [self.ageLabel.text sizeWithFont:self.ageLabel.font];
    self.ageLabel.frame = CGRectMake(x, y, MIN(ageSize.width, textWidth), 20);
    x += ageSize.width;

    if (!self.dotLabel.hidden) {
        x += 6;
        CGSize dotSize = [self.dotLabel.text sizeWithFont:self.dotLabel.font];
        self.dotLabel.frame = CGRectMake(x, y, dotSize.width, 20);
        x += dotSize.width + 6;
    } else if (self.ageLabel.text.length == 0) {
        x = kGHReleaseListSidePadding;
    }

    if (!self.statusLabel.hidden) {
        self.statusLabel.frame = CGRectMake(x, y, MAX(0, width - kGHReleaseListSidePadding - x), 20);
    }
}

@end

@interface RepoDetailViewController ()
@property (nonatomic, strong) NSMutableArray *releases;
@property (nonatomic, assign) BOOL loaded;
@end

@interface RepoDetailViewController (GHReleaseRouting)
+ (void)pushTopOfReleasesListForOwnerLogin:(NSString *)ownerLogin
                                   repoName:(NSString *)repoName
                         fromViewController:(UIViewController *)fromViewController;
+ (void)pushReleaseDetailForRelease:(NSDictionary *)release
                          ownerLogin:(NSString *)ownerLogin
                            repoName:(NSString *)repoName
                  fromViewController:(UIViewController *)fromViewController;
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

    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(loadReleases) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(loadReleases) forControlEvents:UIControlEventValueChanged];
    }

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
    self.tableView.backgroundColor = GHCellBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    [self.tableView reloadData];
}

- (void)loadReleases {
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    [spinner startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] releasesForOwner:self.ownerLogin repo:self.repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.navigationItem.rightBarButtonItem = nil;
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }

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
            for (id release in (NSArray *)jsonObject) {
                if ([release isKindOfClass:[NSDictionary class]]) [strongSelf.releases addObject:release];
            }
        }
        strongSelf.loaded = YES;
        [strongSelf.tableView reloadData];
    }];
}

// «Последний релиз» в терминах GitHub — самый свежий опубликованный релиз,
// который не черновик и не пре-релиз. API отдаёт список от новых к старым.
- (NSInteger)latestReleaseIndex {
    for (NSInteger i = 0; i < (NSInteger)self.releases.count; i++) {
        NSDictionary *release = self.releases[i];
        if (!GHReleaseBool(release, @"draft") && !GHReleaseBool(release, @"prerelease")) return i;
    }
    return NSNotFound;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.loaded && self.releases.count == 0) return 1;
    return self.releases.count;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.releases.count == 0) return nil;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 48)];
    header.backgroundColor = GHCellBackgroundColor();

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kGHReleaseListSidePadding, 18, tableView.bounds.size.width - kGHReleaseListSidePadding * 2, 22)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = GHSecondaryTextColor();
    label.text = GHL(@"Все релизы");
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return self.releases.count > 0 ? 48 : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.releases.count == 0) return 120;
    return kGHReleaseListRowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.releases.count == 0) {
        UITableViewCell *emptyCell = [tableView dequeueReusableCellWithIdentifier:@"ReleaseEmptyCell"];
        if (!emptyCell) {
            emptyCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ReleaseEmptyCell"];
            emptyCell.selectionStyle = UITableViewCellSelectionStyleNone;
            emptyCell.textLabel.textAlignment = NSTextAlignmentCenter;
            emptyCell.textLabel.font = [UIFont systemFontOfSize:16];
        }
        emptyCell.backgroundColor = GHCellBackgroundColor();
        emptyCell.textLabel.backgroundColor = [UIColor clearColor];
        emptyCell.textLabel.textColor = GHSecondaryTextColor();
        emptyCell.textLabel.text = GHL(@"Нет релизов");
        return emptyCell;
    }

    GHReleaseListCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GHReleaseListCell"];
    if (!cell) {
        cell = [[GHReleaseListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"GHReleaseListCell"];
    }
    NSDictionary *release = self.releases[indexPath.row];
    [cell configureWithRelease:release isLatest:(indexPath.row == [self latestReleaseIndex])];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.releases.count) return;

    NSDictionary *release = self.releases[indexPath.row];
    id tagValue = release[@"tag_name"];

    ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
    detailVC.releaseInfo = release;
    detailVC.ownerLogin = self.ownerLogin;
    detailVC.repoName = self.repoName;
    detailVC.title = [tagValue isKindOfClass:[NSString class]] ? tagValue : GHL(@"Релиз");

    [self.navigationController pushViewController:detailVC animated:YES];
}

+ (BOOL)latestReleaseInfoFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/releases/latest/?(?:[?#].*)?$"
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

+ (void)pushLatestReleaseForOwnerLogin:(NSString *)ownerLogin
                                repoName:(NSString *)repoName
                      fromViewController:(UIViewController *)fromViewController {
    __weak UIViewController *weakFromVC = fromViewController;

    [[GHAPIClient sharedClient] latestReleaseForOwner:ownerLogin
                                                   repo:repoName
                                             completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        NSDictionary *release = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        if (error || release == nil) {
            [self pushTopOfReleasesListForOwnerLogin:ownerLogin repoName:repoName fromViewController:strongFromVC];
            return;
        }

        [self pushReleaseDetailForRelease:release ownerLogin:ownerLogin repoName:repoName fromViewController:strongFromVC];
    }];
}

+ (void)pushTopOfReleasesListForOwnerLogin:(NSString *)ownerLogin
                                   repoName:(NSString *)repoName
                         fromViewController:(UIViewController *)fromViewController {
    __weak UIViewController *weakFromVC = fromViewController;

    [[GHAPIClient sharedClient] releasesForOwner:ownerLogin
                                             repo:repoName
                                       completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        NSArray *releases = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : nil;
        NSDictionary *topRelease = releases.count > 0 && [releases[0] isKindOfClass:[NSDictionary class]] ? releases[0] : nil;

        if (topRelease == nil) {
            RepoDetailViewController *listVC = [[RepoDetailViewController alloc] init];
            listVC.ownerLogin = ownerLogin;
            listVC.repoName = repoName;
            listVC.title = GHL(@"Релизы");
            [strongFromVC.navigationController pushViewController:listVC animated:YES];
            return;
        }

        [self pushReleaseDetailForRelease:topRelease ownerLogin:ownerLogin repoName:repoName fromViewController:strongFromVC];
    }];
}

+ (void)pushReleaseDetailForRelease:(NSDictionary *)release
                          ownerLogin:(NSString *)ownerLogin
                            repoName:(NSString *)repoName
                  fromViewController:(UIViewController *)fromViewController {
    id tagValue = release[@"tag_name"];
    ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
    detailVC.releaseInfo = release;
    detailVC.ownerLogin = ownerLogin;
    detailVC.repoName = repoName;
    detailVC.title = [tagValue isKindOfClass:[NSString class]] ? tagValue : GHL(@"Релиз");
    [fromViewController.navigationController pushViewController:detailVC animated:YES];
}

+ (BOOL)releaseByTagInfoFromURL:(NSURL *)url
                      ownerLogin:(NSString **)ownerLogin
                        repoName:(NSString **)repoName
                             tag:(NSString **)tag {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/releases/tag/([^/?#]+)/?(?:[?#].*)?$"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    if (tag != NULL) {
        NSString *rawTag = [urlString substringWithRange:[match rangeAtIndex:3]];
        *tag = [rawTag stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: rawTag;
    }
    return YES;
}

+ (void)pushReleaseForOwnerLogin:(NSString *)ownerLogin
                          repoName:(NSString *)repoName
                               tag:(NSString *)tag
                fromViewController:(UIViewController *)fromViewController {
    __weak UIViewController *weakFromVC = fromViewController;

    [[GHAPIClient sharedClient] releaseForOwner:ownerLogin
                                            repo:repoName
                                             tag:tag
                                      completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        NSDictionary *release = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        if (error || release == nil) {
            RepoDetailViewController *listVC = [[RepoDetailViewController alloc] init];
            listVC.ownerLogin = ownerLogin;
            listVC.repoName = repoName;
            listVC.title = GHL(@"Релизы");
            [strongFromVC.navigationController pushViewController:listVC animated:YES];
            return;
        }

        ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
        detailVC.releaseInfo = release;
        detailVC.ownerLogin = ownerLogin;
        detailVC.repoName = repoName;
        detailVC.title = tag;
        [strongFromVC.navigationController pushViewController:detailVC animated:YES];
    }];
}

@end
