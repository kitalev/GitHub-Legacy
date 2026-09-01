#import "ReadmeViewController.h"
#import "AppDelegate.h"
#import "GHThemeManager.h"
#import "GHIconRenderer.h"
#import "GHMarkdownRenderer.h"
#import "GHAPIClient.h"
#import "GHLocalization.h"
#import "CommitDetailViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "IssueDetailViewController.h"
#import "IssueListViewController.h"
#import "PullRequestDetailViewController.h"
#import "PullRequestListViewController.h"
#import "CommitHistoryViewController.h"
#import "ForkListViewController.h"
#import "RepoDetailViewController.h"
#import "RepoOverviewViewController.h"
#import <string.h>

@interface ReadmeViewController ()
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, assign) CGPoint scrollOffsetBeforeBackgrounding;
@property (nonatomic, assign) BOOL hasPendingScrollRestore;

@property (nonatomic, assign) BOOL contentUnloadedForBackground;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, assign) BOOL waitingForInitialScrollReveal;
@end

@implementation ReadmeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.title.length == 0) {
        self.title = @"README";
    }
    self.view.backgroundColor = GHBackgroundColor();

    [self installWebView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    [self.spinner startAnimating];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppDidEnterBackground)
                                                  name:kGHAppDidEnterBackgroundNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppWillEnterForeground)
                                                  name:kGHAppWillEnterForegroundNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleThemeDidChange)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];

    [self.webView loadHTMLString:self.html ?: @"" baseURL:self.baseURL];
}

- (void)installWebView {
    if (self.webView != nil) return;

    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.dataDetectorTypes = UIDataDetectorTypeNone;

    self.webView.opaque = NO;
    self.webView.backgroundColor = GHWebViewBackgroundColor();

    self.webView.scalesPageToFit = NO;
    self.webView.scrollView.scrollsToTop = YES;

    self.webView.scrollView.directionalLockEnabled = YES;

    if (self.initialScrollOffset.y > 0) {
        self.waitingForInitialScrollReveal = YES;
        self.webView.hidden = YES;
    }
    [self.view addSubview:self.webView];

    if (self.refreshHandler != nil) {
        if (self.refreshControl == nil) {
            self.refreshControl = [[UIRefreshControl alloc] init];
            [self.refreshControl addTarget:self
                                    action:@selector(handlePullToRefresh)
                          forControlEvents:UIControlEventValueChanged];
        }
        [self.webView.scrollView addSubview:self.refreshControl];
    }
}

- (void)disableScrollsToTopOnNestedScrollViewsInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) {
            ((UIScrollView *)subview).scrollsToTop = NO;
        }
        [self disableScrollsToTopOnNestedScrollViewsInView:subview];
    }
}

- (void)refreshScrollsToTopState {
    if (self.webView == nil) return;
    self.webView.scrollView.scrollsToTop = YES;
    [self disableScrollsToTopOnNestedScrollViewsInView:self.webView.scrollView];
}

- (void)destroyWebView {
    if (self.webView == nil) return;

    self.webView.delegate = nil;
    self.webView.scrollView.delegate = nil;
    [self.webView stopLoading];
    [self.webView loadHTMLString:@"" baseURL:nil];
    [self.webView removeFromSuperview];
    self.webView = nil;
}

#pragma mark - Тема

- (void)handleThemeDidChange {
    self.view.backgroundColor = GHBackgroundColor();
    self.webView.backgroundColor = GHWebViewBackgroundColor();

    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
    NSString *js = [GHMarkdownRenderer themeToggleScriptForDarkModeEnabled:isDark];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

#pragma mark - Язык

- (void)handleLanguageDidChange {

    if (self.titleTranslationKey.length > 0) {
        self.title = GHL(self.titleTranslationKey);
    }

    if (self.codeViewerChunkLineCounts.count == 0) return;

    NSMutableArray *labels = [NSMutableArray array];
    for (NSNumber *countNumber in self.codeViewerChunkLineCounts) {
        NSInteger length = countNumber.integerValue;
        NSString *label = [NSString stringWithFormat:GHL(@"Показать ещё %ld %@"),
                            (long)length, [ReadmeViewController showMoreLinesWordForCount:length]];
        [labels addObject:label];
    }
    NSString *labelsJoined = [labels componentsJoinedByString:@"|"];

    NSString *js = [NSString stringWithFormat:
        @"(function(){"
         "var btn=document.getElementById('show-more');"
         "if(!btn)return;"

         "btn.setAttribute('data-labels','%@');"
         "var shown=parseInt(btn.getAttribute('data-shown'),10)||0;"
         "var labels=btn.getAttribute('data-labels').split('|');"
         "if(labels[shown])btn.innerHTML=labels[shown];"
         "})();",
        [ReadmeViewController escapeForSingleQuotedJavaScriptStringInReadme:labelsJoined]];
    [self evaluateJavaScript:js];
}

+ (NSString *)showMoreLinesWordForCount:(NSInteger)count {
    NSInteger mod100 = count % 100;
    NSInteger mod10 = count % 10;
    if (mod100 >= 11 && mod100 <= 14) return GHL(@"строк");
    if (mod10 == 1) return GHL(@"строку");
    if (mod10 >= 2 && mod10 <= 4) return GHL(@"строки");
    return GHL(@"строк");
}

+ (NSString *)escapeForSingleQuotedJavaScriptStringInReadme:(NSString *)text {
    NSString *escaped = text ?: @"";
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    return escaped;
}

#pragma mark - Фон/жизненный цикл

- (void)handleAppDidEnterBackground {
    if (self.html.length == 0) return;

    self.scrollOffsetBeforeBackgrounding = self.webView.scrollView.contentOffset;
    self.contentUnloadedForBackground = YES;

    if (self.ownerLogin.length > 0 && self.repoName.length > 0) {

        NSString *cachePath = [self cachedReadmeHTMLPath];
        BOOL htmlCached = NO;
        if (self.html.length > 0 && cachePath.length > 0) {
            htmlCached = [self.html writeToFile:cachePath
                                     atomically:YES
                                       encoding:NSUTF8StringEncoding
                                          error:NULL];
        }

        NSMutableDictionary *state = [NSMutableDictionary dictionaryWithDictionary:@{
            @"ownerLogin": self.ownerLogin,
            @"repoName": self.repoName,
            @"scrollY": @(self.scrollOffsetBeforeBackgrounding.y),
            @"savedAt": @([NSDate timeIntervalSinceReferenceDate])
        }];
        if (htmlCached) {
            state[@"htmlPath"] = cachePath;
            if (self.baseURL.absoluteString.length > 0) {
                state[@"baseURL"] = self.baseURL.absoluteString;
            }
        }
        [[NSUserDefaults standardUserDefaults] setObject:state forKey:kGHOpenReadmeStateKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }

    [self destroyWebView];
}

- (NSString *)cachedReadmeHTMLPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *caches = paths.firstObject;
    if (caches.length == 0) return nil;
    return [caches stringByAppendingPathComponent:@"gh_restore_readme.html"];
}

- (void)handleAppWillEnterForeground {
    if (!self.contentUnloadedForBackground) return;

    if (!self.isViewLoaded || !self.view.window) return;

    [self reloadContentAfterBackgroundUnload];
}

- (void)reloadContentAfterBackgroundUnload {
    self.contentUnloadedForBackground = NO;

    [self installWebView];
    if (self.html.length == 0) return;
    self.hasPendingScrollRestore = YES;
    [self.webView loadHTMLString:self.html baseURL:self.baseURL];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (self.contentUnloadedForBackground) {
        [self reloadContentAfterBackgroundUnload];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (self.isMovingFromParentViewController) {
        self.webView.delegate = nil;
        self.webView.scrollView.delegate = nil;
        [self.webView stopLoading];
        [self.webView loadHTMLString:@"" baseURL:nil];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.spinner stopAnimating];

    self.webView.scrollView.scrollsToTop = YES;

    [self refreshScrollsToTopState];
    __weak typeof(self) weakSelfScroll = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelfScroll refreshScrollsToTopState];
    });

    [self handleThemeDidChange];

    if (self.hasPendingScrollRestore) {
        self.hasPendingScrollRestore = NO;
        [self applyScrollOffsetWithRetries:self.scrollOffsetBeforeBackgrounding attempt:0];
    }

    if (self.initialScrollOffset.y > 0) {
        CGPoint initialOffset = self.initialScrollOffset;
        self.initialScrollOffset = CGPointZero;
        [self applyScrollOffsetWithRetries:initialOffset attempt:0];
    } else if (self.waitingForInitialScrollReveal) {

        [self revealWebViewAfterInitialScroll];
    }
}

- (void)applyScrollOffsetWithRetries:(CGPoint)offset attempt:(NSInteger)attempt {
    if (self.webView == nil) return;

    UIScrollView *scrollView = self.webView.scrollView;
    CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - scrollView.bounds.size.height);
    CGPoint target = CGPointMake(offset.x, MIN(offset.y, maxOffsetY));
    [scrollView setContentOffset:target animated:NO];

    BOOL reachedTarget = (fabs(scrollView.contentOffset.y - offset.y) < 1.0);
    static const NSInteger kMaxScrollRestoreAttempts = 8;

    if (!reachedTarget && attempt < kMaxScrollRestoreAttempts) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf applyScrollOffsetWithRetries:offset attempt:(attempt + 1)];
        });
        return;
    }

    [self revealWebViewAfterInitialScroll];
}

- (void)revealWebViewAfterInitialScroll {
    if (!self.waitingForInitialScrollReveal) return;
    self.waitingForInitialScrollReveal = NO;
    self.webView.alpha = 0.0;
    self.webView.hidden = NO;
    [UIView animateWithDuration:0.15 animations:^{
        self.webView.alpha = 1.0;
    }];
}

- (void)handlePullToRefresh {
    if (self.refreshHandler == nil) {
        [self.refreshControl endRefreshing];
        return;
    }

    CGPoint offset = self.webView.scrollView.contentOffset;

    __weak typeof(self) weakSelf = self;
    self.refreshHandler(^(NSString *freshHTML) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) return;

        [strongSelf.refreshControl endRefreshing];
        if (freshHTML.length == 0) return;

        strongSelf.html = freshHTML;
        strongSelf.scrollOffsetBeforeBackgrounding = offset;
        strongSelf.hasPendingScrollRestore = YES;
        [strongSelf.webView loadHTMLString:freshHTML baseURL:strongSelf.baseURL];
    });
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    [self.spinner stopAnimating];
}

- (BOOL)webView:(UIWebView *)webView
    shouldStartLoadWithRequest:(NSURLRequest *)request
                navigationType:(UIWebViewNavigationType)navigationType {

    if ([request.URL.scheme isEqualToString:@"app"]) {
        return NO;
    }

    if (navigationType == UIWebViewNavigationTypeLinkClicked) {

        if ([self scrollToAnchorFromURLIfNeeded:request.URL]) {
            return NO;
        }

        NSString *owner, *repo, *sha;
        if ([CommitDetailViewController commitInfoFromURL:request.URL ownerLogin:&owner repoName:&repo sha:&sha]) {
            CommitDetailViewController *detailVC = [[CommitDetailViewController alloc] init];
            detailVC.ownerLogin = owner;
            detailVC.repoName = repo;
            detailVC.sha = sha;
            [self.navigationController pushViewController:detailVC animated:YES];
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
            IssueListViewController *listVC = [[IssueListViewController alloc] init];
            listVC.ownerLogin = issueListOwner;
            listVC.repoName = issueListRepo;
            [self.navigationController pushViewController:listVC animated:YES];
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
            PullRequestListViewController *listVC = [[PullRequestListViewController alloc] init];
            listVC.ownerLogin = pullListOwner;
            listVC.repoName = pullListRepo;
            [self.navigationController pushViewController:listVC animated:YES];
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

        NSString *rootRelativeFileName;
        if (self.ownerLogin.length > 0 && self.repoName.length > 0 &&
            [ReadmeViewController rootRelativeRawFileNameFromURL:request.URL
                                                          fileName:&rootRelativeFileName]) {
            NSString *rawURLString = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/%@",
                                       self.ownerLogin, self.repoName, rootRelativeFileName];
            [ReadmeViewController openRepoFileAtPath:rootRelativeFileName
                                            ownerLogin:self.ownerLogin
                                              repoName:self.repoName
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

#pragma mark - Ссылки на другой markdown/текстовый файл этого же репозитория

+ (BOOL)repoTextFileInfoFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName
                             path:(NSString **)path {
    if (url == nil) return NO;

    static NSRegularExpression *blobRegex = nil;
    static NSRegularExpression *rawRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        blobRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://(?:www\\.)?github\\.com/([^/]+)/([^/]+)/(?:blob|raw)/[^/]+/([^?#]+)"
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
        rawRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://raw\\.githubusercontent\\.com/([^/]+)/([^/]+)/[^/]+/([^?#]+)"
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
    });

    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [blobRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) {
        match = [rawRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    }
    if (match == nil) return NO;

    NSString *matchedPath = [urlString substringWithRange:[match rangeAtIndex:3]];

    NSString *decodedPath = [matchedPath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: matchedPath;

    NSString *extension = [decodedPath.pathExtension lowercaseString];
    NSSet *allowedExtensions = [NSSet setWithObjects:@"md", @"markdown", @"mdown", @"mkd", @"txt", @"rst", nil];

    NSString *lastComponent = decodedPath.lastPathComponent.lowercaseString;
    BOOL looksLikePlainTextFile = [lastComponent isEqualToString:@"readme"] ||
                                    [lastComponent isEqualToString:@"license"] ||
                                    [lastComponent isEqualToString:@"changelog"] ||
                                    [lastComponent isEqualToString:@"contributing"];
    if (![allowedExtensions containsObject:extension] && !looksLikePlainTextFile) {
        return NO;
    }

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    if (path != NULL) *path = decodedPath;
    return YES;
}

- (BOOL)scrollToAnchorFromURLIfNeeded:(NSURL *)url {
    NSString *fragment = url.fragment;
    if (fragment.length == 0) return NO;

    NSString *base = self.baseURL.absoluteString ?: @"";
    NSString *target = url.absoluteString ?: @"";
    NSRange hashRange = [target rangeOfString:@"#" options:NSBackwardsSearch];
    NSString *targetWithoutFragment = hashRange.location != NSNotFound
        ? [target substringToIndex:hashRange.location]
        : target;

    BOOL sameDocument = (targetWithoutFragment.length == 0)
        || [targetWithoutFragment isEqualToString:base]
        || [base hasPrefix:targetWithoutFragment]
        || [targetWithoutFragment hasPrefix:base];
    if (!sameDocument) return NO;

    NSString *decoded = [fragment stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: fragment;
    NSString *escaped = [decoded stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

    NSString *js = [NSString stringWithFormat:
        @"(function(){var e=document.getElementById('%@');"
         "if(!e){var l=document.getElementsByName('%@');e=l&&l.length?l[0]:null;}"
         "if(!e)return -1;var y=0;while(e){y+=e.offsetTop;e=e.offsetParent;}return y;})()",
        escaped, escaped];

    NSString *result = [self.webView stringByEvaluatingJavaScriptFromString:js];
    if (result.length == 0) return NO;

    CGFloat y = (CGFloat)[result doubleValue];
    if (y < 0) return NO;

    UIScrollView *scrollView = self.webView.scrollView;
    CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - scrollView.bounds.size.height);
    [scrollView setContentOffset:CGPointMake(0, MIN(y, maxOffsetY)) animated:YES];
    return YES;
}

+ (BOOL)rootRelativeRawFileNameFromURL:(NSURL *)url fileName:(NSString **)fileName {
    if (url == nil) return NO;
    if (![url.host.lowercaseString isEqualToString:@"raw.githubusercontent.com"]) return NO;

    NSString *path = url.path;
    if (path.length <= 1) return NO;

    NSString *withoutLeadingSlash = [path substringFromIndex:1];

    if ([withoutLeadingSlash rangeOfString:@"/"].location != NSNotFound) return NO;

    NSString *decoded = [withoutLeadingSlash stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: withoutLeadingSlash;

    NSString *extension = decoded.pathExtension.lowercaseString;
    NSSet *allowedExtensions = [NSSet setWithObjects:@"md", @"markdown", @"mdown", @"mkd", @"txt", @"rst", nil];
    NSString *lowercaseName = decoded.lowercaseString;
    BOOL looksLikePlainTextFile = [lowercaseName isEqualToString:@"readme"] ||
                                    [lowercaseName isEqualToString:@"license"] ||
                                    [lowercaseName isEqualToString:@"changelog"] ||
                                    [lowercaseName isEqualToString:@"contributing"];
    if (![allowedExtensions containsObject:extension] && !looksLikePlainTextFile) return NO;

    if (fileName != NULL) *fileName = decoded;
    return YES;
}

+ (void)openRepoFileAtPath:(NSString *)path
                  ownerLogin:(NSString *)ownerLogin
                    repoName:(NSString *)repoName
          fromViewController:(UIViewController *)fromViewController
                 fallbackURL:(NSURL *)fallbackURL {
    __weak UIViewController *weakFromVC = fromViewController;

    void (^openInSafari)(void) = ^{
        if (fallbackURL != nil) {
            [[UIApplication sharedApplication] openURL:fallbackURL];
        }
    };

    [[GHAPIClient sharedClient] fileContentsForOwner:ownerLogin
                                                  repo:repoName
                                                  path:path
                                            completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        NSDictionary *fileDict = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        id contentValue = fileDict[@"content"];
        NSString *base64Content = [contentValue isKindOfClass:[NSString class]] ? contentValue : nil;

        if (error || base64Content.length == 0) {

            NSLog(@"ReadmeViewController: не удалось открыть %@/%@/%@ в приложении (%@) — открываю в Safari: %@",
                  ownerLogin, repoName, path,
                  error.localizedDescription.length > 0 ? error.localizedDescription : @"пустой ответ",
                  fallbackURL);
            openInSafari();
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *decodedData = [self dataFromBase64String:base64Content];
            NSString *markdownText = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];

            if (markdownText.length == 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    openInSafari();
                });
                return;
            }

            markdownText = [markdownText stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
            markdownText = [markdownText stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

            NSString *bodyHTML = [GHMarkdownRenderer bodyHTMLFromMarkdown:markdownText
                                                                  repoOwner:ownerLogin
                                                                   repoName:repoName];
            bodyHTML = [GHMarkdownRenderer inlineUserAttachmentImagesInHTML:bodyHTML
                                                                    ownerLogin:ownerLogin
                                                                      repoName:repoName];
            NSString *fullHTML = [GHMarkdownRenderer htmlDocumentWrappingBody:bodyHTML];

            dispatch_async(dispatch_get_main_queue(), ^{
                __strong UIViewController *strongFromVC2 = weakFromVC;
                if (!strongFromVC2) return;

                NSString *directoryPath = path.stringByDeletingLastPathComponent;
                NSString *baseURLString = directoryPath.length > 0
                    ? [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/%@/", ownerLogin, repoName, directoryPath]
                    : [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/", ownerLogin, repoName];
                NSURL *rawBaseURL = [NSURL URLWithString:baseURLString];

                ReadmeViewController *readmeVC = [[ReadmeViewController alloc] init];
                readmeVC.html = fullHTML;
                readmeVC.baseURL = rawBaseURL;
                readmeVC.ownerLogin = ownerLogin;
                readmeVC.repoName = repoName;
                readmeVC.title = path.lastPathComponent;
                [strongFromVC2.navigationController pushViewController:readmeVC animated:YES];
            });
        });
    }];
}

+ (NSData *)dataFromBase64String:(NSString *)base64String {
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

- (void)evaluateJavaScript:(NSString *)js {
    if (js.length == 0) return;

    if (!self.isViewLoaded) return;
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

@end
