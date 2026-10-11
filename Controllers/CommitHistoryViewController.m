#import "CommitHistoryViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "CommitDetailViewController.h"
#import "GHAPIClient.h"
#import "GHAvatarLoader.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kCommitCellID = @"CommitCell";

static const CGFloat kCommitMargin = 16;
static const CGFloat kCommitTop = 12;
static const CGFloat kCommitMetaHeight = 20;

@interface GHCommitRowCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *shaLabel;
+ (CGFloat)heightForTitle:(NSString *)title width:(CGFloat)width;
@end

@implementation GHCommitRowCell

+ (UIFont *)titleFont {
    return [UIFont boldSystemFontOfSize:16];
}

+ (CGFloat)titleHeight:(NSString *)title width:(CGFloat)width {
    UIFont *font = [self titleFont];
    CGSize size = [(title ?: @"") sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByTruncatingTail];
    return MAX(ceil(font.lineHeight), MIN(ceil(size.height), ceil(font.lineHeight) * 2));
}

+ (CGFloat)heightForTitle:(NSString *)title width:(CGFloat)width {
    return kCommitTop + [self titleHeight:title width:width - kCommitMargin * 2] + 8 + kCommitMetaHeight + kCommitTop;
}

- (UILabel *)labelWithFont:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.backgroundColor = [UIColor clearColor];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:label];
    return label;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;
        self.titleLabel = [self labelWithFont:[GHCommitRowCell titleFont]];
        self.titleLabel.numberOfLines = 2;
        self.avatarView = [[UIImageView alloc] init];
        self.avatarView.layer.cornerRadius = 10;
        self.avatarView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.avatarView];
        self.authorLabel = [self labelWithFont:[UIFont systemFontOfSize:14]];
        self.dateLabel = [self labelWithFont:[UIFont systemFontOfSize:14]];
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        self.shaLabel = [self labelWithFont:[UIFont fontWithName:@"Courier" size:14] ?: [UIFont systemFontOfSize:13]];
        self.shaLabel.textAlignment = NSTextAlignmentRight;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = width - kCommitMargin * 2;
    CGFloat y = kCommitTop;
    CGFloat titleHeight = [GHCommitRowCell titleHeight:self.titleLabel.text width:contentWidth];
    self.titleLabel.frame = CGRectMake(kCommitMargin, y, contentWidth, titleHeight);
    y += titleHeight + 8;

    CGFloat shaWidth = ceil([self.shaLabel.text sizeWithFont:self.shaLabel.font].width);
    self.shaLabel.frame = CGRectMake(width - kCommitMargin - shaWidth, y, shaWidth, kCommitMetaHeight);

    self.avatarView.frame = CGRectMake(kCommitMargin, y, 20, 20);
    CGFloat x = kCommitMargin + 28;
    CGFloat maxRight = width - kCommitMargin - shaWidth - 12;
    CGFloat dateWidth = ceil([self.dateLabel.text sizeWithFont:self.dateLabel.font].width);
    CGFloat authorWidth = MIN(ceil([self.authorLabel.text sizeWithFont:self.authorLabel.font].width), MAX(maxRight - x - dateWidth - 6, 0));
    self.authorLabel.frame = CGRectMake(x, y, authorWidth, kCommitMetaHeight);
    x += authorWidth + 6;
    self.dateLabel.frame = CGRectMake(x, y, MIN(dateWidth, MAX(maxRight - x, 0)), kCommitMetaHeight);
}

@end

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

    [self.tableView gh_registerCellClass:[GHCommitRowCell class] forCellReuseIdentifier:kCommitCellID];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(loadCommits) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(loadCommits) forControlEvents:UIControlEventValueChanged];
    }

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
    return self.commits.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHCommitRowCell *cell = [tableView gh_dequeueCellWithIdentifier:kCommitCellID forIndexPath:indexPath];

    NSDictionary *commitEntry = self.commits[indexPath.row];
    NSDictionary *commitData = [self safeDictForKey:@"commit" inDict:commitEntry];
    NSDictionary *authorData = [self safeDictForKey:@"author" inDict:commitData];
    NSDictionary *githubAuthor = [self safeDictForKey:@"author" inDict:commitEntry];

    NSString *message = [self safeStringForKey:@"message" inDict:commitData];
    NSString *authorName = [self safeStringForKey:@"name" inDict:authorData];
    NSString *authorLogin = [self safeStringForKey:@"login" inDict:githubAuthor];
    NSString *date = [self safeStringForKey:@"date" inDict:authorData];
    NSString *sha = [self safeStringForKey:@"sha" inDict:commitEntry] ?: @"";
    NSString *avatarURL = [self safeStringForKey:@"avatar_url" inDict:githubAuthor];

    cell.backgroundColor = GHCellBackgroundColor();
    cell.titleLabel.text = [self firstLineOfMessage:message];
    cell.titleLabel.textColor = GHPrimaryTextColor();

    cell.authorLabel.text = authorLogin.length > 0 ? authorLogin : (authorName ?: @"");
    cell.authorLabel.textColor = GHPrimaryTextColor();

    NSString *relative = [self relativeDateStringFromISOString:date];
    cell.dateLabel.text = relative.length > 0 ? [NSString stringWithFormat:@"\u00b7 %@", relative] : @"";
    cell.dateLabel.textColor = GHSecondaryTextColor();

    cell.shaLabel.text = sha.length >= 7 ? [sha substringToIndex:7] : sha;
    cell.shaLabel.textColor = GHSecondaryTextColor();

    cell.avatarView.image = nil;
    cell.avatarView.backgroundColor = GHSeparatorColor();
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:cell.avatarView];
    [cell setNeedsLayout];

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *commitEntry = self.commits[indexPath.row];
    NSDictionary *commitData = [self safeDictForKey:@"commit" inDict:commitEntry];
    NSString *title = [self firstLineOfMessage:[self safeStringForKey:@"message" inDict:commitData]];
    return [GHCommitRowCell heightForTitle:title width:tableView.bounds.size.width];
}

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
