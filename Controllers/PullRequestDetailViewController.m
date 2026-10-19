#import "PullRequestDetailViewController.h"
#import "GHCompat.h"
#import "AppDelegate.h"
#import "GHThemeManager.h"
#import "GHAPIClient.h"
#import "GHMarkdownRenderer.h"
#import "GHIconRenderer.h"
#import "GHLocalization.h"
#import "GHTimelineRenderer.h"
#import "CommitDetailViewController.h"
#import "IssueDetailViewController.h"
#import "IssueListViewController.h"
#import "RepoDetailViewController.h"
#import "RepoOverviewViewController.h"

@interface PullRequestDetailViewController ()
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@property (nonatomic, copy) NSString *lastLoadedHTML;
@property (nonatomic, assign) NSUInteger renderGeneration;
@end

@implementation PullRequestDetailViewController

+ (BOOL)pullRequestNumberFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName
                           number:(NSInteger *)number {
    if (url == nil) return NO;
    static NSRegularExpression *regex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/pull/([0-9]+)"
                                                            options:NSRegularExpressionCaseInsensitive
                                                              error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    if (number != NULL) *number = [[urlString substringWithRange:[match rangeAtIndex:3]] integerValue];
    return YES;
}

+ (void)pushPullRequestNumber:(NSInteger)number
                   ownerLogin:(NSString *)ownerLogin
                     repoName:(NSString *)repoName
          fromViewController:(UIViewController *)fromViewController {
    __weak UIViewController *weakFromVC = fromViewController;
    [[GHAPIClient sharedClient] pullRequestForOwner:ownerLogin
                                                repo:repoName
                                              number:number
                                          completion:^(id jsonObject, NSError *error) {
        __strong UIViewController *strongFromVC = weakFromVC;
        if (!strongFromVC) return;

        if (![jsonObject isKindOfClass:[NSDictionary class]]) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription ?: GHL(@"Не удалось загрузить pull request.")
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        PullRequestDetailViewController *detailVC = [[PullRequestDetailViewController alloc] init];
        detailVC.pullRequest = jsonObject;
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

- (BOOL)isMerged {
    id mergedAt = self.pullRequest[@"merged_at"];
    return mergedAt != nil && ![mergedAt isKindOfClass:[NSNull class]];
}

- (NSURL *)contentBaseURL {
    if (self.ownerLogin.length == 0 || self.repoName.length == 0) return nil;
    NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@/pull/", self.ownerLogin, self.repoName];
    return [NSURL URLWithString:urlString];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = GHBackgroundColor();

    NSNumber *number = [self safeNumberForKey:@"number" inDict:self.pullRequest];
    self.title = [NSString stringWithFormat:@"PR #%@", number];

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
        [self loadDetailsThenRender];
    } else {
        [self renderWithTimeline:nil checkRuns:nil loadError:nil];
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
}

- (void)destroyWebView {
    if (self.webView == nil) return;
    self.webView.delegate = nil;
    [self.webView stopLoading];
    [self.webView loadHTMLString:@"" baseURL:nil];
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

- (NSString *)pluralForCount:(NSInteger)count ruOne:(NSString *)ruOne ruFew:(NSString *)ruFew ruMany:(NSString *)ruMany
                       enOne:(NSString *)enOne enMany:(NSString *)enMany {
    if (![[GHLocalization sharedManager].languageCode isEqualToString:@"ru"]) {
        return count == 1 ? enOne : enMany;
    }
    NSInteger mod10 = count % 10;
    NSInteger mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return ruOne;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return ruFew;
    return ruMany;
}

- (BOOL)isDraft {
    id draft = self.pullRequest[@"draft"];
    return [draft respondsToSelector:@selector(boolValue)] && [draft boolValue];
}

- (NSString *)reviewsRowHTMLWithRenderer:(GHTimelineRenderer *)renderer timeline:(NSArray *)timeline {
    NSMutableDictionary *latestByUser = [NSMutableDictionary dictionary];
    for (NSDictionary *item in timeline) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if (![[self safeStringForKey:@"event" inDict:item] isEqualToString:@"reviewed"]) continue;
        NSString *state = [[self safeStringForKey:@"state" inDict:item] lowercaseString];
        NSString *login = [self safeStringForKey:@"login" inDict:[self safeDictForKey:@"user" inDict:item]];
        if (login.length == 0 || state.length == 0) continue;
        if ([state isEqualToString:@"commented"]) continue;
        [latestByUser setObject:state forKey:login];
    }

    NSInteger approvals = 0;
    NSInteger changes = 0;
    for (NSString *state in latestByUser.allValues) {
        if ([state isEqualToString:@"approved"]) approvals++;
        if ([state isEqualToString:@"changes_requested"]) changes++;
    }

    if (changes > 0) {
        return [renderer rowHTMLWithGlyph:@"±" glyphColor:@"#fff" glyphBackground:@"#cf222e"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Запрошены изменения")]
                             subtitleHTML:nil trailingHTML:nil];
    }
    if (approvals > 0) {
        NSString *subtitle = [NSString stringWithFormat:@"%ld %@", (long)approvals,
            [self pluralForCount:approvals ruOne:@"одобрение" ruFew:@"одобрения" ruMany:@"одобрений" enOne:@"approval" enMany:@"approvals"]];
        return [renderer rowHTMLWithGlyph:@"✓" glyphColor:@"#fff" glyphBackground:@"#1f883d"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Изменения одобрены")]
                             subtitleHTML:[GHMarkdownRenderer escapeHTML:subtitle] trailingHTML:nil];
    }
    return [renderer rowHTMLWithGlyph:@"○" glyphColor:nil glyphBackground:nil
                            titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Ревью")]
                         subtitleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Пока никто не оставил отзыв")] trailingHTML:nil];
}

- (NSString *)checksRowHTMLWithRenderer:(GHTimelineRenderer *)renderer checkRuns:(NSDictionary *)checkRuns {
    NSArray *runs = [checkRuns[@"check_runs"] isKindOfClass:[NSArray class]] ? checkRuns[@"check_runs"] : nil;
    if (runs.count == 0) return @"";

    NSInteger failed = 0, pending = 0, passed = 0;
    NSSet *failing = [NSSet setWithObjects:@"failure", @"timed_out", @"cancelled", @"action_required", @"startup_failure", nil];
    for (NSDictionary *run in runs) {
        if (![run isKindOfClass:[NSDictionary class]]) continue;
        NSString *status = [self safeStringForKey:@"status" inDict:run];
        NSString *conclusion = [self safeStringForKey:@"conclusion" inDict:run];
        if (![status isEqualToString:@"completed"]) pending++;
        else if ([failing containsObject:conclusion]) failed++;
        else passed++;
    }

    NSMutableArray *parts = [NSMutableArray array];
    if (passed > 0) [parts addObject:[NSString stringWithFormat:GHL(@"%ld успешно"), (long)passed]];
    if (failed > 0) [parts addObject:[NSString stringWithFormat:GHL(@"%ld с ошибкой"), (long)failed]];
    if (pending > 0) [parts addObject:[NSString stringWithFormat:GHL(@"%ld выполняется"), (long)pending]];
    NSString *subtitle = [GHMarkdownRenderer escapeHTML:[parts componentsJoinedByString:@", "]];

    if (failed > 0) {
        return [renderer rowHTMLWithGlyph:@"✕" glyphColor:@"#fff" glyphBackground:@"#cf222e"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Некоторые проверки не прошли")]
                             subtitleHTML:subtitle trailingHTML:nil];
    }
    if (pending > 0) {
        return [renderer rowHTMLWithGlyph:@"●" glyphColor:@"#fff" glyphBackground:@"#bf8700"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Проверки выполняются")]
                             subtitleHTML:subtitle trailingHTML:nil];
    }
    return [renderer rowHTMLWithGlyph:@"✓" glyphColor:@"#fff" glyphBackground:@"#1f883d"
                            titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Все проверки пройдены")]
                         subtitleHTML:subtitle trailingHTML:nil];
}

- (NSString *)mergeRowHTMLWithRenderer:(GHTimelineRenderer *)renderer {
    NSString *baseRef = [self safeStringForKey:@"ref" inDict:[self safeDictForKey:@"base" inDict:self.pullRequest]];
    NSString *escapedBase = [GHMarkdownRenderer escapeHTML:baseRef ?: @""];

    if ([self isMerged]) {
        NSString *subtitle = baseRef.length > 0 ? [NSString stringWithFormat:GHL(@"Изменения влиты в %@"), escapedBase] : nil;
        return [renderer rowHTMLWithGlyph:@"⑂" glyphColor:@"#fff" glyphBackground:@"#8250df"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Слит")]
                             subtitleHTML:subtitle trailingHTML:nil];
    }
    if ([[self safeStringForKey:@"state" inDict:self.pullRequest] isEqualToString:@"closed"]) {
        return [renderer rowHTMLWithGlyph:@"✕" glyphColor:@"#fff" glyphBackground:@"#cf222e"
                                titleHTML:[GHMarkdownRenderer escapeHTML:GHL(@"Закрыт без слияния")]
                             subtitleHTML:nil trailingHTML:nil];
    }

    NSString *mergeableState = [self safeStringForKey:@"mergeable_state" inDict:self.pullRequest];
    NSString *glyph = nil, *color = nil, *background = nil, *title = nil, *subtitle = nil;
    if ([mergeableState isEqualToString:@"clean"] || [mergeableState isEqualToString:@"has_hooks"]) {
        glyph = @"✓"; color = @"#fff"; background = @"#1f883d";
        title = GHL(@"Можно слить"); subtitle = GHL(@"Конфликтов с базовой веткой нет");
    } else if ([mergeableState isEqualToString:@"unstable"]) {
        glyph = @"!"; color = @"#fff"; background = @"#bf8700";
        title = GHL(@"Можно слить"); subtitle = GHL(@"Но некоторые проверки не прошли");
    } else if ([mergeableState isEqualToString:@"dirty"]) {
        glyph = @"✕"; color = @"#fff"; background = @"#cf222e";
        title = GHL(@"Есть конфликты"); subtitle = GHL(@"Их нужно разрешить перед слиянием");
    } else if ([mergeableState isEqualToString:@"blocked"]) {
        glyph = @"✕"; color = @"#fff"; background = @"#cf222e";
        title = GHL(@"Слияние заблокировано"); subtitle = GHL(@"Не выполнены обязательные условия");
    } else if ([mergeableState isEqualToString:@"behind"]) {
        glyph = @"!"; color = @"#fff"; background = @"#bf8700";
        title = GHL(@"Ветка отстаёт"); subtitle = [NSString stringWithFormat:GHL(@"Нужно обновить её от %@"), baseRef ?: @""];
    } else if ([mergeableState isEqualToString:@"draft"]) {
        glyph = @"○";
        title = GHL(@"Черновик"); subtitle = GHL(@"Слияние недоступно, пока пул-реквест в черновике");
    } else {
        return @"";
    }
    return [renderer rowHTMLWithGlyph:glyph glyphColor:color glyphBackground:background
                            titleHTML:[GHMarkdownRenderer escapeHTML:title]
                         subtitleHTML:[GHMarkdownRenderer escapeHTML:subtitle] trailingHTML:nil];
}

- (NSString *)buildHTMLWithTimeline:(NSArray *)timeline checkRuns:(NSDictionary *)checkRuns loadError:(NSString *)loadError {
    GHTimelineRenderer *renderer = [[GHTimelineRenderer alloc] initWithOwnerLogin:self.ownerLogin repoName:self.repoName];
    renderer.isPullRequest = YES;

    NSString *state = [self safeStringForKey:@"state" inDict:self.pullRequest];
    NSString *stateLabel;
    NSString *stateColor;
    if ([self isMerged]) {
        stateLabel = GHL(@"⑂ Слит");
        stateColor = @"#8250df";
    } else if ([state isEqualToString:@"closed"]) {
        stateLabel = GHL(@"✕ Закрыт");
        stateColor = @"#cf222e";
    } else if ([self isDraft]) {
        stateLabel = GHL(@"Черновик");
        stateColor = @"#59636e";
    } else {
        stateLabel = GHL(@"● Открыт");
        stateColor = @"#1f883d";
    }

    NSDictionary *head = [self safeDictForKey:@"head" inDict:self.pullRequest];
    NSString *headLabel = [self safeStringForKey:@"label" inDict:head] ?: [self safeStringForKey:@"ref" inDict:head];
    NSString *extra = [[renderer branchHTML:headLabel] stringByAppendingString:[renderer labelsHTML:self.pullRequest[@"labels"]]];

    NSMutableString *html = [NSMutableString stringWithString:[renderer styleCSS]];
    [html appendString:[renderer repoLineHTMLWithNumber:[self safeNumberForKey:@"number" inDict:self.pullRequest]]];
    [html appendString:[renderer titleHTML:[self safeStringForKey:@"title" inDict:self.pullRequest]]];
    [html appendString:[renderer stateRowHTMLWithLabel:stateLabel color:stateColor extraHTML:extra]];
    [html appendString:[renderer postHTMLWithUser:[self safeDictForKey:@"user" inDict:self.pullRequest]
                                         createdAt:[self safeStringForKey:@"created_at" inDict:self.pullRequest]
                                       association:[self safeStringForKey:@"author_association" inDict:self.pullRequest]
                                              body:[self safeStringForKey:@"body" inDict:self.pullRequest]]];

    id changedFilesValue = self.pullRequest[@"changed_files"];
    id commitsValue = self.pullRequest[@"commits"];
    if ([changedFilesValue isKindOfClass:[NSNumber class]] || [commitsValue isKindOfClass:[NSNumber class]]) {
        [html appendString:[renderer sectionHeaderHTML:GHL(@"Изменения")]];
        if ([changedFilesValue isKindOfClass:[NSNumber class]]) {
            NSInteger files = [changedFilesValue integerValue];
            NSString *title = [NSString stringWithFormat:@"%ld %@", (long)files,
                [self pluralForCount:files ruOne:@"файл изменён" ruFew:@"файла изменено" ruMany:@"файлов изменено"
                               enOne:@"file changed" enMany:@"files changed"]];
            NSString *trailing = [renderer additionsHTML:[[self safeNumberForKey:@"additions" inDict:self.pullRequest] integerValue]
                                               deletions:[[self safeNumberForKey:@"deletions" inDict:self.pullRequest] integerValue]];
            [html appendString:[renderer rowHTMLWithGlyph:@"±" glyphColor:nil glyphBackground:nil
                                                titleHTML:[GHMarkdownRenderer escapeHTML:title]
                                             subtitleHTML:nil trailingHTML:trailing]];
        }
        if ([commitsValue isKindOfClass:[NSNumber class]]) {
            NSInteger commits = [commitsValue integerValue];
            NSString *title = [NSString stringWithFormat:@"%ld %@", (long)commits,
                [self pluralForCount:commits ruOne:@"коммит" ruFew:@"коммита" ruMany:@"коммитов" enOne:@"commit" enMany:@"commits"]];
            NSString *lastCommitDate = nil;
            for (NSDictionary *item in timeline) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                if (![[self safeStringForKey:@"event" inDict:item] isEqualToString:@"committed"]) continue;
                lastCommitDate = [self safeStringForKey:@"date" inDict:[self safeDictForKey:@"committer" inDict:item]] ?: lastCommitDate;
            }
            NSString *when = [renderer relativeTimeFromISOString:lastCommitDate];
            [html appendString:[renderer rowHTMLWithGlyph:@"◦" glyphColor:nil glyphBackground:nil
                                                titleHTML:[GHMarkdownRenderer escapeHTML:title]
                                             subtitleHTML:nil
                                             trailingHTML:[GHMarkdownRenderer escapeHTML:when]]];
        }
    }

    NSString *reviewsRow = [self reviewsRowHTMLWithRenderer:renderer timeline:timeline];
    NSString *checksRow = [self checksRowHTMLWithRenderer:renderer checkRuns:checkRuns];
    NSString *mergeRow = [self mergeRowHTMLWithRenderer:renderer];
    if (checksRow.length > 0 || mergeRow.length > 0 || timeline.count > 0) {
        [html appendString:[renderer sectionHeaderHTML:GHL(@"Статус")]];
        [html appendString:reviewsRow];
        [html appendString:checksRow];
        [html appendString:mergeRow];
    }

    NSMutableString *conversation = [NSMutableString string];
    for (NSDictionary *item in timeline) {
        [conversation appendString:[renderer timelineItemHTML:item]];
    }
    if (conversation.length > 0) {
        [html appendString:[renderer sectionHeaderHTML:GHL(@"Обсуждение")]];
        [html appendString:conversation];
    }
    [html appendString:[renderer errorHTML:loadError]];

    return [GHMarkdownRenderer htmlDocumentWrappingBody:html];
}

- (void)renderWithTimeline:(NSArray *)timeline checkRuns:(NSDictionary *)checkRuns loadError:(NSString *)loadError {
    NSUInteger generation = ++self.renderGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *html = [strongSelf buildHTMLWithTimeline:timeline checkRuns:checkRuns loadError:loadError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (strongSelf.renderGeneration != generation) return;
            strongSelf.lastLoadedHTML = html;
            [strongSelf.webView loadHTMLString:html baseURL:[strongSelf contentBaseURL]];
        });
    });
}

- (void)loadDetailsThenRender {
    NSInteger number = [[self safeNumberForKey:@"number" inDict:self.pullRequest] integerValue];
    NSString *owner = self.ownerLogin;
    NSString *repo = self.repoName;

    __block NSArray *timeline = nil;
    __block NSDictionary *checkRuns = nil;
    __block NSString *loadError = nil;
    __block NSInteger pending = 3;

    __weak typeof(self) weakSelf = self;
    void (^finishOne)(void) = ^{
        pending--;
        if (pending > 0) return;
        [weakSelf renderWithTimeline:timeline checkRuns:checkRuns loadError:loadError];
    };

    void (^loadChecks)(NSString *) = ^(NSString *sha) {
        if (sha.length == 0) {
            finishOne();
            return;
        }
        [[GHAPIClient sharedClient] checkRunsForOwner:owner repo:repo ref:sha completion:^(id jsonObject, NSError *error) {
            if ([jsonObject isKindOfClass:[NSDictionary class]]) checkRuns = jsonObject;
            finishOne();
        }];
    };

    BOOL hasFullDetails = [self.pullRequest[@"changed_files"] isKindOfClass:[NSNumber class]];
    if (hasFullDetails) {
        finishOne();
        loadChecks([self safeStringForKey:@"sha" inDict:[self safeDictForKey:@"head" inDict:self.pullRequest]]);
    } else {
        [[GHAPIClient sharedClient] pullRequestForOwner:owner repo:repo number:number completion:^(id jsonObject, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && [jsonObject isKindOfClass:[NSDictionary class]]) strongSelf.pullRequest = jsonObject;
            NSDictionary *source = strongSelf ? strongSelf.pullRequest : nil;
            NSDictionary *headDict = [source[@"head"] isKindOfClass:[NSDictionary class]] ? source[@"head"] : nil;
            NSString *sha = [headDict[@"sha"] isKindOfClass:[NSString class]] ? headDict[@"sha"] : nil;
            finishOne();
            loadChecks(sha);
        }];
    }

    [[GHAPIClient sharedClient] timelineForOwner:owner repo:repo number:number completion:^(id jsonObject, NSError *error) {
        if ([jsonObject isKindOfClass:[NSArray class]]) {
            timeline = jsonObject;
            finishOne();
            return;
        }
        [[GHAPIClient sharedClient] commentsForOwner:owner repo:repo number:number completion:^(id commentsObject, NSError *commentsError) {
            if ([commentsObject isKindOfClass:[NSArray class]]) {
                timeline = commentsObject;
            } else {
                loadError = GHL(@"Не удалось загрузить комментарии.");
            }
            finishOne();
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
