#import "RepoOverviewViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "RepoDetailViewController.h"
#import "CommitHistoryViewController.h"
#import "CommitDetailViewController.h"
#import "ReadmeViewController.h"
#import "IssueListViewController.h"
#import "IssueDetailViewController.h"
#import "PullRequestListViewController.h"
#import "PullRequestDetailViewController.h"
#import "ForkListViewController.h"
#import "RepoFilesViewController.h"
#import "AppDelegate.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHMarkdownRenderer.h"
#import "GHThemeManager.h"
#import "PublicProfileViewController.h"
#import "GHAvatarLoader.h"
#import "GHIconRenderer.h"
#import "GHLocalization.h"
#import "GHRepoHeaderView.h"
#import "ReleaseDetailViewController.h"
#import "GHURLRouter.h"
#import <QuartzCore/QuartzCore.h>
#import <string.h>

static const NSInteger kSectionActions = 0;
static const NSInteger kSectionCode = 1;
static const NSInteger kSectionReadme = 2;
static const NSInteger kSectionCount = 3;

typedef NS_ENUM(NSInteger, GHRepoRowKind) {
    GHRepoRowKindIssues,
    GHRepoRowKindPullRequests,
    GHRepoRowKindReleases,
    GHRepoRowKindLatestRelease,
    GHRepoRowKindMore,
    GHRepoRowKindForks,
    GHRepoRowKindLicense,
    GHRepoRowKindBranch,
    GHRepoRowKindFiles,
    GHRepoRowKindCommits
};

static NSString *GHRepoRelativeDate(NSString *isoString) {
    if (isoString.length == 0) return @"";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    NSDate *date = [formatter dateFromString:isoString];
    if (!date) return @"";

    NSTimeInterval seconds = MAX(0, -[date timeIntervalSinceNow]);
    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    BOOL russian = [[GHLocalization sharedManager].languageCode isEqualToString:@"ru"];
    if (minutes < 1) return russian ? @"сейчас" : @"now";
    if (minutes < 60) return [NSString stringWithFormat:russian ? @"%ld мин" : @"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:russian ? @"%ld ч" : @"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:russian ? @"%ld д" : @"%ldd", (long)days];
    if (days < 365) return [NSString stringWithFormat:russian ? @"%ld мес" : @"%ldmo", (long)(days / 30)];
    return [NSString stringWithFormat:russian ? @"%ld г" : @"%ldy", (long)(days / 365)];
}

@interface RepoOverviewViewController ()
@property (nonatomic, assign) BOOL readmeLoading;
@property (nonatomic, assign) BOOL readmeLoadAttempted;

@property (nonatomic, assign) BOOL isStarred;
@property (nonatomic, assign) BOOL starStatusKnown;
@property (nonatomic, assign) BOOL starActionInProgress;
@property (nonatomic, copy) NSString *starCheckErrorMessage;

@property (nonatomic, assign) BOOL sectionsExpanded;

@property (nonatomic, strong) UIWebView *readmeWebView;
@property (nonatomic, assign) BOOL readmeHTMLReady;
@property (nonatomic, assign) CGFloat readmeWebViewHeight;
@property (nonatomic, copy) NSString *readmeFullHTML;

@property (nonatomic, copy) void (^readmeFullHTMLReadyHandler)(NSString *html);

@property (nonatomic, copy) NSString *readmeInlineBodyHTML;
@property (nonatomic, assign) CGFloat readmeRenderedWidth;

@property (nonatomic, assign) BOOL readmeWebViewUnloadedForBackground;

@property (nonatomic, strong) GHRepoHeaderView *headerView;
@property (nonatomic, strong) NSDictionary *latestRelease;
@property (nonatomic, copy) NSString *readmeFileName;
@end

@implementation RepoOverviewViewController

+ (BOOL)repoOverviewInfoFromURL:(NSURL *)url
                      ownerLogin:(NSString **)ownerLogin
                        repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://(?:www\\.)?github\\.com/([^/]+)/([^/]+?)/?(?:[?#].*)?$"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    NSString *owner = [urlString substringWithRange:[match rangeAtIndex:1]];
    NSString *repo = [urlString substringWithRange:[match rangeAtIndex:2]];

    static NSSet *reservedFirstSegments = nil;
    static dispatch_once_t reservedToken;
    dispatch_once(&reservedToken, ^{
        reservedFirstSegments = [NSSet setWithObjects:@"settings", @"notifications", @"marketplace",
                                  @"sponsors", @"topics", @"collections", @"trending", @"search",
                                  @"about", @"pricing", @"features", @"explore", @"apps", @"issues",
                                  @"pulls", @"orgs", @"login", @"join", @"new", @"organizations", nil];
    });
    if ([reservedFirstSegments containsObject:owner.lowercaseString]) return NO;

    if (owner.length == 0 || repo.length == 0) return NO;
    if (ownerLogin != NULL) *ownerLogin = owner;
    if (repoName != NULL) *repoName = repo;
    return YES;
}

+ (void)pushRepoOverviewForOwnerLogin:(NSString *)ownerLogin
                              repoName:(NSString *)repoName
                    fromViewController:(UIViewController *)fromViewController {
    NSMutableDictionary *repoStub = [NSMutableDictionary dictionary];
    repoStub[@"name"] = repoName ?: @"";
    repoStub[@"owner"] = @{@"login": ownerLogin ?: @""};
    repoStub[@"full_name"] = [NSString stringWithFormat:@"%@/%@", ownerLogin ?: @"", repoName ?: @""];

    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repoStub;
    overviewVC.title = repoName;
    [fromViewController.navigationController pushViewController:overviewVC animated:YES];
}

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    return self;
}

- (NSString *)safeStringForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (NSDictionary *)safeDictForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSNumber *)safeNumberForKey:(NSString *)key inDict:(NSDictionary *)dict {
    id value = dict[key];
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (NSString *)ownerLogin {
    NSDictionary *owner = [self safeDictForKey:@"owner" inDict:self.repo];
    return [self safeStringForKey:@"login" inDict:owner];
}

- (NSString *)repoName {
    return [self safeStringForKey:@"name" inDict:self.repo];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView gh_registerCellClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];

    [self.tableView gh_registerCellClass:[UITableViewCell class] forCellReuseIdentifier:@"ReadmeCell"];

    self.headerView = [[GHRepoHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 10)];
    __weak typeof(self) weakHeaderSelf = self;
    self.headerView.onOwnerTapped = ^{
        [weakHeaderSelf openOwnerProfile];
    };
    self.headerView.onHomepageTapped = ^(NSURL *url) {
        [weakHeaderSelf openExternalURL:url];
    };
    self.headerView.onForksTapped = ^{
        [weakHeaderSelf openForks];
    };
    self.headerView.onStarButtonTapped = ^{
        [weakHeaderSelf toggleStar];
    };

    [self fetchRepoDetailIfNeeded];
    [self fetchReadme];
    [self fetchStarStatusIfNeeded];
    [self fetchLatestRelease];

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppDidEnterBackground)
                                                  name:kGHAppDidEnterBackgroundNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppWillEnterForeground)
                                                  name:kGHAppWillEnterForegroundNotification
                                                object:nil];

    [self applyTheme];
}

- (void)handleAppDidEnterBackground {
    if (!self.readmeWebView || !self.readmeHTMLReady) return;

    self.readmeWebViewUnloadedForBackground = YES;

    self.readmeWebView.delegate = nil;
    [self.readmeWebView stopLoading];
    [self.readmeWebView loadHTMLString:@"" baseURL:nil];
    [self.readmeWebView removeFromSuperview];
    self.readmeWebView = nil;
}

- (void)handleAppWillEnterForeground {
    if (!self.readmeWebViewUnloadedForBackground) return;

    if (!self.isViewLoaded || !self.view.window) return;

    [self reloadReadmeWebViewAfterBackgroundUnload];
}

- (void)reloadReadmeWebViewAfterBackgroundUnload {
    self.readmeWebViewUnloadedForBackground = NO;
    if (self.readmeInlineBodyHTML.length == 0) return;

    NSString *html = [GHMarkdownRenderer htmlDocumentWrappingBody:self.readmeInlineBodyHTML
                                                          pixelWidth:self.readmeRenderedWidth];

    [self loadReadmeHTML:html width:self.readmeRenderedWidth];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.readmeWebViewUnloadedForBackground) {
        [self reloadReadmeWebViewAfterBackgroundUnload];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleLanguageDidChange {
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();

    if (self.readmeHTMLReady && self.readmeWebView) {
        BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
        NSString *js = [GHMarkdownRenderer themeToggleScriptForDarkModeEnabled:isDark];
        [self.readmeWebView stringByEvaluatingJavaScriptFromString:js];
    }

    [self.headerView applyTheme];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)fetchRepoDetailIfNeeded {
    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];
    if (ownerLogin.length == 0 || repoName.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] repoDetailForOwner:ownerLogin repo:repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || ![jsonObject isKindOfClass:[NSDictionary class]]) return;

        strongSelf.repo = jsonObject;
        [strongSelf refreshHeader];
        [strongSelf.tableView reloadData];
    }];
}

- (void)handlePullToRefresh {
    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];

    if (ownerLogin.length == 0 || repoName.length == 0) {
        if (GHPullToRefreshAvailable()) { [self.refreshControl endRefreshing]; } else { [self.gh_legacyRefreshControl endRefreshing]; }
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] repoDetailForOwner:ownerLogin repo:repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }

        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            strongSelf.repo = jsonObject;
            [strongSelf refreshHeader];
            [strongSelf.tableView reloadData];
        }

        [strongSelf fetchReadme];
        [strongSelf fetchStarStatusIfNeeded];
        [strongSelf fetchLatestRelease];
    }];
}

- (void)fetchReadme {
    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];

    if (ownerLogin.length == 0 || repoName.length == 0) {
        self.readmeLoadAttempted = YES;
        [self notifyReadmeFullHTMLReady:nil];
        return;
    }

    self.readmeLoading = YES;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] readmeForOwner:ownerLogin repo:repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;

        NSDictionary *readmeDict = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        NSString *base64Content = [strongSelf safeStringForKey:@"content" inDict:readmeDict];
        NSString *readmeName = [strongSelf safeStringForKey:@"name" inDict:readmeDict];
        if (readmeName.length > 0) strongSelf.readmeFileName = readmeName;

        if (!error && base64Content.length > 0) {

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *decodedData = [strongSelf dataFromBase64String:base64Content];
                NSString *markdownText = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];

                markdownText = [markdownText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
                markdownText = [markdownText stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

                markdownText = [strongSelf flattenDetailsSummaryTags:markdownText];

                NSArray *chunks = [strongSelf splitMarkdownIntoChunks:markdownText];

                NSMutableArray *chunkBodies = [NSMutableArray array];
                for (NSString *chunk in chunks) {
                    NSString *chunkHTML = [strongSelf bodyHTMLForChunk:chunk] ?: @"";

                    chunkHTML = [GHMarkdownRenderer inlineUserAttachmentImagesInHTML:chunkHTML
                                                                            ownerLogin:ownerLogin
                                                                              repoName:repoName];
                    [chunkBodies addObject:chunkHTML];
                }

                NSString *fullBody = [chunkBodies componentsJoinedByString:@""];
                NSString *fullHTML = [GHMarkdownRenderer htmlDocumentWrappingBody:fullBody];

                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf2 = weakSelf;
                    strongSelf2.readmeLoading = NO;
                    strongSelf2.readmeLoadAttempted = YES;
                    strongSelf2.readmeFullHTML = fullHTML;

                    [strongSelf2 notifyReadmeFullHTMLReady:fullHTML];

                    if (chunkBodies.count > 0) {
                        NSMutableString *body = [NSMutableString string];

                        static const NSUInteger kPreviewClipThreshold = 600;
                        if (markdownText.length > kPreviewClipThreshold) {

                            NSString *balancedFirstChunk = [GHMarkdownRenderer autoCloseUnclosedTagsInHTML:chunkBodies[0]];
                            [body appendFormat:@"<div class=\"readme-clip\">%@</div>", balancedFirstChunk];
                            [body appendFormat:
                                @"<a href=\"app://readme-full\" class=\"show-more\">%@</a>",
                                GHL(@"Открыть README полностью →")];
                        } else {
                            [body appendString:chunkBodies[0]];
                        }

                        NSString *html = [GHMarkdownRenderer htmlDocumentWrappingBody:body
                                                                              pixelWidth:[strongSelf2 embeddedReadmeWebViewWidth]];
                        strongSelf2.readmeInlineBodyHTML = body;
                        [strongSelf2 loadReadmeHTML:html width:[strongSelf2 embeddedReadmeWebViewWidth]];

                        [strongSelf2 openFullReadmeForRestoreIfNeeded];
                    } else {
                        [strongSelf2.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionReadme]
                                              withRowAnimation:UITableViewRowAnimationNone];
                    }
                });
            });
            return;
        }

        strongSelf.readmeLoading = NO;
        strongSelf.readmeLoadAttempted = YES;

        [strongSelf notifyReadmeFullHTMLReady:nil];
        [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionReadme]
                             withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (void)notifyReadmeFullHTMLReady:(NSString *)html {
    if (self.readmeFullHTMLReadyHandler == nil) return;
    void (^handler)(NSString *) = self.readmeFullHTMLReadyHandler;
    self.readmeFullHTMLReadyHandler = nil;
    handler(html);
}

- (NSString *)flattenDetailsSummaryTags:(NSString *)markdown {
    NSMutableString *text = [(markdown ?: @"") mutableCopy];

    NSRegularExpression *detailsOpen = [NSRegularExpression regularExpressionWithPattern:@"<details[^>]*>"
                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                     error:nil];
    [detailsOpen replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];

    NSRegularExpression *detailsClose = [NSRegularExpression regularExpressionWithPattern:@"</details\\s*>"
                                                                                    options:NSRegularExpressionCaseInsensitive
                                                                                      error:nil];
    [detailsClose replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@""];

    NSRegularExpression *summaryOpen = [NSRegularExpression regularExpressionWithPattern:@"<summary[^>]*>"
                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                     error:nil];
    [summaryOpen replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"**"];

    NSRegularExpression *summaryClose = [NSRegularExpression regularExpressionWithPattern:@"</summary\\s*>"
                                                                                    options:NSRegularExpressionCaseInsensitive
                                                                                      error:nil];
    [summaryClose replaceMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"**\n"];

    return text;
}

- (NSArray *)splitMarkdownIntoChunks:(NSString *)markdown {
    if (markdown.length == 0) return @[];

    static const NSUInteger kChunkCharBudget = 4000;
    NSArray *blocks = [markdown componentsSeparatedByString:@"\n\n"];

    NSMutableArray *chunks = [NSMutableArray array];
    NSMutableArray *currentBlocks = [NSMutableArray array];
    NSUInteger currentLength = 0;

    for (NSString *block in blocks) {

        if (block.length > kChunkCharBudget * 2) {
            if (currentBlocks.count > 0) {
                [chunks addObject:[currentBlocks componentsJoinedByString:@"\n\n"]];
                [currentBlocks removeAllObjects];
                currentLength = 0;
            }

            NSArray *sublines = [block componentsSeparatedByString:@"\n"];
            NSMutableArray *currentLines = [NSMutableArray array];
            NSUInteger subLength = 0;
            for (NSString *line in sublines) {
                [currentLines addObject:line];
                subLength += line.length + 1;
                if (subLength >= kChunkCharBudget) {
                    [chunks addObject:[currentLines componentsJoinedByString:@"\n"]];
                    [currentLines removeAllObjects];
                    subLength = 0;
                }
            }
            if (currentLines.count > 0) {
                [chunks addObject:[currentLines componentsJoinedByString:@"\n"]];
            }
            continue;
        }

        [currentBlocks addObject:block];
        currentLength += block.length + 2;

        if (currentLength >= kChunkCharBudget) {
            [chunks addObject:[currentBlocks componentsJoinedByString:@"\n\n"]];
            [currentBlocks removeAllObjects];
            currentLength = 0;
        }
    }
    if (currentBlocks.count > 0) {
        [chunks addObject:[currentBlocks componentsJoinedByString:@"\n\n"]];
    }

    return chunks;
}

- (NSString *)bodyHTMLForChunk:(NSString *)chunk {
    static const NSUInteger kMaxSingleChunkParseLength = 15000;
    if (chunk.length > kMaxSingleChunkParseLength) {
        NSString *escaped = chunk;
        escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
        escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
        return [NSString stringWithFormat:@"<pre style=\"white-space:pre-wrap;\">%@</pre>", escaped];
    }
    return [GHMarkdownRenderer bodyHTMLFromMarkdown:chunk
                                            repoOwner:[self ownerLogin]
                                             repoName:[self repoName]
                                    repoDefaultBranch:[self repoDefaultBranch]
                                             progress:nil];
}

- (CGFloat)embeddedReadmeWebViewWidth {

    return self.tableView.bounds.size.width - 20.0;
}

- (void)loadReadmeHTML:(NSString *)html width:(CGFloat)width {
    if (self.readmeWebView) {
        self.readmeWebView.delegate = nil;
        [self.readmeWebView stopLoading];
        [self.readmeWebView removeFromSuperview];
        self.readmeWebView = nil;
    }

    self.readmeWebView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
    self.readmeWebView.delegate = self;
    self.readmeWebView.opaque = NO;
    self.readmeWebView.backgroundColor = [UIColor clearColor];
    self.readmeWebView.scrollView.scrollEnabled = NO;
    self.readmeWebView.scrollView.bounces = NO;
    self.readmeWebView.dataDetectorTypes = UIDataDetectorTypeNone;
    self.readmeRenderedWidth = width;

    [self.readmeWebView loadHTMLString:html baseURL:[self readmeBaseURL]];

    [self.tableView beginUpdates];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:kSectionReadme]]
                           withRowAnimation:UITableViewRowAnimationNone];
    [self.tableView endUpdates];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != kSectionReadme) return;
    if (!self.readmeHTMLReady || !self.readmeWebView) return;
    if (self.readmeInlineBodyHTML.length == 0) return;

    CGFloat actualWidth = cell.contentView.bounds.size.width;
    if (actualWidth <= 0) return;
    if (fabs(actualWidth - self.readmeRenderedWidth) <= 1.0) return;

    self.readmeRenderedWidth = actualWidth;
    CGRect frame = self.readmeWebView.frame;
    frame.size.width = actualWidth;
    self.readmeWebView.frame = frame;

    NSString *html = [GHMarkdownRenderer htmlDocumentWrappingBody:self.readmeInlineBodyHTML
                                                          pixelWidth:actualWidth];
    [self.readmeWebView loadHTMLString:html baseURL:[self readmeBaseURL]];

}

- (NSURL *)readmeBaseURL {
    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];
    NSString *defaultBranch = [self repoDefaultBranch];

    if (ownerLogin.length == 0 || repoName.length == 0) {
        return [NSURL URLWithString:@"https://raw.githubusercontent.com"];
    }

    NSString *urlString = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/",
                            ownerLogin, repoName, defaultBranch];
    return [NSURL URLWithString:urlString];
}

- (NSString *)repoDefaultBranch {
    NSString *defaultBranch = [self safeStringForKey:@"default_branch" inDict:self.repo];
    return defaultBranch.length > 0 ? defaultBranch : @"main";
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView {

    if (self.readmeWebViewUnloadedForBackground) return;
    [self recomputeReadmeWebViewHeight];
}

- (void)recomputeReadmeWebViewHeight {
    NSString *heightString = [self.readmeWebView stringByEvaluatingJavaScriptFromString:@"document.body.scrollHeight"];
    CGFloat height = [heightString floatValue];
    if (height <= 0) height = 44;

    static const CGFloat kMaxInlineReadmeHeight = 2600.0;
    if (height > kMaxInlineReadmeHeight) height = kMaxInlineReadmeHeight;

    self.readmeWebViewHeight = height;
    self.readmeHTMLReady = YES;

    CGRect frame = self.readmeWebView.frame;
    frame.size.height = height;
    self.readmeWebView.frame = frame;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.tableView beginUpdates];
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:kSectionReadme]]
                                     withRowAnimation:UITableViewRowAnimationNone];
        [strongSelf.tableView endUpdates];
    });
}

- (void)pushFullReadmeWithScrollOffset:(CGPoint)scrollOffset {
    if (self.readmeFullHTML.length == 0) return;

    ReadmeViewController *readmeVC = [[ReadmeViewController alloc] init];
    readmeVC.html = self.readmeFullHTML;
    readmeVC.baseURL = [self readmeBaseURL];

    readmeVC.ownerLogin = [self ownerLogin];
    readmeVC.repoName = [self repoName];
    readmeVC.initialScrollOffset = scrollOffset;

    __weak typeof(self) weakSelf = self;
    readmeVC.refreshHandler = ^(void (^completion)(NSString *html)) {
        [weakSelf refreshReadmeWithCompletion:completion];
    };
    [self.navigationController pushViewController:readmeVC animated:YES];
}

- (void)refreshReadmeWithCompletion:(void (^)(NSString *html))completion {
    if (completion == nil) return;

    self.readmeFullHTMLReadyHandler = ^(NSString *html) {
        completion(html);
    };

    self.readmeLoadAttempted = NO;
    self.readmeLoading = NO;
    [self fetchReadme];
}

- (void)openFullReadmeForRestoreIfNeeded {
    if (!self.autoOpenFullReadme) return;
    self.autoOpenFullReadme = NO;

    CGPoint offset = self.autoOpenReadmeScrollOffset;

    [self pushFullReadmeWithScrollOffset:offset];
}

- (BOOL)webView:(UIWebView *)webView
    shouldStartLoadWithRequest:(NSURLRequest *)request
                navigationType:(UIWebViewNavigationType)navigationType {

    if ([request.URL.scheme isEqualToString:@"app"] && [request.URL.host isEqualToString:@"readme-full"]) {
        [self pushFullReadmeWithScrollOffset:CGPointZero];
        return NO;
    }

    if ([request.URL.scheme isEqualToString:@"app"] && [request.URL.host isEqualToString:@"readme-img-loaded"]) {
        [self recomputeReadmeWebViewHeight];
        return NO;
    }

    if (navigationType == UIWebViewNavigationTypeLinkClicked) {

        NSString *fileOwner, *fileRepo, *filePath;
        if ([ReadmeViewController repoTextFileInfoFromURL:request.URL
                                                  ownerLogin:&fileOwner
                                                    repoName:&fileRepo
                                                        path:&filePath]) {
            [ReadmeViewController openRepoFileAtPath:filePath
                                            ownerLogin:fileOwner
                                              repoName:fileRepo
                                    fromViewController:self
                                           fallbackURL:request.URL];
            return NO;
        }

        NSString *commitOwner, *commitRepo, *commitSha;
        if ([CommitDetailViewController commitInfoFromURL:request.URL ownerLogin:&commitOwner repoName:&commitRepo sha:&commitSha]) {
            CommitDetailViewController *commitVC = [[CommitDetailViewController alloc] init];
            commitVC.ownerLogin = commitOwner;
            commitVC.repoName = commitRepo;
            commitVC.sha = commitSha;
            [self.navigationController pushViewController:commitVC animated:YES];
            return NO;
        }

        NSString *issueOwner, *issueRepo;
        NSInteger issueNumber = 0;
        if ([IssueListViewController issueNumberFromURL:request.URL ownerLogin:&issueOwner repoName:&issueRepo number:&issueNumber]) {
            [IssueDetailViewController pushIssueNumber:issueNumber ownerLogin:issueOwner repoName:issueRepo fromViewController:self];
            return NO;
        }

        NSString *issueListOwner, *issueListRepo;
        if ([IssueListViewController issueListInfoFromURL:request.URL ownerLogin:&issueListOwner repoName:&issueListRepo]) {
            IssueListViewController *issueListVC = [[IssueListViewController alloc] init];
            issueListVC.ownerLogin = issueListOwner;
            issueListVC.repoName = issueListRepo;
            [self.navigationController pushViewController:issueListVC animated:YES];
            return NO;
        }

        NSString *latestOwner, *latestRepo;
        if ([RepoDetailViewController latestReleaseInfoFromURL:request.URL ownerLogin:&latestOwner repoName:&latestRepo]) {
            [RepoDetailViewController pushLatestReleaseForOwnerLogin:latestOwner repoName:latestRepo fromViewController:self];
            return NO;
        }

        NSString *tagOwner, *tagRepo, *tagName;
        if ([RepoDetailViewController releaseByTagInfoFromURL:request.URL ownerLogin:&tagOwner repoName:&tagRepo tag:&tagName]) {
            [RepoDetailViewController pushReleaseForOwnerLogin:tagOwner repoName:tagRepo tag:tagName fromViewController:self];
            return NO;
        }

        NSString *releaseOwner, *releaseRepo;
        if ([RepoDetailViewController releaseListInfoFromURL:request.URL ownerLogin:&releaseOwner repoName:&releaseRepo]) {
            RepoDetailViewController *releasesVC = [[RepoDetailViewController alloc] init];
            releasesVC.ownerLogin = releaseOwner;
            releasesVC.repoName = releaseRepo;

            releasesVC.title = GHL(@"Релизы");
            [self.navigationController pushViewController:releasesVC animated:YES];
            return NO;
        }

        NSString *pullOwner, *pullRepo;
        NSInteger pullNumber = 0;
        if ([PullRequestDetailViewController pullRequestNumberFromURL:request.URL ownerLogin:&pullOwner repoName:&pullRepo number:&pullNumber]) {
            [PullRequestDetailViewController pushPullRequestNumber:pullNumber ownerLogin:pullOwner repoName:pullRepo fromViewController:self];
            return NO;
        }

        NSString *pullListOwner, *pullListRepo;
        if ([PullRequestListViewController pullRequestListInfoFromURL:request.URL ownerLogin:&pullListOwner repoName:&pullListRepo]) {
            PullRequestListViewController *pullListVC = [[PullRequestListViewController alloc] init];
            pullListVC.ownerLogin = pullListOwner;
            pullListVC.repoName = pullListRepo;
            [self.navigationController pushViewController:pullListVC animated:YES];
            return NO;
        }

        NSString *commitsOwner, *commitsRepo;
        if ([CommitHistoryViewController commitHistoryInfoFromURL:request.URL ownerLogin:&commitsOwner repoName:&commitsRepo]) {
            CommitHistoryViewController *historyVC = [[CommitHistoryViewController alloc] init];
            historyVC.ownerLogin = commitsOwner;
            historyVC.repoName = commitsRepo;
            [self.navigationController pushViewController:historyVC animated:YES];
            return NO;
        }

        NSString *forksOwner, *forksRepo;
        if ([ForkListViewController forkListInfoFromURL:request.URL ownerLogin:&forksOwner repoName:&forksRepo]) {
            ForkListViewController *forksVC = [[ForkListViewController alloc] init];
            forksVC.ownerLogin = forksOwner;
            forksVC.repoName = forksRepo;
            [self.navigationController pushViewController:forksVC animated:YES];
            return NO;
        }

        NSString *rootRelativeFileName;
        NSString *ownerLogin = [self ownerLogin];
        NSString *repoName = [self repoName];
        if (ownerLogin.length > 0 && repoName.length > 0 &&
            [ReadmeViewController rootRelativeRawFileNameFromURL:request.URL
                                                          fileName:&rootRelativeFileName]) {
            NSString *rawURLString = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/%@",
                                       ownerLogin, repoName, rootRelativeFileName];
            [ReadmeViewController openRepoFileAtPath:rootRelativeFileName
                                            ownerLogin:ownerLogin
                                              repoName:repoName
                                    fromViewController:self
                                           fallbackURL:[NSURL URLWithString:rawURLString]];
            return NO;
        }

        NSString *linkedOwner, *linkedRepo;
        if ([RepoOverviewViewController repoOverviewInfoFromURL:request.URL
                                                        ownerLogin:&linkedOwner
                                                          repoName:&linkedRepo]) {
            [RepoOverviewViewController pushRepoOverviewForOwnerLogin:linkedOwner
                                                               repoName:linkedRepo
                                                     fromViewController:self];
            return NO;
        }

        [[UIApplication sharedApplication] openURL:request.URL];
        return NO;
    }

    return YES;
}

- (void)fetchStarStatusIfNeeded {
    if (![GHAuthManager sharedManager].isAuthenticated) return;

    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];
    if (ownerLogin.length == 0 || repoName.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] checkStarredForOwner:ownerLogin repo:repoName completion:^(NSInteger statusCode, NSString *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;

        if (error) return;

        if (statusCode == 204 || statusCode == 404) {
            strongSelf.isStarred = (statusCode == 204);
            strongSelf.starStatusKnown = YES;
        } else {

            strongSelf.starCheckErrorMessage = [NSString stringWithFormat:@"HTTP %ld: %@",
                (long)statusCode, message.length > 0 ? message : GHL(@"неизвестная ошибка")];
        }

        [strongSelf reloadStarRow];
    }];
}

- (void)reloadStarRow {
    [self refreshHeader];
}

- (void)toggleStar {
    if (self.starActionInProgress) return;
    if (self.starCheckErrorMessage.length > 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                         message:[NSString stringWithFormat:GHL(@"Не удалось проверить, добавлен ли репозиторий в избранное: %@"), self.starCheckErrorMessage]
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
        return;
    }
    if (!self.starStatusKnown) return;

    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];
    if (ownerLogin.length == 0 || repoName.length == 0) return;

    self.starActionInProgress = YES;
    BOOL wasStarred = self.isStarred;

    __weak typeof(self) weakSelf = self;
    GHStatusCompletionBlock completion = ^(NSInteger statusCode, NSString *message, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.starActionInProgress = NO;

        if (!error && statusCode == 204) {
            strongSelf.isStarred = !wasStarred;
        } else {
            NSString *detail = message.length > 0 ? message : (error.localizedDescription ?: GHL(@"неизвестная ошибка"));

            if (!error && statusCode == 404) {
                detail = [detail stringByAppendingFormat:@"\n\n%@",
                    GHL(@"Возможно, у вашего токена нет прав на звёздочки. Для classic-токена нужен scope «public_repo», для fine-grained — разрешение «Starring».")];
            }

            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:[NSString stringWithFormat:GHL(@"Ошибка (HTTP %ld)"), (long)statusCode]
                                                             message:detail
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        }

        [strongSelf reloadStarRow];
    };

    [self reloadStarRow];

    if (wasStarred) {
        [[GHAPIClient sharedClient] unstarRepoForOwner:ownerLogin repo:repoName completion:completion];
    } else {
        [[GHAPIClient sharedClient] starRepoForOwner:ownerLogin repo:repoName completion:completion];
    }
}

- (NSData *)dataFromBase64String:(NSString *)base64String {
    static const char table[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static char reverseTable[128];
    static BOOL tableBuilt = NO;

    if (!tableBuilt) {
        memset(reverseTable, -1, sizeof(reverseTable));
        for (int i = 0; i < 64; i++) {
            reverseTable[(unsigned char)table[i]] = i;
        }
        tableBuilt = YES;
    }

    const char *input = [base64String cStringUsingEncoding:NSASCIIStringEncoding];
    if (!input) return nil;

    NSUInteger inputLength = strlen(input);
    NSMutableData *output = [NSMutableData dataWithCapacity:(inputLength * 3) / 4];

    int buffer = 0;
    int bitsCollected = 0;

    for (NSUInteger i = 0; i < inputLength; i++) {
        unsigned char c = (unsigned char)input[i];
        if (c >= 128 || reverseTable[c] == -1) {
            continue;
        }

        buffer = (buffer << 6) | reverseTable[c];
        bitsCollected += 6;

        if (bitsCollected >= 8) {
            bitsCollected -= 8;
            unsigned char byte = (buffer >> bitsCollected) & 0xFF;
            [output appendBytes:&byte length:1];
        }
    }

    return output;
}

- (NSString *)displayDateFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return nil;

    NSDateFormatter *isoFormatter = GHISODateFormatter();

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return nil;

    NSDateFormatter *displayFormatter = GHMediumDateFormatter();
    return [displayFormatter stringFromDate:date];
}

- (NSString *)readmePlaceholderText {
    if (self.readmeLoading) return GHL(@"Загрузка README…");
    if (self.readmeLoadAttempted) return GHL(@"README не найден");
    return GHL(@"Загрузка README…");
}

- (BOOL)shouldShowStarButton {
    return [GHAuthManager sharedManager].isAuthenticated;
}

- (BOOL)repoHasIssues {
    id value = self.repo[@"has_issues"];
    if (![value isKindOfClass:[NSNumber class]]) return YES;
    return [value boolValue];
}

- (NSString *)licenseName {
    NSDictionary *license = [self safeDictForKey:@"license" inDict:self.repo];
    NSString *spdx = [self safeStringForKey:@"spdx_id" inDict:license];
    if (spdx.length > 0 && ![spdx isEqualToString:@"NOASSERTION"]) return spdx;
    NSString *name = [self safeStringForKey:@"name" inDict:license];
    return name.length > 0 ? name : nil;
}

#pragma mark - Header

- (GHRepoStarState)currentStarState {
    if (![self shouldShowStarButton]) return GHRepoStarStateHidden;
    if (self.starActionInProgress) return GHRepoStarStateBusy;
    if (self.starCheckErrorMessage.length > 0) return GHRepoStarStateError;
    if (!self.starStatusKnown) return GHRepoStarStateChecking;
    return self.isStarred ? GHRepoStarStateStarred : GHRepoStarStateNotStarred;
}

- (void)refreshHeader {
    if (!self.headerView) return;
    CGFloat width = self.tableView.bounds.size.width > 0 ? self.tableView.bounds.size.width : 320;
    [self.headerView configureWithRepo:self.repo];
    [self.headerView setStarState:[self currentStarState]];
    CGFloat height = [self.headerView heightForWidth:width];
    self.headerView.frame = CGRectMake(0, 0, width, height);
    [self.headerView setNeedsLayout];
    self.tableView.tableHeaderView = self.headerView;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.headerView) return;
    if (self.tableView.tableHeaderView != self.headerView ||
        fabs(self.headerView.frame.size.width - self.tableView.bounds.size.width) > 0.5) {
        [self refreshHeader];
    }
}

#pragma mark - Latest release

- (void)fetchLatestRelease {
    NSString *ownerLogin = [self ownerLogin];
    NSString *repoName = [self repoName];
    if (ownerLogin.length == 0 || repoName.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] latestReleaseForOwner:ownerLogin repo:repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *release = (!error && [jsonObject isKindOfClass:[NSDictionary class]]) ? jsonObject : nil;
        if (release && [strongSelf safeStringForKey:@"tag_name" inDict:release].length == 0) release = nil;
        if (release == strongSelf.latestRelease) return;
        strongSelf.latestRelease = release;
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark - Rows

- (NSArray *)actionRowKinds {
    NSMutableArray *rows = [NSMutableArray arrayWithObjects:@(GHRepoRowKindIssues), @(GHRepoRowKindPullRequests), @(GHRepoRowKindReleases), nil];
    if (self.latestRelease) [rows addObject:@(GHRepoRowKindLatestRelease)];
    [rows addObject:@(GHRepoRowKindMore)];
    if (self.sectionsExpanded) [rows addObjectsFromArray:[self expandedRowKinds]];
    return rows;
}

- (NSArray *)expandedRowKinds {
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@(GHRepoRowKindForks)];
    if ([self licenseName]) [rows addObject:@(GHRepoRowKindLicense)];
    return rows;
}

- (NSArray *)codeRowKinds {
    NSMutableArray *rows = [NSMutableArray array];
    if ([self safeStringForKey:@"default_branch" inDict:self.repo].length > 0) [rows addObject:@(GHRepoRowKindBranch)];
    [rows addObject:@(GHRepoRowKindFiles)];
    [rows addObject:@(GHRepoRowKindCommits)];
    return rows;
}

- (NSArray *)rowKindsForSection:(NSInteger)section {
    if (section == kSectionActions) return [self actionRowKinds];
    if (section == kSectionCode) return [self codeRowKinds];
    return @[];
}

- (GHRepoRowKind)rowKindAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = [self rowKindsForSection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return GHRepoRowKindMore;
    return (GHRepoRowKind)[[rows objectAtIndex:indexPath.row] integerValue];
}

- (void)toggleSectionsExpanded {
    NSArray *rowsBefore = [self actionRowKinds];
    NSInteger moreIndex = [rowsBefore indexOfObject:@(GHRepoRowKindMore)];
    if (moreIndex == NSNotFound) return;

    NSInteger extraCount = [self expandedRowKinds].count;
    NSMutableArray *extraIndexPaths = [NSMutableArray array];
    for (NSInteger i = 0; i < extraCount; i++) {
        [extraIndexPaths addObject:[NSIndexPath indexPathForRow:moreIndex + 1 + i inSection:kSectionActions]];
    }
    NSIndexPath *moreIndexPath = [NSIndexPath indexPathForRow:moreIndex inSection:kSectionActions];

    self.sectionsExpanded = !self.sectionsExpanded;

    [self.tableView beginUpdates];
    if (self.sectionsExpanded) {
        [self.tableView insertRowsAtIndexPaths:extraIndexPaths withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:extraIndexPaths withRowAnimation:UITableViewRowAnimationFade];
    }
    [self.tableView endUpdates];

    BOOL expandedNow = self.sectionsExpanded;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableViewCell *moreCell = [self.tableView cellForRowAtIndexPath:moreIndexPath];
        CGAffineTransform targetTransform = expandedNow ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
        [UIView animateWithDuration:0.25 animations:^{
            moreCell.accessoryView.transform = targetTransform;
        }];
    });
}

- (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:15]
                    constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                        lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(size.height, 20);
}

#pragma mark - Icons

- (UIImage *)tileForIcon:(UIImage *)icon color:(UIColor *)color {
    return [GHIconRenderer tileWithIcon:icon backgroundColor:color size:30];
}

- (UIColor *)neutralTileColor {
    return [UIColor colorWithRed:0.33 green:0.36 blue:0.40 alpha:1.0];
}

- (UIImage *)tileImageForRowKind:(GHRepoRowKind)kind {
    UIColor *white = [UIColor whiteColor];
    switch (kind) {
        case GHRepoRowKindIssues:
            return [self tileForIcon:[GHIconRenderer issueOpenIconWithColor:white size:18]
                               color:[UIColor colorWithRed:0.18 green:0.64 blue:0.31 alpha:1.0]];
        case GHRepoRowKindPullRequests:
            return [self tileForIcon:[GHIconRenderer pullRequestIconWithColor:white size:18]
                               color:[UIColor colorWithRed:0.12 green:0.44 blue:0.95 alpha:1.0]];
        case GHRepoRowKindReleases:
            return [self tileForIcon:[GHIconRenderer tagIconWithColor:white size:18] color:[self neutralTileColor]];
        case GHRepoRowKindMore:
            return [self tileForIcon:[GHIconRenderer moreIconWithColor:white size:18] color:[self neutralTileColor]];
        case GHRepoRowKindForks:
            return [self tileForIcon:[GHIconRenderer forkIconWithColor:white size:18]
                               color:[UIColor colorWithRed:0.94 green:0.51 blue:0.24 alpha:1.0]];
        case GHRepoRowKindLicense:
            return [self tileForIcon:[GHIconRenderer lawIconWithColor:white size:18]
                               color:[UIColor colorWithRed:0.85 green:0.24 blue:0.28 alpha:1.0]];
        case GHRepoRowKindBranch:
            return [GHIconRenderer tileWithIcon:[GHIconRenderer branchIconWithColor:GHSecondaryTextColor() size:20]
                                backgroundColor:[UIColor clearColor]
                                           size:30];
        case GHRepoRowKindFiles:
            return [self tileForIcon:[GHIconRenderer codeIconWithColor:white size:18] color:[self neutralTileColor]];
        case GHRepoRowKindCommits:
            return [self tileForIcon:[GHIconRenderer commitIconWithColor:white size:18] color:[self neutralTileColor]];
        default:
            return nil;
    }
}

- (UIView *)moreChevronAccessory {
    static UIImage *chevronImage = nil;
    static dispatch_once_t chevronOnceToken;
    dispatch_once(&chevronOnceToken, ^{
        chevronImage = [GHIconRenderer disclosureChevronWithColor:[UIColor colorWithWhite:0.62 alpha:1.0]
                                                               size:CGSizeMake(12, 20)];
    });
    CGFloat chevronSide = MAX(chevronImage.size.width, chevronImage.size.height);
    UIView *chevronContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, chevronSide, chevronSide)];
    chevronContainer.backgroundColor = [UIColor clearColor];
    UIImageView *chevronImageView = [[UIImageView alloc] initWithImage:chevronImage];
    chevronImageView.center = CGPointMake(chevronSide / 2.0, chevronSide / 2.0);
    [chevronContainer addSubview:chevronImageView];
    return chevronContainer;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (UIView *)readmeSectionHeaderView {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 44)];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[GHIconRenderer infoIconWithColor:GHSecondaryTextColor() size:18]];
    icon.frame = CGRectMake(16, 16, 18, 18);
    [container addSubview:icon];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16 + 18 + 10, 12, container.bounds.size.width - 60, 26)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont fontWithName:@"Menlo-Regular" size:15] ?: [UIFont fontWithName:@"Courier" size:16] ?: [UIFont systemFontOfSize:15];
    label.textColor = GHSecondaryTextColor();
    label.text = self.readmeFileName.length > 0 ? self.readmeFileName : @"README";
    [container addSubview:label];
    return container;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == kSectionReadme) return [self readmeSectionHeaderView];
    return GHThemedSectionHeaderView(nil);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == kSectionReadme) return 44;
    return GHThemedSectionHeaderHeight(nil);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kSectionReadme) return 1;
    return [self rowKindsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionReadme) {
        if (self.readmeHTMLReady) {
            return self.readmeWebViewHeight;
        }
        CGFloat width = tableView.bounds.size.width - 40;
        return [self heightForText:[self readmePlaceholderText] width:width] + 24;
    }

    GHRepoRowKind kind = [self rowKindAtIndexPath:indexPath];
    if (kind == GHRepoRowKindLatestRelease || kind == GHRepoRowKindBranch) return 58;
    return 50;
}

- (UITableViewCell *)menuCellForTableView:(UITableView *)tableView style:(UITableViewCellStyle)style identifier:(NSString *)identifier {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
        cell.textLabel.backgroundColor = [UIColor clearColor];
        cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.indentationLevel = 0;
    cell.textLabel.textColor = GHPrimaryTextColor();
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    return cell;
}

- (UITableViewCell *)readmeCellForTableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView gh_dequeueCellWithIdentifier:@"ReadmeCell" forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.imageView.image = nil;

    if (self.readmeHTMLReady && self.readmeWebView) {
        cell.textLabel.text = nil;

        if (self.readmeWebView.superview != cell.contentView) {
            [self.readmeWebView removeFromSuperview];
            CGRect frame = self.readmeWebView.frame;
            frame.origin = CGPointZero;
            self.readmeWebView.frame = frame;
            [cell.contentView addSubview:self.readmeWebView];
        }
        return cell;
    }

    cell.textLabel.text = [self readmePlaceholderText];
    cell.textLabel.textColor = GHSecondaryTextColor();
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionReadme) {
        return [self readmeCellForTableView:tableView indexPath:indexPath];
    }

    GHRepoRowKind kind = [self rowKindAtIndexPath:indexPath];

    if (kind == GHRepoRowKindLatestRelease) {
        UITableViewCell *cell = [self menuCellForTableView:tableView style:UITableViewCellStyleSubtitle identifier:@"RepoReleaseCell"];
        cell.indentationWidth = 46;
        cell.indentationLevel = 1;
        NSString *name = [self safeStringForKey:@"name" inDict:self.latestRelease];
        NSString *tag = [self safeStringForKey:@"tag_name" inDict:self.latestRelease];
        cell.textLabel.text = name.length > 0 ? name : tag;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];

        NSString *when = GHRepoRelativeDate([self safeStringForKey:@"published_at" inDict:self.latestRelease]);
        NSString *latest = GHL(@"Последний");
        NSString *detail = when.length > 0 ? [NSString stringWithFormat:@"%@ · %@", when, latest] : latest;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.text = detail;
        if ([cell.detailTextLabel respondsToSelector:@selector(setAttributedText:)]) {
            NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:detail];
            [attributed addAttribute:GHForegroundColorAttributeName() value:GHSecondaryTextColor() range:NSMakeRange(0, detail.length)];
            [attributed addAttribute:GHForegroundColorAttributeName()
                               value:[UIColor colorWithRed:0.18 green:0.64 blue:0.31 alpha:1.0]
                               range:NSMakeRange(detail.length - latest.length, latest.length)];
            cell.detailTextLabel.attributedText = attributed;
        }
        cell.imageView.image = nil;
        GHApplyDisclosureIndicator(cell);
        return cell;
    }

    if (kind == GHRepoRowKindBranch) {
        UITableViewCell *cell = [self menuCellForTableView:tableView style:UITableViewCellStyleSubtitle identifier:@"RepoBranchCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = GHL(@"Текущая ветка");
        cell.textLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.detailTextLabel.text = [self repoDefaultBranch];
        cell.detailTextLabel.font = [UIFont fontWithName:@"Menlo-Regular" size:16] ?: [UIFont fontWithName:@"Courier" size:17] ?: [UIFont systemFontOfSize:16];
        cell.detailTextLabel.textColor = GHPrimaryTextColor();
        cell.imageView.image = [self tileImageForRowKind:kind];
        return cell;
    }

    UITableViewCell *cell = [self menuCellForTableView:tableView style:UITableViewCellStyleValue1 identifier:@"RepoMenuCell"];
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:17];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = [self tileImageForRowKind:kind];

    switch (kind) {
        case GHRepoRowKindIssues: {
            cell.textLabel.text = GHL(@"Задачи");
            if ([self repoHasIssues]) {
                NSNumber *openIssuesCount = [self safeNumberForKey:@"open_issues_count" inDict:self.repo];
                cell.detailTextLabel.text = [openIssuesCount stringValue];
            } else {
                cell.detailTextLabel.text = GHL(@"скрыты");
            }
            GHApplyDisclosureIndicator(cell);
            break;
        }
        case GHRepoRowKindPullRequests:
            cell.textLabel.text = GHL(@"Пул-реквесты");
            GHApplyDisclosureIndicator(cell);
            break;
        case GHRepoRowKindReleases:
            cell.textLabel.text = GHL(@"Релизы");
            GHApplyDisclosureIndicator(cell);
            break;
        case GHRepoRowKindMore: {
            cell.textLabel.text = GHL(@"Ещё");
            UIView *chevron = [self moreChevronAccessory];
            cell.accessoryView = chevron;
            BOOL expandedNow = self.sectionsExpanded;
            dispatch_async(dispatch_get_main_queue(), ^{
                chevron.transform = expandedNow ? CGAffineTransformMakeRotation((CGFloat)M_PI_2) : CGAffineTransformIdentity;
            });
            break;
        }
        case GHRepoRowKindForks: {
            cell.textLabel.text = GHL(@"Форки");
            cell.detailTextLabel.text = [[self safeNumberForKey:@"forks_count" inDict:self.repo] stringValue];
            GHApplyDisclosureIndicator(cell);
            break;
        }
        case GHRepoRowKindLicense:
            cell.textLabel.text = GHL(@"Лицензия");
            cell.detailTextLabel.text = [self licenseName];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case GHRepoRowKindFiles:
            cell.textLabel.text = GHL(@"Код");
            GHApplyDisclosureIndicator(cell);
            break;
        case GHRepoRowKindCommits:
            cell.textLabel.text = GHL(@"Коммиты");
            GHApplyDisclosureIndicator(cell);
            break;
        default:
            break;
    }
    return cell;
}

#pragma mark - Navigation

- (void)openOwnerProfile {
    NSString *ownerLogin = [self ownerLogin];
    if (ownerLogin.length == 0) return;
    PublicProfileViewController *profileVC = [[PublicProfileViewController alloc] init];
    profileVC.login = ownerLogin;
    [self.navigationController pushViewController:profileVC animated:YES];
}

- (void)openExternalURL:(NSURL *)url {
    if (!url) return;
    NSString *host = url.host.lowercaseString;
    if (([host isEqualToString:@"github.com"] || [host isEqualToString:@"www.github.com"]) &&
        [GHURLRouter routeGitHubURL:url fromViewController:self]) {
        return;
    }
    [[UIApplication sharedApplication] openURL:url];
}

- (void)openForks {
    ForkListViewController *forksVC = [[ForkListViewController alloc] init];
    forksVC.ownerLogin = [self ownerLogin];
    forksVC.repoName = [self repoName];
    [self.navigationController pushViewController:forksVC animated:YES];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == kSectionReadme) return;

    switch ([self rowKindAtIndexPath:indexPath]) {
        case GHRepoRowKindIssues: {
            if (![self repoHasIssues]) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Issues скрыты")
                                                                 message:GHL(@"Владелец репозитория отключил раздел Issues — GitHub не отдаёт по нему ни одной issue, поэтому список всегда будет пустым.")
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                [alert show];
                return;
            }
            IssueListViewController *issuesVC = [[IssueListViewController alloc] init];
            issuesVC.ownerLogin = [self ownerLogin];
            issuesVC.repoName = [self repoName];
            [self.navigationController pushViewController:issuesVC animated:YES];
            return;
        }
        case GHRepoRowKindPullRequests: {
            PullRequestListViewController *pullRequestsVC = [[PullRequestListViewController alloc] init];
            pullRequestsVC.ownerLogin = [self ownerLogin];
            pullRequestsVC.repoName = [self repoName];
            [self.navigationController pushViewController:pullRequestsVC animated:YES];
            return;
        }
        case GHRepoRowKindReleases: {
            RepoDetailViewController *releasesVC = [[RepoDetailViewController alloc] init];
            releasesVC.ownerLogin = [self ownerLogin];
            releasesVC.repoName = [self repoName];
            releasesVC.title = GHL(@"Релизы");
            [self.navigationController pushViewController:releasesVC animated:YES];
            return;
        }
        case GHRepoRowKindLatestRelease: {
            if (!self.latestRelease) return;
            ReleaseDetailViewController *releaseVC = [[ReleaseDetailViewController alloc] init];
            releaseVC.releaseInfo = self.latestRelease;
            releaseVC.ownerLogin = [self ownerLogin];
            releaseVC.repoName = [self repoName];
            [self.navigationController pushViewController:releaseVC animated:YES];
            return;
        }
        case GHRepoRowKindMore:
            [self toggleSectionsExpanded];
            return;
        case GHRepoRowKindForks:
            [self openForks];
            return;
        case GHRepoRowKindFiles: {
            RepoFilesViewController *filesVC = [[RepoFilesViewController alloc] init];
            filesVC.ownerLogin = [self ownerLogin];
            filesVC.repoName = [self repoName];
            filesVC.path = nil;
            filesVC.title = GHL(@"Файлы");
            [self.navigationController pushViewController:filesVC animated:YES];
            return;
        }
        case GHRepoRowKindCommits: {
            CommitHistoryViewController *commitsVC = [[CommitHistoryViewController alloc] init];
            commitsVC.ownerLogin = [self ownerLogin];
            commitsVC.repoName = [self repoName];
            [self.navigationController pushViewController:commitsVC animated:YES];
            return;
        }
        default:
            return;
    }
}

@end
