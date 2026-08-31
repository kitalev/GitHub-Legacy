#import "RepoFilesViewController.h"
#import "GHAPIClient.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHMarkdownRenderer.h"
#import "ReadmeViewController.h"

static NSString * const kFileCellID = @"RepoFileCell";

@interface RepoFilesViewController ()
@property (nonatomic, strong) NSMutableArray *entries;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL hasLoadedOnce;
@end

@implementation RepoFilesViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kFileCellID];

    if (self.title.length == 0) {
        self.title = self.path.length > 0 ? [self.path lastPathComponent] : self.repoName;
    }

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.emptyLabel.font = [UIFont systemFontOfSize:15];
    self.emptyLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyLabel.text = GHL(@"Папка пуста");
    self.emptyLabel.backgroundColor = [UIColor clearColor];
    self.emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(loadContents) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self loadContents];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = (self.hasLoadedOnce && self.entries.count == 0) ? self.emptyLabel : nil;
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.emptyLabel.textColor = GHSecondaryTextColor();
    [self.tableView reloadData];
}

#pragma mark - Загрузка

- (void)loadContents {
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] fileContentsForOwner:self.ownerLogin
                                                  repo:self.repoName
                                                  path:self.path ?: @""
                                            completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
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

        NSArray *rawEntries;
        if ([jsonObject isKindOfClass:[NSArray class]]) {
            rawEntries = jsonObject;
        } else if ([jsonObject isKindOfClass:[NSDictionary class]]) {
            rawEntries = @[jsonObject];
        } else {
            rawEntries = @[];
        }

        [strongSelf.entries removeAllObjects];
        [strongSelf.entries addObjectsFromArray:rawEntries];

        [strongSelf.entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            BOOL aIsDir = [a[@"type"] isEqual:@"dir"];
            BOOL bIsDir = [b[@"type"] isEqual:@"dir"];
            if (aIsDir != bIsDir) return aIsDir ? NSOrderedAscending : NSOrderedDescending;
            NSString *aName = [a[@"name"] isKindOfClass:[NSString class]] ? a[@"name"] : @"";
            NSString *bName = [b[@"name"] isKindOfClass:[NSString class]] ? b[@"name"] : @"";
            return [aName caseInsensitiveCompare:bName];
        }];

        [strongSelf.tableView reloadData];
        strongSelf.hasLoadedOnce = YES;
        strongSelf.tableView.backgroundView = strongSelf.entries.count > 0 ? nil : strongSelf.emptyLabel;
    }];
}

#pragma mark - Открытие файла

+ (NSSet *)imageExtensions {
    static NSSet *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithObjects:@"png", @"jpg", @"jpeg", @"gif", @"bmp", @"webp", @"svg", nil];
    });
    return extensions;
}

+ (NSSet *)markdownExtensions {
    static NSSet *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = [NSSet setWithObjects:@"md", @"markdown", @"mdown", nil];
    });
    return extensions;
}

- (void)openFileEntry:(NSDictionary *)entry {
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    NSString *path = [entry[@"path"] isKindOfClass:[NSString class]] ? entry[@"path"] : name;
    NSString *downloadURLString = [entry[@"download_url"] isKindOfClass:[NSString class]] ? entry[@"download_url"] : nil;
    NSString *ext = name.pathExtension.lowercaseString;

    if ([[RepoFilesViewController imageExtensions] containsObject:ext] && downloadURLString.length > 0) {
        NSString *escapedURL = [GHMarkdownRenderer escapeHTMLAttribute:downloadURLString];
        NSString *bodyHTML = [NSString stringWithFormat:
            @"<div style=\"text-align:center;padding:16px 0;\"><img src=\"%@\" style=\"max-width:100%%;height:auto;\"></div>",
            escapedURL];
        NSString *fullHTML = [GHMarkdownRenderer htmlDocumentWrappingBody:bodyHTML];
        [self pushViewerWithHTML:fullHTML baseURL:nil title:name];
        return;
    }

    [self.spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] fileContentsForOwner:self.ownerLogin
                                                  repo:self.repoName
                                                  path:path
                                            completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.spinner stopAnimating];

        if (error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
            return;
        }

        NSDictionary *fileDict = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        NSString *base64Content = [fileDict[@"content"] isKindOfClass:[NSString class]] ? fileDict[@"content"] : nil;

        if (base64Content.length == 0) {

            [strongSelf openInSafari:downloadURLString];
            return;
        }

        __weak typeof(strongSelf) weakSelf2 = strongSelf;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *decodedData = [RepoFilesViewController dataFromBase64String:base64Content];
            NSString *text = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];

            if (text.length == 0) {

                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf2 openInSafari:downloadURLString];
                });
                return;
            }

            text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
            text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

            NSString *directoryPath = [path stringByDeletingLastPathComponent];
            NSString *baseURLString = directoryPath.length > 0
                ? [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/%@/", strongSelf.ownerLogin, strongSelf.repoName, directoryPath]
                : [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/HEAD/", strongSelf.ownerLogin, strongSelf.repoName];
            NSURL *baseURL = [NSURL URLWithString:baseURLString];

            BOOL isMarkdown = [[RepoFilesViewController markdownExtensions] containsObject:ext];
            if (isMarkdown) {

                NSString *bodyHTML = [GHMarkdownRenderer bodyHTMLFromMarkdown:text
                                                                      repoOwner:strongSelf.ownerLogin
                                                                       repoName:strongSelf.repoName];
                bodyHTML = [GHMarkdownRenderer inlineUserAttachmentImagesInHTML:bodyHTML
                                                                        ownerLogin:strongSelf.ownerLogin
                                                                          repoName:strongSelf.repoName];
                NSString *fullHTML = [GHMarkdownRenderer htmlDocumentWrappingBody:bodyHTML];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf2 pushViewerWithHTML:fullHTML baseURL:baseURL title:name];
                });
                return;
            }

            [weakSelf2 openCodeViewerForText:text baseURL:baseURL title:name];
        });
    }];
}

- (void)openCodeViewerForText:(NSString *)text baseURL:(NSURL *)baseURL title:(NSString *)title {
    NSMutableArray *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];

    if (lines.count > 0 && [lines.lastObject isEqualToString:@""]) {
        [lines removeLastObject];
    }

    NSInteger totalLines = lines.count;
    NSInteger totalChunks = MAX((totalLines + kCodeChunkSize - 1) / kCodeChunkSize, 1);

    NSRange firstChunkRange = NSMakeRange(0, MIN((NSUInteger)kCodeChunkSize, lines.count));
    NSString *firstChunkHTML = [RepoFilesViewController codeViewerShellHTMLForLines:lines
                                                                          chunkRange:firstChunkRange
                                                                          totalLines:totalLines
                                                                         totalChunks:totalChunks];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        ReadmeViewController *viewerVC = [strongSelf pushViewerWithHTML:firstChunkHTML baseURL:baseURL title:title];

        if (totalChunks <= 1) return;

        NSMutableArray *chunkLineCounts = [NSMutableArray array];
        for (NSInteger chunkIndex = 1; chunkIndex < totalChunks; chunkIndex++) {
            NSInteger start = chunkIndex * kCodeChunkSize;
            NSInteger length = MIN((NSInteger)kCodeChunkSize, totalLines - start);
            [chunkLineCounts addObject:@(length)];
        }
        viewerVC.codeViewerChunkLineCounts = chunkLineCounts;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            for (NSInteger chunkIndex = 1; chunkIndex < totalChunks; chunkIndex++) {
                NSUInteger start = (NSUInteger)(chunkIndex * kCodeChunkSize);
                NSUInteger length = MIN((NSUInteger)kCodeChunkSize, lines.count - start);
                if (length == 0) break;

                NSString *injectionJS = [RepoFilesViewController injectionJSForChunkIndex:chunkIndex
                                                                                      lines:lines
                                                                                      range:NSMakeRange(start, length)];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [viewerVC evaluateJavaScript:injectionJS];
                });
            }
        });
    });
}

- (ReadmeViewController *)pushViewerWithHTML:(NSString *)html baseURL:(NSURL *)baseURL title:(NSString *)title {
    ReadmeViewController *viewerVC = [[ReadmeViewController alloc] init];
    viewerVC.html = html;
    viewerVC.baseURL = baseURL;
    viewerVC.ownerLogin = self.ownerLogin;
    viewerVC.repoName = self.repoName;
    viewerVC.title = title;
    [self.navigationController pushViewController:viewerVC animated:YES];
    return viewerVC;
}

- (void)openInSafari:(NSString *)urlString {
    if (urlString.length == 0) return;
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url];
    }
}

#pragma mark - Просмотр обычного (не-markdown) текстового файла

static const NSInteger kCodeChunkSize = 300;

+ (void)buildGutterHTML:(NSString **)outGutterHTML
                codeHTML:(NSString **)outCodeHTML
                forLines:(NSArray *)rawLines
                   range:(NSRange)range {
    NSArray *rangeLines = [rawLines subarrayWithRange:range];
    NSString *chunkText = [rangeLines componentsJoinedByString:@"\n"];
    NSString *highlighted = [self syntaxHighlightedHTMLForCode:chunkText];
    NSArray *highlightedLines = [highlighted componentsSeparatedByString:@"\n"];

    NSMutableString *gutterHTML = [NSMutableString string];
    NSMutableString *codeHTML = [NSMutableString string];
    for (NSUInteger i = 0; i < range.length; i++) {
        NSInteger lineNumber = (NSInteger)(range.location + i + 1);
        NSString *lineHTML = i < highlightedLines.count ? highlightedLines[i] : @"";
        [gutterHTML appendFormat:@"<div class=\"ln-row\">%ld</div>", (long)lineNumber];
        [codeHTML appendFormat:@"<tr><td class=\"code-cell\">%@</td></tr>", lineHTML.length > 0 ? lineHTML : @"&nbsp;"];
    }
    if (outGutterHTML) *outGutterHTML = gutterHTML;
    if (outCodeHTML) *outCodeHTML = codeHTML;
}

+ (NSString *)codeViewerShellHTMLForLines:(NSArray *)rawLines
                                chunkRange:(NSRange)chunkRange
                                totalLines:(NSInteger)totalLines
                               totalChunks:(NSInteger)totalChunks {
    NSString *gutterHTML = nil;
    NSString *codeHTML = nil;
    [self buildGutterHTML:&gutterHTML codeHTML:&codeHTML forLines:rawLines range:chunkRange];

    NSMutableString *body = [NSMutableString string];
    [body appendFormat:
        @"<div class=\"code-block\">"
         "<div class=\"code-gutter\">%@</div>"
         "<div class=\"code-area\"><table class=\"code-table\"><tbody>%@</tbody></table></div>"
         "</div>",
        gutterHTML, codeHTML];

    if (totalChunks > 1) {

        NSMutableArray *labels = [NSMutableArray array];
        for (NSInteger chunkIndex = 1; chunkIndex < totalChunks; chunkIndex++) {
            NSInteger start = chunkIndex * kCodeChunkSize;
            NSInteger length = MIN((NSInteger)kCodeChunkSize, totalLines - start);
            NSString *label = [NSString stringWithFormat:GHL(@"Показать ещё %ld %@"),
                                (long)length, [self linesWordForCount:length]];
            [labels addObject:[label stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"]];
        }
        NSString *labelsAttr = [labels componentsJoinedByString:@"|"];
        [body appendFormat:@"<div class=\"show-more\" id=\"show-more\" "
                             "data-total=\"%ld\" data-shown=\"0\" data-labels=\"%@\" "
                             "ontouchstart=\"chunkTouchStart(event)\" ontouchend=\"chunkTouchEnd(event)\">%@</div>",
                             (long)(totalChunks - 1), labelsAttr, labels[0]];
    }

    return [self wrapCodeViewerBodyInDocument:body];
}

+ (NSString *)injectionJSForChunkIndex:(NSInteger)chunkIndex lines:(NSArray *)rawLines range:(NSRange)range {
    NSString *gutterPart = nil;
    NSString *codePart = nil;
    [self buildGutterHTML:&gutterPart codeHTML:&codePart forLines:rawLines range:range];

    NSString *gutterWrapped = [NSString stringWithFormat:
        @"<div class=\"more-rows\" id=\"gutter-chunk-%ld\" style=\"display:none;\">%@</div>", (long)chunkIndex, gutterPart];
    NSString *codeWrapped = [NSString stringWithFormat:
        @"<div class=\"more-rows\" id=\"code-chunk-%ld\" style=\"display:none;\"><table class=\"code-table\"><tbody>%@</tbody></table></div>",
        (long)chunkIndex, codePart];

    NSString *gutterJS = [self escapeForSingleQuotedJavaScriptString:gutterWrapped];
    NSString *codeJS = [self escapeForSingleQuotedJavaScriptString:codeWrapped];

    return [NSString stringWithFormat:
        @"(function(){"
         "var g=document.querySelector('.code-gutter');"
         "var c=document.querySelector('.code-area');"
         "if(g)g.insertAdjacentHTML('beforeend','%@');"
         "if(c)c.insertAdjacentHTML('beforeend','%@');"
         "})();",
        gutterJS, codeJS];
}

+ (NSString *)escapeForSingleQuotedJavaScriptString:(NSString *)text {
    NSString *escaped = text ?: @"";
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    return escaped;
}

+ (NSString *)wrapCodeViewerBodyInDocument:(NSString *)body {

    NSString *css =
        @"html,body{-webkit-text-size-adjust:100%;overflow-x:hidden;}"
        "body{font-family:-apple-system,Helvetica;font-size:14px;color:#1f2328;margin:0;padding:0;}"
        ".code-block{display:-webkit-box;display:flex;-webkit-box-orient:horizontal;font-family:Menlo,monospace;font-size:12px;line-height:1.6;}"
        ".code-gutter{-webkit-box-flex:0;flex:0 0 auto;background:#f6f8fa;color:#59636e;text-align:right;border-right:1px solid #d0d7de;-webkit-text-size-adjust:100%;}"
        ".code-gutter .ln-row{padding:1px 8px;white-space:nowrap;}"
        ".code-area{-webkit-box-flex:1;flex:1 1 auto;overflow-x:auto;min-width:0;-webkit-text-size-adjust:100%;}"
        ".code-table{border-collapse:collapse;width:100%;}"
        ".code-table td.code-cell{white-space:pre;padding:1px 12px;color:#1f2328;}"

        ".tok-comment{color:#6a737d;}"
        ".tok-string{color:#032f62;}"
        ".tok-number{color:#005cc5;}"
        ".tok-keyword{color:#d73a49;}"
        ".tok-preproc{color:#005cc5;}"
        ".tok-function{color:#6f42c1;}"
        ".show-more{padding:10px 12px;text-align:center;color:#0969da;font-size:13px;font-weight:bold;background:#f6f8fa;border-top:1px solid #d0d7de;cursor:pointer;}"
        ".show-more:active{background:#eaeef1;}";

    NSString *darkCss =
        @"body{background:#0d1117;color:#c9d1d9;}"
        ".code-gutter{background:#161b22;color:#8b949e;border-right-color:#30363d;}"
        ".code-table td.code-cell{color:#c9d1d9;}"

        ".tok-comment{color:#8b949e;}"
        ".tok-string{color:#a5d6ff;}"
        ".tok-number{color:#79c0ff;}"
        ".tok-keyword{color:#ff7b72;}"
        ".tok-preproc{color:#79c0ff;}"
        ".tok-function{color:#d2a8ff;}"
        ".show-more{color:#58a6ff;background:#161b22;border-top-color:#30363d;}"
        ".show-more:active{background:#21262d;}";

    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
    NSString *initialThemeJS = [GHMarkdownRenderer themeToggleScriptForDarkModeEnabled:isDark];

    NSString *js =
        @"var _touchStartX=0,_touchStartY=0;"
        "function chunkTouchStart(e){"
        "var t=e.touches[0];"
        "_touchStartX=t.clientX;_touchStartY=t.clientY;"
        "}"

        "function didMoveTooMuch(e){"
        "var t=e.changedTouches[0];"
        "var dx=Math.abs(t.clientX-_touchStartX);"
        "var dy=Math.abs(t.clientY-_touchStartY);"
        "return dx>10||dy>10;"
        "}"
        "function chunkTouchEnd(e){"
        "if(didMoveTooMuch(e))return;"
        "revealNextChunk();"
        "}"
        "function revealNextChunk(){"
        "var btn=document.getElementById('show-more');"
        "if(!btn)return;"
        "var shown=parseInt(btn.getAttribute('data-shown'),10)||0;"
        "var total=parseInt(btn.getAttribute('data-total'),10)||0;"
        "var chunkIndex=shown+1;"
        "var g=document.getElementById('gutter-chunk-'+chunkIndex);"
        "var c=document.getElementById('code-chunk-'+chunkIndex);"

        "if(!g||!c)return;"
        "g.style.display='';"
        "c.style.display='';"
        "shown++;"
        "btn.setAttribute('data-shown',shown);"
        "if(shown>=total){"
        "btn.style.display='none';"
        "}else{"
        "var labels=btn.getAttribute('data-labels').split('|');"
        "if(labels[shown])btn.innerHTML=labels[shown];"
        "}"
        "}";

    return [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head>"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>"
        "<style id=\"gh-base-style\">%@</style>"
        "<style id=\"gh-dark-style\">%@</style>"
        "<script>%@</script>"
        "<script>%@</script>"
        "</head><body>%@</body></html>",
        css, darkCss, initialThemeJS, js, body];
}

+ (NSString *)linesWordForCount:(NSInteger)count {
    NSInteger mod100 = count % 100;
    NSInteger mod10 = count % 10;
    if (mod100 >= 11 && mod100 <= 14) return GHL(@"строк");
    if (mod10 == 1) return GHL(@"строку");
    if (mod10 >= 2 && mod10 <= 4) return GHL(@"строки");
    return GHL(@"строк");
}

#pragma mark - Подсветка синтаксиса

+ (NSString *)syntaxHighlightedHTMLForCode:(NSString *)text {
    if (text.length == 0) return @"";

    static NSArray *keywords;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        keywords = @[
            @"static", @"void", @"int", @"char", @"const", @"unsigned", @"signed",
            @"long", @"short", @"float", @"double", @"struct", @"typedef", @"union",
            @"enum", @"extern", @"volatile", @"register", @"sizeof", @"return",
            @"if", @"else", @"for", @"while", @"do", @"switch", @"case", @"break",
            @"continue", @"default", @"goto", @"NULL", @"nullptr", @"true", @"false",
            @"TRUE", @"FALSE", @"class", @"public", @"private", @"protected",
            @"virtual", @"override", @"template", @"namespace", @"using", @"new",
            @"delete", @"this", @"self", @"super", @"nil", @"id", @"BOOL", @"YES", @"NO",
            @"import", @"export", @"package", @"interface", @"implements", @"throws",
            @"throw", @"try", @"catch", @"finally", @"function", @"var", @"let", @"def",
            @"elif", @"pass", @"lambda", @"yield", @"async", @"await", @"None", @"True",
            @"False", @"and", @"or", @"not", @"is", @"in", @"from", @"as", @"with",
            @"module", @"end", @"then", @"fn", @"impl", @"trait", @"mod", @"pub", @"mut",
            @"match", @"loop", @"where", @"type", @"func", @"defer", @"chan", @"go",
            @"range", @"select", @"inline", @"constexpr", @"noexcept",
        ];
    });

    NSMutableArray *tokenHTML = [NSMutableArray array];
    NSString *result = text;

    NSString *(^protect)(NSString *, NSString *, NSString *) = ^NSString *(NSString *sourceText, NSString *pattern, NSString *cssClass) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                  options:NSRegularExpressionAnchorsMatchLines
                                                                                    error:nil];
        if (!regex) return sourceText;

        NSMutableString *replaced = [NSMutableString string];
        __block NSUInteger lastLocation = 0;
        NSString *sourceCopy = sourceText;

        [regex enumerateMatchesInString:sourceCopy
                                 options:0
                                   range:NSMakeRange(0, sourceCopy.length)
                              usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            [replaced appendString:[sourceCopy substringWithRange:NSMakeRange(lastLocation, match.range.location - lastLocation)]];

            NSString *matchedText = [sourceCopy substringWithRange:match.range];
            NSString *escaped = [GHMarkdownRenderer escapeHTML:matchedText];
            NSString *spanHTML;

            if ([escaped rangeOfString:@"\n"].location != NSNotFound) {
                NSArray *pieces = [escaped componentsSeparatedByString:@"\n"];
                NSMutableArray *wrapped = [NSMutableArray arrayWithCapacity:pieces.count];
                for (NSString *piece in pieces) {
                    [wrapped addObject:[NSString stringWithFormat:@"<span class=\"%@\">%@</span>", cssClass, piece]];
                }
                spanHTML = [wrapped componentsJoinedByString:@"\n"];
            } else {
                spanHTML = [NSString stringWithFormat:@"<span class=\"%@\">%@</span>", cssClass, escaped];
            }

            [tokenHTML addObject:spanHTML];
            [replaced appendFormat:@"\x02TOK%lu\x03", (unsigned long)(tokenHTML.count - 1)];
            lastLocation = match.range.location + match.range.length;
        }];

        [replaced appendString:[sourceCopy substringFromIndex:lastLocation]];
        return replaced;
    };

    result = protect(result, @"/\\*[\\s\\S]*?\\*/", @"tok-comment");

    result = protect(result, @"^[ \\t]*#\\s*(?:define|undef|include|include_next|import|if|ifdef|ifndef|elif|elifdef|elifndef|else|endif|line|error|warning|pragma)\\b[^\\n]*", @"tok-preproc");
    result = protect(result, @"//[^\\n]*|#[^\\n]*", @"tok-comment");
    result = protect(result, @"\"(?:\\\\.|[^\"\\\\\\n])*\"", @"tok-string");
    result = protect(result, @"'(?:\\\\.|[^'\\\\\\n])*'", @"tok-string");
    result = protect(result, @"\\b(?:0[xX][0-9a-fA-F]+|\\d+\\.\\d+[fF]?|\\d+[uUlLfF]*)\\b", @"tok-number");
    result = protect(result, [NSString stringWithFormat:@"\\b(?:%@)\\b", [keywords componentsJoinedByString:@"|"]], @"tok-keyword");

    result = protect(result, @"\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", @"tok-function");

    result = [GHMarkdownRenderer escapeHTML:result];

    for (NSUInteger i = 0; i < tokenHTML.count; i++) {
        NSString *placeholder = [NSString stringWithFormat:@"\x02TOK%lu\x03", (unsigned long)i];
        result = [result stringByReplacingOccurrencesOfString:placeholder withString:tokenHTML[i]];
    }

    return result;
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

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFileCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.textColor = GHPrimaryTextColor();
    cell.textLabel.numberOfLines = 1;

    NSDictionary *entry = self.entries[indexPath.row];
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    BOOL isDir = [entry[@"type"] isEqual:@"dir"];

    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", isDir ? @"📁" : @"📄", name];
    cell.accessoryType = UITableViewCellAccessoryNone;
    GHApplyDisclosureIndicator(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSDictionary *entry = self.entries[indexPath.row];
    BOOL isDir = [entry[@"type"] isEqual:@"dir"];

    if (isDir) {
        RepoFilesViewController *childVC = [[RepoFilesViewController alloc] init];
        childVC.ownerLogin = self.ownerLogin;
        childVC.repoName = self.repoName;
        childVC.path = entry[@"path"];
        [self.navigationController pushViewController:childVC animated:YES];
        return;
    }

    [self openFileEntry:entry];
}

@end
