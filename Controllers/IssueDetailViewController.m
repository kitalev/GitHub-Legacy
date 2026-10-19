#import "IssueDetailViewController.h"
#import "GHCompat.h"
#import "AppDelegate.h"
#import "GHThemeManager.h"
#import "GHAPIClient.h"
#import "GHMarkdownRenderer.h"
#import "GHLocalization.h"
#import "GHTimelineRenderer.h"
#import "CommitDetailViewController.h"
#import "IssueListViewController.h"
#import "RepoDetailViewController.h"
#import "RepoOverviewViewController.h"

@interface IssueDetailViewController ()
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, copy) NSString *lastLoadedHTML;
@property (nonatomic, assign) NSUInteger renderGeneration;
@end

@implementation IssueDetailViewController

+ (void)pushIssueNumber:(NSInteger)number
              ownerLogin:(NSString *)ownerLogin
                repoName:(NSString *)repoName
      fromViewController:(UIViewController *)fromViewController {
    __weak UIViewController *weakFromVC = fromViewController;
    [[GHAPIClient sharedClient] issueForOwner:ownerLogin
                                          repo:repoName
                                        number:number
                                    completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        if (![jsonObject isKindOfClass:[NSDictionary class]]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription ?: GHL(@"Не удалось загрузить issue.")
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        IssueDetailViewController *detailVC = [[IssueDetailViewController alloc] init];
        detailVC.issue = jsonObject;
        detailVC.ownerLogin = ownerLogin;
        detailVC.repoName = repoName;
        [strongFromVC.navigationController pushViewController:detailVC animated:YES];
    }];
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

- (NSURL *)contentBaseURL {
    if (self.ownerLogin.length == 0 || self.repoName.length == 0) return nil;
    NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@/issues/", self.ownerLogin, self.repoName];
    return [NSURL URLWithString:urlString];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = GHBackgroundColor();

    NSNumber *number = [self safeNumberForKey:@"number" inDict:self.issue];
    self.title = [NSString stringWithFormat:@"Issue #%@", number];

    [self installWebView];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppDidEnterBackground)
                                                  name:kGHAppDidEnterBackgroundNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleAppWillEnterForeground)
                                                  name:kGHAppWillEnterForegroundNotification
                                                object:nil];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.center = self.view.center;
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                     UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.spinner];
    [self.spinner startAnimating];

    if (self.ownerLogin.length > 0 && self.repoName.length > 0) {
        [self loadCommentsThenRender];
    } else {
        [self renderWithTimeline:nil loadError:nil];
    }
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
    [self.view addSubview:self.webView];

    if (self.refreshControl == nil) {

        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];
    }
    if (self.refreshControl != nil) {
        [self.webView.scrollView addSubview:self.refreshControl];
    }
}

- (void)destroyWebView {
    if (self.webView == nil) return;
    self.webView.delegate = nil;
    [self.webView stopLoading];
    [self.webView loadHTMLString:@"" baseURL:nil];
    [self.refreshControl removeFromSuperview];
    [self.webView removeFromSuperview];
    self.webView = nil;
}

- (void)handleAppDidEnterBackground {
    if (self.lastLoadedHTML.length == 0) return;
    [self destroyWebView];
}

- (void)handleAppWillEnterForeground {
    if (self.lastLoadedHTML.length == 0) return;

    [self installWebView];
    [self.webView loadHTMLString:self.lastLoadedHTML baseURL:[self contentBaseURL]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handlePullToRefresh {
    NSNumber *number = [self safeNumberForKey:@"number" inDict:self.issue];
    if (number.integerValue == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) {
        [self.refreshControl endRefreshing];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] issueForOwner:self.ownerLogin
                                          repo:self.repoName
                                        number:number.integerValue
                                    completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if ([jsonObject isKindOfClass:[NSDictionary class]]) {
            strongSelf.issue = jsonObject;
            NSNumber *refreshedNumber = [strongSelf safeNumberForKey:@"number" inDict:strongSelf.issue];
            strongSelf.title = [NSString stringWithFormat:@"Issue #%@", refreshedNumber];
        }

        if (strongSelf.ownerLogin.length > 0 && strongSelf.repoName.length > 0) {
            [strongSelf loadCommentsThenRender];
        } else {
            [strongSelf renderWithTimeline:nil loadError:nil];
        }
    }];
}

- (NSString *)buildHTMLWithTimeline:(NSArray *)timeline loadError:(NSString *)loadError {
    GHTimelineRenderer *renderer = [[GHTimelineRenderer alloc] initWithOwnerLogin:self.ownerLogin repoName:self.repoName];

    NSString *state = [self safeStringForKey:@"state" inDict:self.issue];
    NSString *stateReason = [self safeStringForKey:@"state_reason" inDict:self.issue];

    NSString *stateLabel;
    NSString *stateColor;
    if ([state isEqualToString:@"open"]) {
        stateLabel = GHL(@"● Открыта");
        stateColor = @"#1f883d";
    } else if ([stateReason isEqualToString:@"not_planned"] || [stateReason isEqualToString:@"duplicate"]) {
        stateLabel = GHL(@"⊘ Закрыта");
        stateColor = @"#59636e";
    } else {
        stateLabel = GHL(@"✓ Закрыта");
        stateColor = @"#8250df";
    }

    NSMutableString *html = [NSMutableString stringWithString:[renderer styleCSS]];
    [html appendString:[renderer repoLineHTMLWithNumber:[self safeNumberForKey:@"number" inDict:self.issue]]];
    [html appendString:[renderer titleHTML:[self safeStringForKey:@"title" inDict:self.issue]]];
    [html appendString:[renderer stateRowHTMLWithLabel:stateLabel color:stateColor extraHTML:[renderer labelsHTML:self.issue[@"labels"]]]];
    [html appendString:[renderer postHTMLWithUser:[self safeDictForKey:@"user" inDict:self.issue]
                                         createdAt:[self safeStringForKey:@"created_at" inDict:self.issue]
                                       association:[self safeStringForKey:@"author_association" inDict:self.issue]
                                              body:[self safeStringForKey:@"body" inDict:self.issue]]];

    for (NSDictionary *item in timeline) {
        [html appendString:[renderer timelineItemHTML:item]];
    }
    [html appendString:[renderer errorHTML:loadError]];

    return [GHMarkdownRenderer htmlDocumentWrappingBody:html];
}

- (void)renderWithTimeline:(NSArray *)timeline loadError:(NSString *)loadError {
    NSUInteger generation = ++self.renderGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *html = [strongSelf buildHTMLWithTimeline:timeline loadError:loadError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf.renderGeneration != generation) return;
            strongSelf.lastLoadedHTML = html;
            [strongSelf.webView loadHTMLString:html baseURL:[strongSelf contentBaseURL]];
            [strongSelf.refreshControl endRefreshing];
        });
    });
}

- (void)loadCommentsThenRender {
    NSNumber *number = [self safeNumberForKey:@"number" inDict:self.issue];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] timelineForOwner:self.ownerLogin
                                              repo:self.repoName
                                            number:number.integerValue
                                        completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if ([jsonObject isKindOfClass:[NSArray class]]) {
            [strongSelf renderWithTimeline:jsonObject loadError:nil];
            return;
        }

        [[GHAPIClient sharedClient] commentsForOwner:strongSelf.ownerLogin
                                                  repo:strongSelf.repoName
                                                number:number.integerValue
                                            completion:^(id commentsObject, NSError *commentsError) {
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (!innerSelf) return;
            NSArray *comments = [commentsObject isKindOfClass:[NSArray class]] ? commentsObject : nil;
            NSString *errorText = comments ? nil : GHL(@"Не удалось загрузить комментарии.");
            [innerSelf renderWithTimeline:comments loadError:errorText];
        }];
    }];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.spinner stopAnimating];
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
    return YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        self.webView.delegate = nil;
        [self.webView stopLoading];
        [self.webView loadHTMLString:@"" baseURL:nil];
    }
}

@end
