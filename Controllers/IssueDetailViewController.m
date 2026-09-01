#import "IssueDetailViewController.h"
#import "AppDelegate.h"
#import "GHThemeManager.h"
#import "GHAPIClient.h"
#import "GHMarkdownRenderer.h"
#import "GHLocalization.h"
#import "CommitDetailViewController.h"
#import "IssueListViewController.h"
#import "RepoDetailViewController.h"
#import "RepoOverviewViewController.h"

@interface IssueDetailViewController ()
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIRefreshControl *refreshControl;

@property (nonatomic, copy) NSString *lastLoadedHTML;
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

- (NSString *)displayDateFromISOString:(NSString *)isoString {
    if (isoString.length == 0) return nil;

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return nil;

    NSDateFormatter *displayFormatter = [[NSDateFormatter alloc] init];
    displayFormatter.dateStyle = NSDateFormatterMediumStyle;
    displayFormatter.timeStyle = NSDateFormatterShortStyle;
    return [displayFormatter stringFromDate:date];
}

- (NSURL *)contentBaseURL {
    if (self.ownerLogin.length == 0 || self.repoName.length == 0) return nil;
    NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@/issues/", self.ownerLogin, self.repoName];
    return [NSURL URLWithString:urlString];
}

- (UIColor *)readableTextColorOverHexBackground:(NSString *)hex {
    if (hex.length != 6) return [UIColor blackColor];

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&value]) return [UIColor blackColor];

    CGFloat r = ((value >> 16) & 0xFF) / 255.0;
    CGFloat g = ((value >> 8) & 0xFF) / 255.0;
    CGFloat b = (value & 0xFF) / 255.0;
    CGFloat luma = (0.299 * r) + (0.587 * g) + (0.114 * b);
    return luma > 0.6 ? [UIColor blackColor] : [UIColor whiteColor];
}

- (NSString *)hexStringFromColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
        (long)round(r * 255), (long)round(g * 255), (long)round(b * 255)];
}

- (NSString *)issueLabelsHTML {
    NSArray *labels = [self.issue[@"labels"] isKindOfClass:[NSArray class]] ? self.issue[@"labels"] : nil;
    if (labels.count == 0) return @"";

    NSMutableString *html = [NSMutableString stringWithString:@"<span class=\"issue-labels\">"];
    for (NSDictionary *label in labels) {
        if (![label isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = [self safeStringForKey:@"name" inDict:label];
        if (name.length == 0) continue;
        NSString *colorHex = [self safeStringForKey:@"color" inDict:label] ?: @"ededed";

        if (![self isValidHexColor:colorHex]) colorHex = @"ededed";
        UIColor *textColor = [self readableTextColorOverHexBackground:colorHex];
        [html appendFormat:
            @"<span class=\"issue-label\" style=\"background:#%@;color:%@;\">%@</span>",
            colorHex, [self hexStringFromColor:textColor], [GHMarkdownRenderer escapeHTML:name]];
    }
    [html appendString:@"</span>"];
    return html;
}

- (BOOL)isValidHexColor:(NSString *)hex {
    if (hex.length != 6) return NO;
    static NSCharacterSet *nonHex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *hexSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        nonHex = [hexSet invertedSet];
    });
    return [hex rangeOfCharacterFromSet:nonHex].location == NSNotFound;
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

    NSNumber *commentsCount = [self safeNumberForKey:@"comments" inDict:self.issue];
    if (commentsCount.integerValue > 0 && self.ownerLogin.length > 0 && self.repoName.length > 0) {
        [self loadCommentsThenRender];
    } else {
        self.lastLoadedHTML = [self buildHTMLWithComments:nil commentsError:nil];
        [self.webView loadHTMLString:self.lastLoadedHTML baseURL:[self contentBaseURL]];
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
    [self.webView.scrollView addSubview:self.refreshControl];
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

        NSNumber *commentsCount = [strongSelf safeNumberForKey:@"comments" inDict:strongSelf.issue];
        if (commentsCount.integerValue > 0 && strongSelf.ownerLogin.length > 0 && strongSelf.repoName.length > 0) {
            [strongSelf loadCommentsThenRender];
        } else {
            strongSelf.lastLoadedHTML = [strongSelf buildHTMLWithComments:nil commentsError:nil];
            [strongSelf.webView loadHTMLString:strongSelf.lastLoadedHTML baseURL:[strongSelf contentBaseURL]];
            [strongSelf.refreshControl endRefreshing];
        }
    }];
}

- (void)loadCommentsThenRender {
    NSNumber *number = [self safeNumberForKey:@"number" inDict:self.issue];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] commentsForOwner:self.ownerLogin
                                              repo:self.repoName
                                            number:number.integerValue
                                        completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSArray *comments = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : nil;
        NSString *errorText = (!comments && error) ? GHL(@"Не удалось загрузить комментарии.") : nil;
        strongSelf.lastLoadedHTML = [strongSelf buildHTMLWithComments:comments commentsError:errorText];
        [strongSelf.webView loadHTMLString:strongSelf.lastLoadedHTML baseURL:[strongSelf contentBaseURL]];

        [strongSelf.refreshControl endRefreshing];
    }];
}

- (NSString *)buildHTMLWithComments:(NSArray *)comments commentsError:(NSString *)commentsError {
    NSString *title = [self safeStringForKey:@"title" inDict:self.issue];
    NSString *state = [self safeStringForKey:@"state" inDict:self.issue];
    NSString *body = [self safeStringForKey:@"body" inDict:self.issue];
    NSDictionary *user = [self safeDictForKey:@"user" inDict:self.issue];
    NSString *authorLogin = [self safeStringForKey:@"login" inDict:user];
    NSString *authorAvatarURL = [self safeStringForKey:@"avatar_url" inDict:user];
    NSString *createdAt = [self displayDateFromISOString:[self safeStringForKey:@"created_at" inDict:self.issue]];
    NSNumber *commentsCount = [self safeNumberForKey:@"comments" inDict:self.issue];

    BOOL isOpen = [state isEqualToString:@"open"];
    NSString *stateReason = [self safeStringForKey:@"state_reason" inDict:self.issue];

    NSString *stateLabel;
    NSString *stateColor;
    if (isOpen) {
        stateLabel = GHL(@"● Открыт");
        stateColor = @"#28a745";
    } else if ([stateReason isEqualToString:@"not_planned"]) {
        stateLabel = GHL(@"⊘ Закрыт: не планируется");
        stateColor = @"#6a737d";
    } else if ([stateReason isEqualToString:@"duplicate"]) {
        stateLabel = GHL(@"⊘ Закрыт как дубликат");
        stateColor = @"#6a737d";
    } else {
        stateLabel = GHL(@"✓ Закрыт");
        stateColor = @"#6f42c1";
    }

    NSMutableString *meta = [NSMutableString string];
    if (authorAvatarURL.length > 0) {
        [meta appendFormat:@"<img class=\"avatar\" src=\"%@\"/>", [GHMarkdownRenderer escapeHTMLAttribute:authorAvatarURL]];
    }
    if (authorLogin.length > 0) [meta appendString:[GHMarkdownRenderer escapeHTML:authorLogin]];
    if (createdAt.length > 0) {
        if (meta.length > 0) [meta appendString:@" · "];
        [meta appendString:[GHMarkdownRenderer escapeHTML:createdAt]];
    }
    if (commentsCount.integerValue > 0) {
        if (meta.length > 0) [meta appendString:@" · "];
        [meta appendFormat:@"💬 %@", commentsCount];
    }

    NSString *bodyHTML = body.length > 0
        ? [GHMarkdownRenderer bodyHTMLFromMarkdown:body repoOwner:self.ownerLogin repoName:self.repoName]
        : @"<p style=\"color:#888;\">Без описания.</p>";

    NSString *header = [NSString stringWithFormat:
        @"<div class=\"issue-header\">"
         "<div class=\"issue-state\" style=\"color:%@;\">%@</div>"
         "<h1 class=\"issue-title\">%@%@</h1>"
         "<div class=\"issue-meta\">%@</div>"
         "</div><hr/>",
        stateColor, stateLabel, [GHMarkdownRenderer escapeHTML:title ?: @""], [self issueLabelsHTML], meta];

    return [GHMarkdownRenderer htmlDocumentWrappingBody:
        [[header stringByAppendingString:bodyHTML] stringByAppendingString:[self commentsHTML:comments error:commentsError]]];
}

- (NSString *)commentsHTML:(NSArray *)comments error:(NSString *)errorText {
    if (errorText.length > 0) {
        return [NSString stringWithFormat:
            @"<div class=\"comments-error\">%@</div>", [GHMarkdownRenderer escapeHTML:errorText]];
    }
    if (comments.count == 0) return @"";

    NSMutableString *html = [NSMutableString stringWithFormat:
        @"<div class=\"comments-heading\">Комментарии (%lu)</div>", (unsigned long)comments.count];

    for (NSDictionary *comment in comments) {
        if (![comment isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *commentUser = [self safeDictForKey:@"user" inDict:comment];
        NSString *login = [self safeStringForKey:@"login" inDict:commentUser];
        NSString *avatarURL = [self safeStringForKey:@"avatar_url" inDict:commentUser];
        NSString *createdAt = [self displayDateFromISOString:[self safeStringForKey:@"created_at" inDict:comment]];
        NSString *commentBody = [self safeStringForKey:@"body" inDict:comment];

        NSMutableString *commentMeta = [NSMutableString string];
        if (avatarURL.length > 0) {
            [commentMeta appendFormat:@"<img class=\"avatar\" src=\"%@\"/>", [GHMarkdownRenderer escapeHTMLAttribute:avatarURL]];
        }
        if (login.length > 0) [commentMeta appendString:[GHMarkdownRenderer escapeHTML:login]];
        if (createdAt.length > 0) {
            if (commentMeta.length > 0) [commentMeta appendString:@" · "];
            [commentMeta appendString:[GHMarkdownRenderer escapeHTML:createdAt]];
        }

        NSString *commentBodyHTML = commentBody.length > 0
            ? [GHMarkdownRenderer bodyHTMLFromMarkdown:commentBody repoOwner:self.ownerLogin repoName:self.repoName]
            : @"<p style=\"color:#888;\">Без текста.</p>";

        [html appendFormat:
            @"<div class=\"comment\">"
             "<div class=\"comment-meta\">%@</div>"
             "<div class=\"comment-body\">%@</div>"
             "</div>",
            commentMeta, commentBodyHTML];
    }
    return html;
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
