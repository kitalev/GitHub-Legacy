#import "CommitDetailViewController.h"
#import "AppDelegate.h"
#import "GHThemeManager.h"
#import "GHAPIClient.h"
#import "GHLocalization.h"
#import "IssueDetailViewController.h"
#import "IssueListViewController.h"
#import "RepoDetailViewController.h"
#import "RepoOverviewViewController.h"
#import "GHCompat.h"
#import "GHMarkdownRenderer.h"
#import "GHLegacyRefreshControl.h"
#import "PublicProfileViewController.h"

@interface CommitDetailViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) GHLegacyRefreshControl *legacyRefreshControl;

@property (nonatomic, copy) NSString *lastLoadedHTML;
@property (nonatomic, strong) NSDictionary *lastCommitJSON;
@property (nonatomic, assign) NSUInteger renderGeneration;

@property (nonatomic, strong) UIView *stickyHeaderView;
@property (nonatomic, assign) BOOL stickyChevronOpen;
@property (nonatomic, assign) CGFloat pendingSnapTop;
@property (nonatomic, assign) BOOL gh_suppressStickyHeaderUpdates;
@property (nonatomic, strong) UILabel *stickyNameLabel;
@property (nonatomic, strong) UILabel *stickyStatusLabel;
@property (nonatomic, strong) UILabel *stickyAddLabel;
@property (nonatomic, strong) UILabel *stickyDelLabel;
@property (nonatomic, strong) NSArray *fileSectionMetrics;
@property (nonatomic, assign) NSInteger stickyFileIndex;
@property (nonatomic, strong) UIView *stickyChevronView;
@end

@implementation CommitDetailViewController

+ (BOOL)commitInfoFromURL:(NSURL *)url
                ownerLogin:(NSString **)ownerLogin
                  repoName:(NSString **)repoName
                       sha:(NSString **)sha {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/commit/([0-9a-fA-F]{7,40})"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    if (sha != NULL) *sha = [urlString substringWithRange:[match rangeAtIndex:3]];
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = GHL(@"Коммит");
    self.view.backgroundColor = GHBackgroundColor();

    [self installWebView];

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

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    [self loadCommitDetail];
}

- (void)handlePullToRefresh {
    [self loadCommitDetail];
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

- (void)loadCommitDetail {
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] commitDetailForOwner:self.ownerLogin
                                                  repo:self.repoName
                                                   sha:self.sha
                                            completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.spinner stopAnimating];
        [strongSelf.refreshControl endRefreshing];
        [strongSelf.legacyRefreshControl endRefreshing];

        if (error || ![jsonObject isKindOfClass:[NSDictionary class]]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription ?: GHL(@"Не удалось загрузить коммит")
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        strongSelf.lastCommitJSON = jsonObject;
        [strongSelf renderCommitJSON:jsonObject];
    }];
}

- (void)renderCommitJSON:(NSDictionary *)commitJSON {
    NSUInteger generation = ++self.renderGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *html = [strongSelf htmlForCommit:commitJSON];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf.renderGeneration != generation) return;
            strongSelf.lastLoadedHTML = html;
            [strongSelf.webView loadHTMLString:html baseURL:nil];
        });
    });
}

- (void)installWebView {
    if (self.webView != nil) return;

    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.dataDetectorTypes = UIDataDetectorTypeNone;

    self.webView.opaque = NO;
    self.webView.backgroundColor = GHWebViewBackgroundColor();
    [self.view addSubview:self.webView];

    if (GHPullToRefreshAvailable()) {
        if (self.refreshControl == nil) {
            self.refreshControl = [[UIRefreshControl alloc] init];
            [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
        }
        [self.webView.scrollView addSubview:self.refreshControl];
    } else if (self.legacyRefreshControl == nil) {
        self.legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.webView.scrollView];
        [self.legacyRefreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
        self.webView.scrollView.delegate = self;
    }

    [self installStickyHeaderIfNeeded];
}

#pragma mark - Sticky file header (iOS 5 fallback for position:sticky)

- (BOOL)gh_needsNativeStickyHeader {
    return !GHPullToRefreshAvailable();
}

- (void)installStickyHeaderIfNeeded {
    if (![self gh_needsNativeStickyHeader]) return;
    if (self.stickyHeaderView != nil) return;

    self.stickyFileIndex = NSNotFound;

    BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.backgroundColor = dark ? [UIColor colorWithWhite:0.11 alpha:1.0]
                                  : [UIColor colorWithRed:0.965 green:0.973 blue:0.980 alpha:1.0];
    header.hidden = YES;
    header.userInteractionEnabled = YES;

    UIColor *lineColor = dark ? [UIColor colorWithWhite:0.2 alpha:1.0]
                              : [UIColor colorWithWhite:0.87 alpha:1.0];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, header.bounds.size.width, 1)];
    topLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    topLine.backgroundColor = lineColor;
    [header addSubview:topLine];

    UIView *bottomLine = [[UIView alloc] initWithFrame:CGRectMake(0, 43, header.bounds.size.width, 1)];
    bottomLine.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    bottomLine.backgroundColor = lineColor;
    [header addSubview:bottomLine];

    UIView *chevron = [[UIView alloc] initWithFrame:CGRectMake(13, 12, 9, 9)];
    chevron.backgroundColor = [UIColor clearColor];
    UIView *right = [[UIView alloc] initWithFrame:CGRectMake(7, 0, 2, 9)];
    UIView *bottom = [[UIView alloc] initWithFrame:CGRectMake(0, 7, 9, 2)];
    UIColor *chevronColor = dark ? [UIColor colorWithWhite:0.55 alpha:1.0]
                                 : [UIColor colorWithRed:0.416 green:0.451 blue:0.494 alpha:1.0];
    right.backgroundColor = chevronColor;
    bottom.backgroundColor = chevronColor;
    [chevron addSubview:right];
    [chevron addSubview:bottom];
    chevron.transform = CGAffineTransformMakeRotation(M_PI_4);
    [header addSubview:chevron];

    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 4, header.bounds.size.width - 42, 18)];
    nameLabel.backgroundColor = [UIColor clearColor];
    nameLabel.font = [UIFont boldSystemFontOfSize:13];
    nameLabel.textColor = dark ? [UIColor colorWithWhite:0.85 alpha:1.0] : [UIColor blackColor];
    [header addSubview:nameLabel];

    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 4, header.bounds.size.width - 42, 18)];
    statusLabel.backgroundColor = [UIColor clearColor];
    statusLabel.font = [UIFont systemFontOfSize:13];
    statusLabel.textColor = dark ? [UIColor colorWithWhite:0.6 alpha:1.0] : [UIColor colorWithWhite:0.4 alpha:1.0];
    [header addSubview:statusLabel];

    UILabel *addLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    addLabel.backgroundColor = [UIColor clearColor];
    addLabel.font = [UIFont systemFontOfSize:12];
    addLabel.textColor = [UIColor colorWithRed:0.133 green:0.525 blue:0.227 alpha:1.0];
    [header addSubview:addLabel];

    UILabel *delLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    delLabel.backgroundColor = [UIColor clearColor];
    delLabel.font = [UIFont systemFontOfSize:12];
    delLabel.textColor = [UIColor colorWithRed:0.796 green:0.141 blue:0.192 alpha:1.0];
    [header addSubview:delLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                          action:@selector(handleStickyHeaderTap)];
    [header addGestureRecognizer:tap];

    self.stickyChevronView = chevron;
    self.stickyNameLabel = nameLabel;
    self.stickyStatusLabel = statusLabel;
    self.stickyAddLabel = addLabel;
    self.stickyDelLabel = delLabel;
    self.stickyHeaderView = header;
    [self.view addSubview:header];

    self.webView.scrollView.delegate = self;
}

- (void)refreshFileSectionMetrics {
    if (![self gh_needsNativeStickyHeader] || self.webView == nil) return;

    NSString *js =
        @"(function(){"
         "var out=[];"
         "var hs=document.getElementsByClassName('file-header');"
         "for(var i=0;i<hs.length;i++){"
         "var h=hs[i];var top=0;var n=h;"
         "while(n){top+=n.offsetTop;n=n.offsetParent;}"
         "var sec=h.parentNode;"
         "var nameEl=h.getElementsByClassName('file-name')[0];"
         "var name='';"
         "if(nameEl){"
         "for(var c=0;c<nameEl.childNodes.length;c++){"
         "var node=nameEl.childNodes[c];"
         "if(node.nodeType===3){name+=node.nodeValue;}"
         "}"
         "}"
         "name=name.replace(/^\\s+|\\s+$/g,'').replace(/[\\r\\n]+/g,' ');"
         "var statusEl=h.getElementsByClassName('file-status')[0];"
         "var status=statusEl?(statusEl.innerText||statusEl.textContent):'';"
         "var addEl=h.getElementsByClassName('stat-add')[0];"
         "var delEl=h.getElementsByClassName('stat-del')[0];"
         "var adds=addEl?addEl.innerText||addEl.textContent:'';"
         "var dels=delEl?delEl.innerText||delEl.textContent:'';"
         "var content=document.getElementById('file-content-'+i);"
         "var open=(content&&content.style.display!=='none')?'1':'0';"
         "out.push([top,top+sec.offsetHeight,h.offsetHeight,"
         "name,status,adds,dels,open].join(SEP_U));"
         "}"
         "return out.join(SEP_R);"
         "})()";

    NSString *recordSep = [NSString stringWithFormat:@"%C", (unichar)0x001e];
    NSString *unitSep = [NSString stringWithFormat:@"%C", (unichar)0x001f];
    js = [js stringByReplacingOccurrencesOfString:@"SEP_U"
                                       withString:[NSString stringWithFormat:@"String.fromCharCode(%d)", 0x1f]];
    js = [js stringByReplacingOccurrencesOfString:@"SEP_R"
                                       withString:[NSString stringWithFormat:@"String.fromCharCode(%d)", 0x1e]];

    NSString *raw = [self.webView stringByEvaluatingJavaScriptFromString:js];
    if (raw.length == 0) {
        self.fileSectionMetrics = nil;
        [self updateStickyHeader];
        return;
    }

    NSMutableArray *metrics = [NSMutableArray array];
    for (NSString *row in [raw componentsSeparatedByString:recordSep]) {
        NSArray *parts = [row componentsSeparatedByString:unitSep];
        if (parts.count < 8) continue;
        [metrics addObject:@{
            @"top": @([[parts objectAtIndex:0] doubleValue]),
            @"bottom": @([[parts objectAtIndex:1] doubleValue]),
            @"height": @([[parts objectAtIndex:2] doubleValue]),
            @"name": [parts objectAtIndex:3],
            @"status": [parts objectAtIndex:4],
            @"adds": [parts objectAtIndex:5],
            @"dels": [parts objectAtIndex:6],
            @"open": @([[parts objectAtIndex:7] boolValue]),
        }];
    }
    self.fileSectionMetrics = metrics;
    [self updateStickyHeader];
}

- (void)gh_scheduleStickyDomIndexSync {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(gh_syncStickyDomIndex)
                                               object:nil];
    [self performSelector:@selector(gh_syncStickyDomIndex) withObject:nil afterDelay:0.06];
}

- (void)gh_syncStickyDomIndex {
    if (self.webView == nil) return;
    NSInteger domIndex = (self.stickyFileIndex == NSNotFound) ? -1 : self.stickyFileIndex;
    [self.webView stringByEvaluatingJavaScriptFromString:
        [NSString stringWithFormat:@"ghSetStickyDomIndex(%ld);", (long)domIndex]];
}

- (void)updateStickyHeader {
    if (self.gh_suppressStickyHeaderUpdates) return;
    if (![self gh_needsNativeStickyHeader] || self.stickyHeaderView == nil) return;

    NSArray *metrics = self.fileSectionMetrics;
    if (metrics.count == 0) {
        self.stickyHeaderView.hidden = YES;
        self.stickyFileIndex = NSNotFound;
        return;
    }

    CGFloat offsetY = self.webView.scrollView.contentOffset.y;

    NSInteger activeIndex = NSNotFound;
    CGFloat pushUp = 0;

    for (NSUInteger i = 0; i < metrics.count; i++) {
        NSDictionary *m = [metrics objectAtIndex:i];
        if (![[m objectForKey:@"open"] boolValue]) continue;

        CGFloat top = [[m objectForKey:@"top"] doubleValue];
        CGFloat bottom = [[m objectForKey:@"bottom"] doubleValue];
        CGFloat height = [[m objectForKey:@"height"] doubleValue];

        if (offsetY >= top && offsetY < bottom) {
            activeIndex = (NSInteger)i;

            CGFloat remaining = bottom - offsetY;
            if (remaining < height) pushUp = height - remaining;
            break;
        }
    }

    if (activeIndex == NSNotFound) {
        self.stickyHeaderView.hidden = YES;
        if (self.stickyFileIndex != NSNotFound) {
            [self gh_scheduleStickyDomIndexSync];
        }
        self.stickyFileIndex = NSNotFound;
        return;
    }

    NSDictionary *activeMetrics = [metrics objectAtIndex:activeIndex];
    BOOL activeOpen = [[activeMetrics objectForKey:@"open"] boolValue];

    if (activeIndex != self.stickyFileIndex) {
        self.stickyFileIndex = activeIndex;

        [self gh_scheduleStickyDomIndexSync];

        [self applyStickyChevronOpen:activeOpen animated:YES];
        self.stickyChevronOpen = activeOpen;
        [self layoutStickyHeaderContentWithMetrics:activeMetrics];
    } else if (activeOpen != self.stickyChevronOpen) {
        [self applyStickyChevronOpen:activeOpen animated:YES];
        self.stickyChevronOpen = activeOpen;
        [self layoutStickyHeaderContentWithMetrics:activeMetrics];
    }

    CGRect frame = self.stickyHeaderView.frame;
    frame.origin.y = self.webView.frame.origin.y - pushUp;
    self.stickyHeaderView.frame = frame;
    self.stickyHeaderView.hidden = NO;
    [self.view bringSubviewToFront:self.stickyHeaderView];
}

- (void)layoutStickyHeaderContentWithMetrics:(NSDictionary *)m {
    CGFloat width = self.stickyHeaderView.bounds.size.width;

    NSString *name = [m objectForKey:@"name"];
    NSString *status = [m objectForKey:@"status"];
    NSString *adds = [m objectForKey:@"adds"];
    NSString *dels = [m objectForKey:@"dels"];

    self.stickyNameLabel.text = name;
    CGSize nameSize = [name sizeWithFont:self.stickyNameLabel.font];

    CGFloat statusMaxWidth = MAX(width - 42 - nameSize.width - 4, 0);
    self.stickyStatusLabel.text = status;
    self.stickyStatusLabel.frame = CGRectMake(30 + nameSize.width + 4, 4, statusMaxWidth, 18);
    self.stickyNameLabel.frame = CGRectMake(30, 4, nameSize.width, 18);

    CGFloat rightEdge = width - 12;

    self.stickyDelLabel.text = dels;
    CGSize delSize = [dels sizeWithFont:self.stickyDelLabel.font];
    self.stickyDelLabel.frame = CGRectMake(rightEdge - delSize.width, 22, delSize.width, 16);

    self.stickyAddLabel.text = adds;
    CGSize addSize = [adds sizeWithFont:self.stickyAddLabel.font];
    CGFloat addOrigin = rightEdge - delSize.width - (delSize.width > 0 ? 6 : 0) - addSize.width;
    self.stickyAddLabel.frame = CGRectMake(addOrigin, 22, addSize.width, 16);
}

- (void)applyStickyChevronOpen:(BOOL)open animated:(BOOL)animated {

    CGAffineTransform t = CGAffineTransformMakeRotation(open ? M_PI_4 : -M_PI_4);
    if (!animated) {
        self.stickyChevronView.transform = t;
        return;
    }
    [UIView animateWithDuration:0.25 animations:^{
        self.stickyChevronView.transform = t;
    }];
}

- (void)gh_snapScrollToTop:(id)ignored {
    self.gh_suppressStickyHeaderUpdates = NO;
    if (self.webView == nil) return;

    UIScrollView *scrollView = self.webView.scrollView;
    if (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) {
        /* the user has already taken control of scrolling since the tap;
           forcing contentOffset here would fight their gesture and make
           scrolling feel broken, so just back off. */
        return;
    }

    [scrollView setContentOffset:CGPointMake(0, self.pendingSnapTop) animated:NO];
}

- (void)handleStickyHeaderTap {
    if (self.stickyFileIndex == NSNotFound || self.webView == nil) return;
    if (self.stickyFileIndex >= (NSInteger)self.fileSectionMetrics.count) return;

    NSInteger tappedIndex = self.stickyFileIndex;
    NSDictionary *m = [self.fileSectionMetrics objectAtIndex:tappedIndex];
    CGFloat top = [[m objectForKey:@"top"] doubleValue];
    BOOL wasOpen = [[m objectForKey:@"open"] boolValue];

    [self applyStickyChevronOpen:!wasOpen animated:!wasOpen];
    self.stickyChevronOpen = !wasOpen;

    NSString *js = [NSString stringWithFormat:@"toggleFile(%ld);", (long)tappedIndex];
    [self.webView stringByEvaluatingJavaScriptFromString:js];
    [self refreshFileSectionMetrics];

    self.stickyFileIndex = NSNotFound;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(gh_syncStickyDomIndex)
                                               object:nil];
    [self gh_syncStickyDomIndex];
    self.gh_suppressStickyHeaderUpdates = YES;

    if (wasOpen) {
        self.stickyHeaderView.hidden = YES;
    }

    [self.webView.scrollView setContentOffset:CGPointMake(0, top) animated:NO];
    self.gh_suppressStickyHeaderUpdates = NO;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateStickyHeader];
    [self.legacyRefreshControl gh_scrollViewDidScroll];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [self.legacyRefreshControl gh_scrollViewDidEndDragging];
}

- (void)destroyWebView {
    if (self.webView == nil) return;
    self.gh_suppressStickyHeaderUpdates = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(refreshFileSectionMetrics)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(gh_snapScrollToTop:)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(gh_syncStickyDomIndex)
                                               object:nil];
    self.webView.scrollView.delegate = nil;
    self.webView.delegate = nil;
    [self.webView stopLoading];
    [self.webView loadHTMLString:@"" baseURL:nil];
    [self.refreshControl removeFromSuperview];
    [self.legacyRefreshControl removeFromSuperview];
    self.legacyRefreshControl = nil;
    [self.webView removeFromSuperview];
    self.webView = nil;

    [self.stickyHeaderView removeFromSuperview];
    self.stickyHeaderView = nil;
    self.stickyNameLabel = nil;
    self.stickyStatusLabel = nil;
    self.stickyAddLabel = nil;
    self.stickyDelLabel = nil;
    self.stickyChevronView = nil;
    self.fileSectionMetrics = nil;
    self.stickyFileIndex = NSNotFound;
}

- (void)handleAppDidEnterBackground {
    if (self.lastLoadedHTML.length == 0) return;
    [self destroyWebView];
}

- (void)handleAppWillEnterForeground {
    if (self.lastLoadedHTML.length == 0) return;
    [self installWebView];
    [self.webView loadHTMLString:self.lastLoadedHTML baseURL:nil];
}

- (void)handleThemeDidChange {
    if (self.lastCommitJSON == nil || self.webView == nil) return;

    self.view.backgroundColor = GHBackgroundColor();
    self.webView.backgroundColor = GHWebViewBackgroundColor();

    [self.stickyHeaderView removeFromSuperview];
    self.stickyHeaderView = nil;
    self.stickyFileIndex = NSNotFound;
    self.fileSectionMetrics = nil;
    [self installStickyHeaderIfNeeded];

    [self renderCommitJSON:self.lastCommitJSON];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView {

    [self performSelector:@selector(refreshFileSectionMetrics) withObject:nil afterDelay:0.1];
}

- (BOOL)webView:(UIWebView *)webView
    shouldStartLoadWithRequest:(NSURLRequest *)request
                navigationType:(UIWebViewNavigationType)navigationType {

    if ([[request.URL scheme] isEqualToString:@"ghlegacy-layout"]) {
        [self refreshFileSectionMetrics];
        return NO;
    }

    if ([[request.URL scheme] isEqualToString:@"ghlegacy-copy"]) {
        NSString *sha = [self safeStringForKey:@"sha" inDict:self.lastCommitJSON];
        if (sha.length > 0) [UIPasteboard generalPasteboard].string = sha;
        return NO;
    }

    if ([[request.URL scheme] isEqualToString:@"ghlegacy-user"]) {
        NSString *login = request.URL.host;
        if (login.length > 0) {
            PublicProfileViewController *profileVC = [[PublicProfileViewController alloc] init];
            profileVC.login = login;
            [self.navigationController pushViewController:profileVC animated:YES];
        }
        return NO;
    }

    if (navigationType != UIWebViewNavigationTypeLinkClicked) {
        return YES;
    }

    NSString *owner, *repo, *sha;
    if ([[self class] commitInfoFromURL:request.URL ownerLogin:&owner repoName:&repo sha:&sha]) {
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
        [self.navigationController pushViewController:releasesVC animated:YES];
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

- (NSString *)escapeHTML:(NSString *)text {
    text = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    text = [text stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    text = [text stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return text;
}

static const NSInteger kDiffChunkSize = 80;

- (NSString *)diffHTMLFromPatch:(NSString *)patch fileIndex:(NSInteger)fileIndex {
    if (patch.length == 0) return @"";

    NSArray *lines = [patch componentsSeparatedByString:@"\n"];
    NSMutableArray *gutterRows = [NSMutableArray array];
    NSMutableArray *codeRows = [NSMutableArray array];

    NSInteger oldLine = 0;
    NSInteger newLine = 0;

    NSRegularExpression *hunkRegex = [NSRegularExpression regularExpressionWithPattern:@"^@@ -(\\d+)(?:,\\d+)? \\+(\\d+)(?:,\\d+)? @@"
                                                                                options:0
                                                                                  error:nil];

    for (NSString *line in lines) {
        if (line.length == 0) continue;
        NSString *escaped = [self escapeHTML:line];

        if ([line hasPrefix:@"@@"]) {
            NSTextCheckingResult *match = [hunkRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
            if (match) {
                oldLine = [[line substringWithRange:[match rangeAtIndex:1]] integerValue];
                newLine = [[line substringWithRange:[match rangeAtIndex:2]] integerValue];
            }
            [gutterRows addObject:@"<div class=\"ln-row diff-hunk\">&nbsp;</div>"];
            [codeRows addObject:[NSString stringWithFormat:@"<tr class=\"diff-hunk\"><td class=\"code-cell\">%@</td></tr>", escaped]];
            continue;
        }

        if ([line hasPrefix:@"\\"]) {

            [gutterRows addObject:@"<div class=\"ln-row diff-ctx\">&nbsp;</div>"];
            [codeRows addObject:[NSString stringWithFormat:@"<tr class=\"diff-ctx\"><td class=\"code-cell\">%@</td></tr>", escaped]];
            continue;
        }

        NSString *cssClass;
        NSString *oldNumStr = @"";
        NSString *newNumStr = @"";

        if ([line hasPrefix:@"+"]) {
            cssClass = @"diff-add";
            newNumStr = [NSString stringWithFormat:@"%ld", (long)newLine];
            newLine++;
        } else if ([line hasPrefix:@"-"]) {
            cssClass = @"diff-del";
            oldNumStr = [NSString stringWithFormat:@"%ld", (long)oldLine];
            oldLine++;
        } else {
            cssClass = @"diff-ctx";
            oldNumStr = [NSString stringWithFormat:@"%ld", (long)oldLine];
            newNumStr = [NSString stringWithFormat:@"%ld", (long)newLine];
            oldLine++;
            newLine++;
        }

        [gutterRows addObject:[NSString stringWithFormat:@"<div class=\"ln-row %@\"><span class=\"ln-old\">%@</span><span class=\"ln-new\">%@</span></div>",
                                cssClass, oldNumStr, newNumStr]];
        [codeRows addObject:[NSString stringWithFormat:@"<tr class=\"%@\"><td class=\"code-cell\">%@</td></tr>", cssClass, escaped]];
    }

    NSInteger totalRows = gutterRows.count;
    NSInteger totalChunks = (totalRows + kDiffChunkSize - 1) / kDiffChunkSize;
    if (totalChunks == 0) totalChunks = 1;

    NSMutableString *result = [NSMutableString string];
    NSMutableString *gutterChunk0 = [NSMutableString string];
    NSMutableString *codeChunk0 = [NSMutableString string];
    NSMutableString *gutterHidden = [NSMutableString string];
    NSMutableString *codeHidden = [NSMutableString string];
    NSMutableArray *chunkLabels = [NSMutableArray array];

    for (NSInteger chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
        NSInteger start = chunkIdx * kDiffChunkSize;
        NSInteger end = MIN(start + kDiffChunkSize, totalRows);
        if (start >= end) break;

        NSString *gutterPart = [[gutterRows subarrayWithRange:NSMakeRange(start, end - start)] componentsJoinedByString:@""];
        NSString *codePart = [[codeRows subarrayWithRange:NSMakeRange(start, end - start)] componentsJoinedByString:@""];

        if (chunkIdx == 0) {
            [gutterChunk0 appendString:gutterPart];
            [codeChunk0 appendString:codePart];
        } else {

            [gutterHidden appendFormat:@"<div class=\"more-rows\" id=\"gutter-chunk-%ld-%ld\" style=\"display:none;\">%@</div>",
                                         (long)fileIndex, (long)chunkIdx, gutterPart];
            [codeHidden appendFormat:@"<div class=\"more-rows\" id=\"code-chunk-%ld-%ld\" style=\"display:none;\">"
                                       "<table class=\"diff-table\"><tbody>%@</tbody></table></div>",
                                       (long)fileIndex, (long)chunkIdx, codePart];
            NSInteger chunkLineCount = end - start;
            NSString *label = [NSString stringWithFormat:GHL(@"Показать ещё %ld %@"), (long)chunkLineCount, [self linesWordForCount:chunkLineCount]];
            [chunkLabels addObject:label];
        }
    }

    [result appendFormat:
        @"<div class=\"diff-block\">"
         "<div class=\"diff-gutter\">%@%@</div>"
         "<div class=\"diff-code\"><table class=\"diff-table\"><tbody>%@</tbody></table>%@</div>"
         "</div>",
        gutterChunk0, gutterHidden, codeChunk0, codeHidden];

    if (chunkLabels.count > 0) {
        NSMutableArray *escapedLabels = [NSMutableArray array];
        for (NSString *label in chunkLabels) {
            [escapedLabels addObject:[label stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]];
        }
        NSString *labelsAttr = [escapedLabels componentsJoinedByString:@"|"];

        [result appendFormat:@"<div class=\"show-more\" id=\"show-more-%ld\" "
                               "data-total=\"%ld\" data-shown=\"0\" data-labels=\"%@\" "
                               "ontouchstart=\"fileTouchStart(event)\" ontouchend=\"moreTouchEnd(event,%ld)\">%@</div>",
                               (long)fileIndex, (long)chunkLabels.count, labelsAttr, (long)fileIndex, chunkLabels[0]];
    }

    return result;
}

- (NSString *)linesWordForCount:(NSInteger)count {
    NSInteger mod100 = count % 100;
    NSInteger mod10 = count % 10;
    if (mod100 >= 11 && mod100 <= 14) return GHL(@"строк");
    if (mod10 == 1) return GHL(@"строку");
    if (mod10 >= 2 && mod10 <= 4) return GHL(@"строки");
    return GHL(@"строк");
}

- (BOOL)isImageFilename:(NSString *)filename {
    NSString *lower = [filename lowercaseString];
    NSArray *extensions = @[@".png", @".jpg", @".jpeg", @".gif", @".webp", @".bmp", @".svg"];
    for (NSString *ext in extensions) {
        if ([lower hasSuffix:ext]) return YES;
    }
    return NO;
}

- (NSString *)rawURLForFilename:(NSString *)filename atSHA:(NSString *)sha {
    NSMutableArray *encodedParts = [NSMutableArray array];
    for (NSString *part in [filename componentsSeparatedByString:@"/"]) {
        NSString *encoded = [part stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: part;
        [encodedParts addObject:encoded];
    }
    NSString *encodedPath = [encodedParts componentsJoinedByString:@"/"];
    return [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/%@",
            self.ownerLogin, self.repoName, sha, encodedPath];
}

static NSString *GHCommitL(NSString *ru, NSString *en) {
    return [[GHLocalization sharedManager].languageCode isEqualToString:@"en"] ? en : ru;
}

- (NSString *)groupedNumber:(NSInteger)value {
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.groupingSeparator = @" ";
        formatter.usesGroupingSeparator = YES;
        formatter.groupingSize = 3;
    });
    NSString *text = nil;
    @synchronized (formatter) {
        text = [formatter stringFromNumber:@(value)];
    }
    return text ?: [NSString stringWithFormat:@"%ld", (long)value];
}

- (NSString *)relativeDateFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return @"";
    NSDate *date = GHDateFromISO8601String(isoString);
    if (!date) return @"";
    NSTimeInterval seconds = MAX(-[date timeIntervalSinceNow], 0);
    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    BOOL en = [[GHLocalization sharedManager].languageCode isEqualToString:@"en"];
    if (minutes < 1) return en ? @"now" : @"сейчас";
    if (minutes < 60) return [NSString stringWithFormat:en ? @"%ldm" : @"%ld мин", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:en ? @"%ldh" : @"%ld ч", (long)hours];
    if (days < 30) return [NSString stringWithFormat:en ? @"%ldd" : @"%ld д", (long)days];
    if (days < 365) return [NSString stringWithFormat:en ? @"%ldmo" : @"%ld мес", (long)(days / 30)];
    return [NSString stringWithFormat:en ? @"%ldy" : @"%ld г", (long)(days / 365)];
}

- (NSString *)filesChangedText:(NSInteger)count {
    NSString *number = [self groupedNumber:count];
    if ([[GHLocalization sharedManager].languageCode isEqualToString:@"en"]) {
        return [NSString stringWithFormat:@"%@ %@", number, count == 1 ? @"file changed" : @"files changed"];
    }
    NSInteger mod10 = count % 10;
    NSInteger mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return [NSString stringWithFormat:@"%@ файл изменён", number];
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return [NSString stringWithFormat:@"%@ файла изменено", number];
    return [NSString stringWithFormat:@"%@ файлов изменено", number];
}

- (NSString *)avatarHTML:(NSString *)url size:(NSInteger)size {
    if (url.length == 0) {
        return [NSString stringWithFormat:@"<span class=\"avatar\" style=\"width:%ldpx;height:%ldpx;\"></span>", (long)size, (long)size];
    }
    NSString *sep = [url rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&";
    return [NSString stringWithFormat:@"<img class=\"avatar\" style=\"width:%ldpx;height:%ldpx;\" src=\"%@%@s=%ld\"/>",
            (long)size, (long)size, [self escapeHTML:url], sep, (long)size * 2];
}

- (NSString *)personRowHTMLWithLogin:(NSString *)login name:(NSString *)name avatarURL:(NSString *)avatarURL {
    NSString *display = login.length > 0 ? login : (name ?: @"");
    NSString *inner = [NSString stringWithFormat:@"%@<span class=\"person-name\">%@</span>",
                       [self avatarHTML:avatarURL size:40], [self escapeHTML:display]];
    if (login.length > 0) {
        return [NSString stringWithFormat:@"<a class=\"detail-row person\" href=\"ghlegacy-user://%@\">%@</a>", [self escapeHTML:login], inner];
    }
    return [NSString stringWithFormat:@"<div class=\"detail-row person\">%@</div>", inner];
}

- (NSString *)htmlForCommit:(NSDictionary *)commitJSON {
    NSDictionary *commitData = [self safeDictForKey:@"commit" inDict:commitJSON];
    NSDictionary *authorData = [self safeDictForKey:@"author" inDict:commitData];
    NSDictionary *committerData = [self safeDictForKey:@"committer" inDict:commitData];
    NSDictionary *ghAuthor = [self safeDictForKey:@"author" inDict:commitJSON];
    NSDictionary *ghCommitter = [self safeDictForKey:@"committer" inDict:commitJSON];
    NSString *message = [self safeStringForKey:@"message" inDict:commitData] ?: @"";
    NSString *authorName = [self safeStringForKey:@"name" inDict:authorData] ?: @"";
    NSString *authorLogin = [self safeStringForKey:@"login" inDict:ghAuthor];
    NSString *authorAvatar = [self safeStringForKey:@"avatar_url" inDict:ghAuthor];
    NSString *date = [self safeStringForKey:@"date" inDict:authorData];
    NSString *sha = [self safeStringForKey:@"sha" inDict:commitJSON] ?: @"";
    NSString *shortSHA = sha.length >= 7 ? [sha substringToIndex:7] : sha;

    NSString *parentSHA = sha;
    NSArray *parents = [commitJSON[@"parents"] isKindOfClass:[NSArray class]] ? commitJSON[@"parents"] : @[];
    if (parents.count > 0) {
        NSDictionary *parentDict = [parents[0] isKindOfClass:[NSDictionary class]] ? parents[0] : nil;
        NSString *candidateSHA = [self safeStringForKey:@"sha" inDict:parentDict];
        if (candidateSHA.length > 0) parentSHA = candidateSHA;
    }

    NSString *trimmed = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *titleLine = trimmed;
    NSString *bodyText = @"";
    NSRange nl = [trimmed rangeOfString:@"\n"];
    if (nl.location != NSNotFound) {
        titleLine = [trimmed substringToIndex:nl.location];
        bodyText = [[trimmed substringFromIndex:nl.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    NSArray *files = [commitJSON[@"files"] isKindOfClass:[NSArray class]] ? commitJSON[@"files"] : @[];
    NSDictionary *stats = [self safeDictForKey:@"stats" inDict:commitJSON];
    NSInteger totalAdd = [[self safeNumberForKey:@"additions" inDict:stats] integerValue];
    NSInteger totalDel = [[self safeNumberForKey:@"deletions" inDict:stats] integerValue];
    if (stats == nil) {
        for (NSDictionary *file in files) {
            if (![file isKindOfClass:[NSDictionary class]]) continue;
            totalAdd += [[self safeNumberForKey:@"additions" inDict:file] integerValue];
            totalDel += [[self safeNumberForKey:@"deletions" inDict:file] integerValue];
        }
    }

    NSMutableString *body = [NSMutableString string];

    [body appendFormat:@"<div class=\"tabs\">"
                         "<div class=\"tab active\" id=\"tab-btn-changes\" ontouchstart=\"fileTouchStart(event)\" ontouchend=\"tabTouchEnd(event,'changes')\">%@</div>"
                         "<div class=\"tab\" id=\"tab-btn-details\" ontouchstart=\"fileTouchStart(event)\" ontouchend=\"tabTouchEnd(event,'details')\">%@</div>"
                         "</div>",
                         GHCommitL(@"ИЗМЕНЕНИЯ", @"CHANGES"), GHCommitL(@"ПОДРОБНЕЕ", @"DETAILS")];

    [body appendString:@"<div id=\"tab-changes\">"];

    NSString *who = authorLogin.length > 0 ? authorLogin : authorName;
    [body appendFormat:@"<div class=\"commit-header\">"
                         "<div class=\"author-row\"><span class=\"author-date\">%@</span>%@"
                         "<span class=\"author-name\">%@</span> <span class=\"author-verb\">%@</span></div>"
                         "<div class=\"commit-title\">%@</div>",
                         [self escapeHTML:[self relativeDateFromISOString:date]],
                         [self avatarHTML:authorAvatar size:26],
                         [self escapeHTML:who], GHCommitL(@"автор", @"authored"),
                         [self escapeHTML:titleLine.length > 0 ? titleLine : GHL(@"(без сообщения)")]];
    if (bodyText.length > 0) {
        [body appendFormat:@"<pre class=\"commit-body\">%@</pre>", [self escapeHTML:bodyText]];
    }
    [body appendString:@"</div><div class=\"gap\"></div>"];

    [body appendFormat:@"<div class=\"summary\"><div class=\"summary-title\">%@</div>"
                         "<div class=\"summary-stats\"><span class=\"sum-add\">%@ %@</span>&nbsp;&nbsp;<span class=\"sum-del\">%@ %@</span></div></div>",
                         [self escapeHTML:[self filesChangedText:files.count]],
                         [self groupedNumber:totalAdd], GHCommitL(@"добавлено", totalAdd == 1 ? @"addition" : @"additions"),
                         [self groupedNumber:totalDel], GHCommitL(@"удалено", totalDel == 1 ? @"deletion" : @"deletions")];

    if (files.count == 0) {
        [body appendFormat:@"<div class=\"no-files\">%@</div>", GHCommitL(@"Нет данных об изменённых файлах.", @"No changed files.")];
    }

    NSInteger fileIndex = 0;
    for (NSDictionary *file in files) {
        if (![file isKindOfClass:[NSDictionary class]]) continue;

        NSString *filename = [self safeStringForKey:@"filename" inDict:file] ?: GHL(@"(файл)");
        NSString *status = [self safeStringForKey:@"status" inDict:file] ?: @"";
        NSInteger additions = [[self safeNumberForKey:@"additions" inDict:file] integerValue];
        NSInteger deletions = [[self safeNumberForKey:@"deletions" inDict:file] integerValue];
        NSString *patch = [self safeStringForKey:@"patch" inDict:file];

        NSString *statusText = status;
        NSString *statusClass = @"st-mod";
        if ([status isEqualToString:@"added"]) { statusText = GHCommitL(@"добавлен", @"added"); statusClass = @"st-add"; }
        else if ([status isEqualToString:@"removed"]) { statusText = GHCommitL(@"удалён", @"removed"); statusClass = @"st-del"; }
        else if ([status isEqualToString:@"modified"]) { statusText = GHCommitL(@"изменён", @"modified"); }
        else if ([status isEqualToString:@"renamed"]) { statusText = GHCommitL(@"переименован", @"renamed"); }

        NSString *baseName = [filename lastPathComponent];
        NSString *dirName = [filename stringByDeletingLastPathComponent];
        NSString *subline = dirName.length > 0 ? [NSString stringWithFormat:@"%@/ · %@", dirName, statusText] : statusText;

        [body appendFormat:@"<div class=\"file-section\">"
                             "<div class=\"file-header\" ontouchstart=\"fileTouchStart(event)\" ontouchend=\"fileTouchEnd(event,%ld)\">"
                             "<span class=\"toggle-icon\" id=\"toggle-%ld\" style=\"-webkit-transform:rotate(-45deg);transform:rotate(-45deg);\"></span>"
                             "<div class=\"file-stats\"><span class=\"stat-add\">+%@</span> <span class=\"stat-del\">−%@</span></div>"
                             "<div class=\"file-name\">%@<span class=\"file-status\"><i class=\"st-dot %@\"></i>%@</span></div>"
                             "</div>",
                             (long)fileIndex, (long)fileIndex,
                             [self groupedNumber:additions], [self groupedNumber:deletions],
                             [self escapeHTML:baseName], statusClass, [self escapeHTML:subline]];

        [body appendFormat:@"<div class=\"file-content\" id=\"file-content-%ld\" style=\"display:none;\">", (long)fileIndex];

        if (patch.length > 0) {
            [body appendString:[self diffHTMLFromPatch:patch fileIndex:fileIndex]];
        } else if ([self isImageFilename:filename]) {
            NSString *imageSHA = [status isEqualToString:@"removed"] ? parentSHA : sha;
            NSString *imageURL = [self rawURLForFilename:filename atSHA:imageSHA];
            [body appendFormat:@"<div class=\"image-preview\"><img src=\"%@\" alt=\"%@\"/></div>",
                                 imageURL, [self escapeHTML:filename]];
        } else {
            [body appendFormat:@"<div class=\"no-diff\">%@</div>",
                                 GHCommitL(@"Бинарный файл или diff слишком большой для отображения.", @"Binary file or diff too large to display.")];
        }

        [body appendString:@"</div></div>"];
        fileIndex++;
    }

    [body appendString:@"</div>"];

    [body appendString:@"<div id=\"tab-details\" style=\"display:none;\">"];
    [body appendFormat:@"<div class=\"detail-section\"><div class=\"detail-label\">%@</div>"
                         "<div class=\"detail-row\"><a class=\"copy-link\" href=\"ghlegacy-copy://sha\" ontouchend=\"copyTouched(this)\">%@</a>"
                         "<span class=\"commit-icon\"></span><span class=\"mono\">%@</span></div></div>",
                         GHCommitL(@"Коммит", @"Commit"), GHCommitL(@"КОПИРОВАТЬ", @"COPY"), [self escapeHTML:shortSHA]];

    [body appendFormat:@"<div class=\"detail-section\"><div class=\"detail-label\">%@</div>", GHCommitL(@"Участники", @"Contributors")];
    [body appendString:[self personRowHTMLWithLogin:authorLogin name:authorName avatarURL:authorAvatar]];
    NSString *committerLogin = [self safeStringForKey:@"login" inDict:ghCommitter];
    NSString *committerName = [self safeStringForKey:@"name" inDict:committerData];
    BOOL sameCommitter = (committerLogin.length > 0 && [committerLogin isEqualToString:authorLogin])
                      || (committerLogin.length == 0 && [committerName isEqualToString:authorName]);
    if (!sameCommitter && ![committerLogin isEqualToString:@"web-flow"] && (committerLogin.length > 0 || committerName.length > 0)) {
        [body appendString:[self personRowHTMLWithLogin:committerLogin name:committerName
                                               avatarURL:[self safeStringForKey:@"avatar_url" inDict:ghCommitter]]];
    }
    [body appendString:@"</div>"];

    if (parents.count > 0) {
        [body appendFormat:@"<div class=\"detail-section\"><div class=\"detail-label\">%@</div>", GHCommitL(@"Родители", @"Parents")];
        for (NSDictionary *parent in parents) {
            if (![parent isKindOfClass:[NSDictionary class]]) continue;
            NSString *psha = [self safeStringForKey:@"sha" inDict:parent];
            if (psha.length == 0) continue;
            NSString *pshort = psha.length >= 7 ? [psha substringToIndex:7] : psha;
            [body appendFormat:@"<a class=\"detail-row\" href=\"https://github.com/%@/%@/commit/%@\"><span class=\"commit-icon\"></span><span class=\"mono\">%@</span></a>",
                                 self.ownerLogin, self.repoName, psha, pshort];
        }
        [body appendString:@"</div>"];
    }
    [body appendString:@"</div>"];

    NSString *css =
        @"html,body{-webkit-text-size-adjust:100%;-webkit-overflow-scrolling:touch;}"
        "body{font-family:-apple-system,Helvetica;font-size:14px;color:#000;margin:0;padding:0;background:#fff;}"
        "a{color:inherit;text-decoration:none;}"
        ".tabs{display:table;width:100%;table-layout:fixed;border-bottom:1px solid #ddd;}"
        ".tab{display:table-cell;text-align:center;padding:13px 0 11px 0;font-size:14px;font-weight:bold;color:#666;border-bottom:3px solid transparent;cursor:pointer;}"
        ".tab.active{color:#000;border-bottom-color:#0969da;}"
        ".avatar{display:inline-block;border-radius:50%;background:#ddd;vertical-align:middle;}"
        ".commit-header{padding:14px 16px 16px 16px;}"
        ".author-row{font-size:15px;line-height:26px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;}"
        ".author-row .avatar{margin-right:8px;}"
        ".author-name{font-weight:bold;}"
        ".author-verb{color:#666;}"
        ".author-date{float:right;color:#666;margin-left:8px;}"
        ".commit-title{font-size:17px;font-weight:bold;margin-top:10px;word-wrap:break-word;}"
        ".commit-body{white-space:pre-wrap;word-wrap:break-word;font-family:Menlo,monospace;font-size:13px;line-height:1.5;margin:6px 0 0 0;}"
        ".gap{height:10px;background:#f0f1f3;border-top:1px solid #ddd;border-bottom:1px solid #ddd;}"
        ".summary{padding:12px 16px;}"
        ".summary-title{font-size:17px;font-weight:bold;}"
        ".summary-stats{font-size:15px;margin-top:3px;}"
        ".sum-add{color:#1a7f37;}"
        ".sum-del{color:#cf222e;}"
        ".detail-section{border-bottom:1px solid #ddd;padding:6px 0;}"
        ".detail-label{color:#666;font-size:14px;padding:10px 16px 4px 16px;}"
        ".detail-row{display:block;padding:10px 16px;font-size:16px;overflow:hidden;line-height:24px;}"
        ".detail-row.person{line-height:40px;}"
        ".detail-row .avatar{margin-right:12px;}"
        ".mono{font-family:Menlo,monospace;font-size:15px;}"
        ".commit-icon{display:inline-block;width:6px;height:6px;border:2px solid #666;border-radius:6px;margin:0 16px 0 4px;vertical-align:middle;position:relative;}"
        ".commit-icon:before,.commit-icon:after{content:'';position:absolute;top:2px;width:6px;height:2px;background:#666;}"
        ".commit-icon:before{left:-8px;}"
        ".commit-icon:after{right:-8px;}"
        ".copy-link{float:right;color:#0969da;font-weight:bold;font-size:14px;}"

        ".file-section{position:relative;}"

        ".file-header{background:#f6f8fa;height:44px;-webkit-box-sizing:border-box;box-sizing:border-box;overflow:hidden;padding:4px 12px 4px 30px;font-weight:bold;font-size:13px;border-top:1px solid #ddd;border-bottom:1px solid #ddd;cursor:pointer;"
        "position:-webkit-sticky;position:sticky;top:0;z-index:5;}"
        ".file-header:active{background:#eaeef1;}"
        ".toggle-icon{position:absolute;left:13px;top:12px;width:7px;height:7px;border-right:2px solid #6a737d;border-bottom:2px solid #6a737d;"
        "-webkit-transform:rotate(45deg);transform:rotate(45deg);"
        "-webkit-transition:-webkit-transform 0.25s ease;transition:transform 0.25s ease;}"
        ".file-name{font-family:Menlo,monospace;font-size:13px;line-height:18px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-right:96px;}"
        ".file-status{display:block;font-family:-apple-system,Helvetica;font-weight:normal;font-size:12px;line-height:16px;color:#666;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;}"
        ".st-dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:5px;vertical-align:middle;background:#bf8700;}"
        ".st-dot.st-add{background:#1a7f37;}"
        ".st-dot.st-del{background:#cf222e;}"
        ".file-stats{position:absolute;right:12px;top:0;line-height:42px;font-weight:normal;font-size:13px;white-space:nowrap;}"
        ".stat-add{color:#22863a;}"
        ".stat-del{color:#cb2431;}"

        ".file-content{opacity:1;}"

        ".diff-block{position:relative;overflow:hidden;font-family:Menlo,monospace;font-size:12px;line-height:1.6;border-top:1px solid #eee;}"
        ".diff-gutter{position:absolute;left:0;top:0;width:77px;"
        "-webkit-box-sizing:border-box;box-sizing:border-box;"
        "background:#f6f8fa;color:#999;text-align:right;border-right:1px solid #eee;"
        "-webkit-text-size-adjust:100%;}"
        ".diff-gutter .ln-row{padding:1px 4px;white-space:nowrap;}"
        ".diff-gutter .ln-old,.diff-gutter .ln-new{display:inline-block;width:34px;text-align:right;vertical-align:top;}"

        ".diff-code{margin-left:77px;overflow-x:auto;overflow-y:hidden;"
        "-webkit-overflow-scrolling:touch;-webkit-text-size-adjust:100%;}"

        ".diff-table{border-collapse:collapse;width:auto;min-width:100%;}"
        ".diff-table td.code-cell{white-space:pre;padding:1px 8px;}"
        ".diff-add{background:#e6ffed;color:#22863a;}"
        ".diff-del{background:#ffeef0;color:#b31d28;}"
        ".diff-hunk{background:#f1f8ff;color:#005cc5;}"
        ".diff-ctx{color:#333;}"
        ".no-diff,.no-files{padding:10px 12px;color:#666;font-size:13px;}"
        ".image-preview{padding:12px;text-align:center;background:#f6f8fa;}"
        ".image-preview img{max-width:100%;max-height:280px;height:auto;border:1px solid #ddd;border-radius:4px;background:#fff;}"
        ".show-more{padding:10px 12px;text-align:center;color:#0366d6;font-size:13px;font-weight:bold;background:#f6f8fa;border-top:1px solid #eee;border-bottom:1px solid #ddd;cursor:pointer;}"
        ".show-more:active{background:#eaeef1;}";

    if ([self gh_needsNativeStickyHeader]) {
        css = [css stringByReplacingOccurrencesOfString:
            @"html,body{-webkit-text-size-adjust:100%;-webkit-overflow-scrolling:touch;}"
                                              withString:
            @"html,body{-webkit-text-size-adjust:100%;}"];
    }

    if ([GHThemeManager sharedManager].darkModeEnabled) {
        NSString *darkOverride =
            @"body{background:#121212;color:#e6e6e6;}"
            ".tabs{border-bottom-color:#2a2a2a;}"
            ".tab{color:#999;}"
            ".tab.active{color:#fff;border-bottom-color:#4493f8;}"
            ".avatar{background:#333;}"
            ".author-verb,.author-date{color:#999;}"
            ".gap{background:#000;border-color:#2a2a2a;}"
            ".sum-add{color:#3fb950;}"
            ".sum-del{color:#f85149;}"
            ".detail-section{border-bottom-color:#2a2a2a;}"
            ".detail-label{color:#999;}"
            ".commit-icon{border-color:#999;}"
            ".commit-icon:before,.commit-icon:after{background:#999;}"
            ".copy-link{color:#4493f8;}"
            ".file-header{background:#1c1c1c;border-top-color:#333;border-bottom-color:#333;}"
            ".file-header:active{background:#262626;}"
            ".toggle-icon{border-right-color:#8b949e;border-bottom-color:#8b949e;}"
            ".file-status{color:#999;}"
            ".diff-gutter{background:#1c1c1c;color:#6e7681;border-right-color:#2a2a2a;}"
            ".diff-add{background:rgba(46,160,67,0.18);color:#56d364;}"
            ".diff-del{background:rgba(248,81,73,0.18);color:#ff7b72;}"
            ".diff-hunk{background:rgba(56,139,253,0.15);color:#58a6ff;}"
            ".diff-ctx{color:#c9d1d9;}"
            ".no-diff,.no-files{color:#999;}"
            ".image-preview{background:#1c1c1c;}"
            ".image-preview img{border-color:#333;background:#1c1c1c;}"
            ".show-more{color:#58a6ff;background:#1c1c1c;border-top-color:#2a2a2a;border-bottom-color:#333;}"
            ".show-more:active{background:#262626;}";
        css = [css stringByAppendingString:darkOverride];
    }

    NSString *js =
        @"var _touchStartX=0,_touchStartY=0;"
        "function fileTouchStart(e){"
        "var t=e.touches[0];"
        "_touchStartX=t.clientX;"
        "_touchStartY=t.clientY;"
        "}"

        "function didMoveTooMuch(e){"
        "var t=e.changedTouches[0];"
        "var dx=Math.abs(t.clientX-_touchStartX);"
        "var dy=Math.abs(t.clientY-_touchStartY);"
        "return dx>10||dy>10;"
        "}"
        "function moreTouchEnd(e,n){"
        "if(didMoveTooMuch(e))return;"
        "revealNextChunk(n);"
        "}"
        "function revealNextChunk(n){"
        "var btn=document.getElementById('show-more-'+n);"
        "if(!btn)return;"
        "var shown=parseInt(btn.getAttribute('data-shown'),10)||0;"
        "var total=parseInt(btn.getAttribute('data-total'),10)||0;"
        "var chunkIndex=shown+1;"
        "var g=document.getElementById('gutter-chunk-'+n+'-'+chunkIndex);"
        "var c=document.getElementById('code-chunk-'+n+'-'+chunkIndex);"
        "if(g)g.style.display='';"
        "if(c)c.style.display='';"
        "shown++;"
        "btn.setAttribute('data-shown',shown);"
        "if(shown>=total){"
        "btn.style.display='none';"
        "}else{"
        "var labels=btn.getAttribute('data-labels').split('|');"
        "if(labels[shown])btn.innerHTML=labels[shown];"
        "}"
        "notifyLayoutChanged();"
        "}"
        "function fileTouchEnd(e,n){"
        "if(didMoveTooMuch(e))return;"
        "toggleFile(n);"
        "}"
        "function toggleFile(n){"
        "var content=document.getElementById('file-content-'+n);"
        "var icon=document.getElementById('toggle-'+n);"
        "if(!content||!icon)return;"
        "var isHidden=content.style.display==='none';"
        "if(isHidden){"
        "content.style.display='';"
        "void content.offsetHeight;"
        "icon.style.webkitTransform='rotate(45deg)';"
        "icon.style.transform='rotate(45deg)';"
        "}else{"
        "icon.style.webkitTransform='rotate(-45deg)';"
        "icon.style.transform='rotate(-45deg)';"
        "content.style.display='none';"
        "void document.body.offsetHeight;"
        "}"
        "notifyLayoutChanged();"
        "}"
        "function notifyLayoutChanged(){"
        "var f=document.getElementById('gh-layout-ping');"
        "if(!f){f=document.createElement('iframe');f.id='gh-layout-ping';"
        "f.style.display='none';document.body.appendChild(f);}"
        "f.src='ghlegacy-layout://changed?t='+new Date().getTime();"
        "}"

        "function tabTouchEnd(e,name){"
        "if(didMoveTooMuch(e))return;"
        "showTab(name);"
        "}"
        "function showTab(name){"
        "var tabs=['changes','details'];"
        "for(var i=0;i<tabs.length;i++){"
        "var on=tabs[i]===name;"
        "document.getElementById('tab-'+tabs[i]).style.display=on?'':'none';"
        "document.getElementById('tab-btn-'+tabs[i]).className=on?'tab active':'tab';"
        "}"
        "notifyLayoutChanged();"
        "}"
        "function copyTouched(el){"
        "var old=el.getAttribute('data-label')||el.innerHTML;"
        "el.setAttribute('data-label',old);"
        "el.innerHTML='\u2713';"
        "setTimeout(function(){el.innerHTML=old;},1200);"
        "}"
        "function ghSetStickyDomIndex(i){"
        "var hs=document.getElementsByClassName('file-header');"
        "for(var j=0;j<hs.length;j++){"
        "hs[j].style.visibility=(j===i)?'hidden':'visible';"
        "}"
        "}";

    return [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head>"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>"
        "<style>%@</style>"
        "<script>%@</script>"
        "</head><body>%@</body></html>",
        css, [js stringByAppendingString:[GHMarkdownRenderer legacyOverflowScrollScript]], body];
}

@end
