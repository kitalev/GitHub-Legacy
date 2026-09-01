#import "ReleaseDetailViewController.h"
#import "DownloadManager.h"
#import "GHThemeManager.h"
#import "GHMarkdownRenderer.h"
#import "GHLocalization.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "SettingsViewController.h"
#import "GHIconRenderer.h"
#import "ReadmeViewController.h"
#import "AppDelegate.h"

static const NSInteger kSectionNotes = 0;
static const NSInteger kSectionDownloads = 1;
static const NSInteger kSectionCount = 2;

static const NSInteger kNotesRowNotes = 0;
static const NSInteger kNotesSectionRowCount = 1;
static const NSInteger kDownloadCompleteAlertTag = 1;
static const NSInteger kLoginRequiredAlertTag = 2;

static NSArray *GHReactionContents(void) {
    return @[@"+1", @"laugh", @"hooray", @"heart", @"rocket", @"eyes"];
}

static NSString *GHReactionEmoji(NSString *content) {
    if ([content isEqualToString:@"+1"]) return @"👍";
    if ([content isEqualToString:@"laugh"]) return @"😄";
    if ([content isEqualToString:@"hooray"]) return @"🎉";
    if ([content isEqualToString:@"heart"]) return @"❤️";
    if ([content isEqualToString:@"rocket"]) return @"🚀";
    if ([content isEqualToString:@"eyes"]) return @"👀";
    return @"";
}

static const CGFloat kNotesVerticalPadding = 10.0;

@interface GHDownloadItem : NSObject
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *downloadURLString;
@property (nonatomic, assign) long long sizeBytes;
@property (nonatomic, assign) float downloadProgress;
@end

@implementation GHDownloadItem
@end

@interface ReleaseDetailViewController ()
@property (nonatomic, strong) NSArray *downloadItems;
@property (nonatomic, strong) NSIndexPath *downloadingIndexPath;
@property (nonatomic, copy) NSString *lastDownloadedFilePath;
@property (nonatomic, strong) UIDocumentInteractionController *documentInteractionController;

@property (nonatomic, strong) UIWebView *notesWebView;
@property (nonatomic, assign) CGFloat notesWebViewHeight;
@property (nonatomic, assign) BOOL notesHTMLReady;

@property (nonatomic, copy) NSString *notesFullHTML;
@property (nonatomic, strong) NSURL *notesBaseURL;

@property (nonatomic, assign) BOOL notesIsClipped;

@property (nonatomic, copy) NSString *notesPreviewHTML;

@property (nonatomic, assign) BOOL notesWebViewUnloadedForBackground;

@property (nonatomic, strong) NSMutableDictionary *reactionCounts;

@property (nonatomic, strong) NSMutableDictionary *myReactionIDs;
@property (nonatomic, copy) NSString *currentUsername;
@property (nonatomic, assign) BOOL reactionsActionInProgress;
@end

@implementation ReleaseDetailViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _notesWebViewHeight = 44;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"NotesCell"];
    self.reactionCounts = [NSMutableDictionary dictionary];
    self.myReactionIDs = [NSMutableDictionary dictionary];
    [self buildDownloadItems];
    [self loadReleaseNotesHTML];
    [self loadReactions];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(handlePullToRefresh) forControlEvents:UIControlEventValueChanged];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Назад")
                                                                                style:UIBarButtonItemStylePlain
                                                                               target:nil
                                                                               action:nil];

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
    if (!self.notesWebView || self.notesPreviewHTML.length == 0) return;
    self.notesWebViewUnloadedForBackground = YES;

    self.notesWebView.delegate = nil;
    [self.notesWebView stopLoading];
    [self.notesWebView loadHTMLString:@"" baseURL:nil];
    [self.notesWebView removeFromSuperview];
    self.notesWebView = nil;
}

- (void)handleAppWillEnterForeground {
    if (!self.notesWebViewUnloadedForBackground) return;

    if (!self.isViewLoaded || !self.view.window) return;
    [self reloadNotesWebViewAfterBackgroundUnload];
}

- (void)reloadNotesWebViewAfterBackgroundUnload {
    self.notesWebViewUnloadedForBackground = NO;
    if (self.notesPreviewHTML.length == 0) return;

    if (self.notesWebView == nil) {
        CGFloat width = self.tableView.bounds.size.width - 20.0;
        self.notesWebView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
        self.notesWebView.delegate = self;
        self.notesWebView.opaque = NO;
        self.notesWebView.backgroundColor = [UIColor clearColor];
        self.notesWebView.scrollView.scrollEnabled = NO;
        self.notesWebView.scrollView.bounces = NO;
        self.notesWebView.dataDetectorTypes = UIDataDetectorTypeNone;
    }
    [self.notesWebView loadHTMLString:self.notesPreviewHTML baseURL:self.notesBaseURL];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.notesWebViewUnloadedForBackground) {
        [self reloadNotesWebViewAfterBackgroundUnload];
    }
}

- (void)handleLanguageDidChange {
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Назад")
                                                                                style:UIBarButtonItemStylePlain
                                                                               target:nil
                                                                               action:nil];
    self.notesWebView.delegate = nil;
    [self.notesWebView stopLoading];
    self.notesWebView = nil;
    self.notesHTMLReady = NO;
    self.notesFullHTML = nil;
    [self buildDownloadItems];
    [self loadReleaseNotesHTML];
    [self.tableView reloadData];
}

- (void)handlePullToRefresh {
    long long releaseID = [self releaseID];
    if (releaseID == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) {
        [self.refreshControl endRefreshing];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] releaseForOwner:self.ownerLogin
                                            repo:self.repoName
                                       releaseID:releaseID
                                      completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.refreshControl endRefreshing];

        if (error || ![jsonObject isKindOfClass:[NSDictionary class]]) {

            return;
        }

        strongSelf.releaseInfo = jsonObject;
        strongSelf.notesWebView.delegate = nil;
        [strongSelf.notesWebView stopLoading];
        strongSelf.notesWebView = nil;
        strongSelf.notesHTMLReady = NO;
        strongSelf.notesFullHTML = nil;
        [strongSelf buildDownloadItems];
        [strongSelf loadReleaseNotesHTML];
        [strongSelf loadReactions];
        [strongSelf.tableView reloadData];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.notesWebView.delegate = nil;
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();

    if (self.notesWebView != nil) {
        BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
        NSString *js = [GHMarkdownRenderer themeToggleScriptForDarkModeEnabled:isDark];
        [self.notesWebView stringByEvaluatingJavaScriptFromString:js];
    }

    [self.tableView reloadData];
}

- (void)buildDownloadItems {
    NSMutableArray *items = [NSMutableArray array];

    NSArray *assets = self.releaseInfo[@"assets"];
    for (NSDictionary *asset in assets) {
        GHDownloadItem *item = [[GHDownloadItem alloc] init];
        item.displayName = asset[@"name"];
        item.fileName = asset[@"name"];
        item.downloadURLString = asset[@"browser_download_url"];
        NSNumber *size = asset[@"size"];
        item.sizeBytes = size.longLongValue;
        [items addObject:item];
    }

    id tagValue = self.releaseInfo[@"tag_name"];
    NSString *tagName = [tagValue isKindOfClass:[NSString class]] ? tagValue : @"release";
    NSString *zipURL = self.releaseInfo[@"zipball_url"];
    NSString *tarURL = self.releaseInfo[@"tarball_url"];

    if (zipURL.length > 0) {
        GHDownloadItem *item = [[GHDownloadItem alloc] init];
        item.displayName = GHL(@"Исходный код (zip)");
        item.fileName = [NSString stringWithFormat:@"source-%@.zip", tagName];
        item.downloadURLString = zipURL;
        item.sizeBytes = 0;
        [items addObject:item];
    }
    if (tarURL.length > 0) {
        GHDownloadItem *item = [[GHDownloadItem alloc] init];
        item.displayName = GHL(@"Исходный код (tar.gz)");
        item.fileName = [NSString stringWithFormat:@"source-%@.tar.gz", tagName];
        item.downloadURLString = tarURL;
        item.sizeBytes = 0;
        [items addObject:item];
    }

    self.downloadItems = items;
}

#pragma mark - Release notes (changelog) webview

- (void)loadReleaseNotesHTML {
    id bodyValue = self.releaseInfo[@"body"];
    NSString *body = [bodyValue isKindOfClass:[NSString class]] ? bodyValue : @"";

    if (body.length == 0) {
        self.notesHTMLReady = NO;
        return;
    }

    CGFloat width = self.tableView.bounds.size.width - 20.0;
    if (width <= 0) width = 300;

    NSString *ownerLogin = [self ownerLoginFromReleaseURL];
    NSURL *baseURL = ownerLogin.length > 0
        ? [NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/", ownerLogin]]
        : nil;
    self.notesBaseURL = baseURL;

    static const NSUInteger kNotesPreviewClipThreshold = 1000;
    BOOL needsClip = body.length > kNotesPreviewClipThreshold;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSString *previewMarkdown = needsClip
            ? [self safeMarkdownPrefixOfString:body maxLength:kNotesPreviewClipThreshold]
            : body;
        NSString *previewBodyHTML = [GHMarkdownRenderer bodyHTMLFromMarkdown:previewMarkdown];
        if (needsClip) {

            previewBodyHTML = [GHMarkdownRenderer autoCloseUnclosedTagsInHTML:previewBodyHTML];
        }

        NSString *previewHTML = needsClip
            ? [GHMarkdownRenderer htmlDocumentWrappingBody:

                [NSString stringWithFormat:@"%@<a href=\"app://release-notes-full\" class=\"show-more\">%@</a>",
                    previewBodyHTML, GHL(@"Читать полностью →")]
                                                   pixelWidth:width]
            : [GHMarkdownRenderer htmlDocumentWrappingBody:previewBodyHTML pixelWidth:width];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (![strongSelf.releaseInfo[@"body"] isEqual:body]) return;

            strongSelf.notesIsClipped = needsClip;
            strongSelf.notesPreviewHTML = previewHTML;
            strongSelf.notesWebView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, width, 1)];
            strongSelf.notesWebView.delegate = strongSelf;
            strongSelf.notesWebView.opaque = NO;
            strongSelf.notesWebView.backgroundColor = [UIColor clearColor];
            strongSelf.notesWebView.scrollView.scrollEnabled = NO;
            strongSelf.notesWebView.scrollView.bounces = NO;
            strongSelf.notesWebView.dataDetectorTypes = UIDataDetectorTypeNone;
            [strongSelf.notesWebView loadHTMLString:previewHTML baseURL:strongSelf.notesBaseURL];
        });

        if (!needsClip) return;

        NSString *fullBodyHTML = [GHMarkdownRenderer bodyHTMLFromMarkdown:body];
        NSString *fullHTML = [GHMarkdownRenderer htmlDocumentWrappingBody:fullBodyHTML];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (![strongSelf.releaseInfo[@"body"] isEqual:body]) return;
            strongSelf.notesFullHTML = fullHTML;
        });
    });
}

- (NSString *)safeMarkdownPrefixOfString:(NSString *)markdown maxLength:(NSUInteger)maxLength {
    NSUInteger length = MIN(markdown.length, maxLength);
    NSString *candidate = [markdown substringToIndex:length];

    NSRange lastParagraphBreak = [candidate rangeOfString:@"\n\n" options:NSBackwardsSearch];
    if (lastParagraphBreak.location != NSNotFound && lastParagraphBreak.location > 0) {
        return [candidate substringToIndex:lastParagraphBreak.location];
    }

    NSRange lastClosingParen = [candidate rangeOfString:@")" options:NSBackwardsSearch];
    if (lastClosingParen.location != NSNotFound) {
        return [candidate substringToIndex:lastClosingParen.location + 1];
    }

    return candidate;
}

- (NSString *)ownerLoginFromReleaseURL {
    NSString *htmlURL = self.releaseInfo[@"html_url"];
    if (![htmlURL isKindOfClass:[NSString class]]) return nil;
    NSArray *parts = [htmlURL componentsSeparatedByString:@"/"];

    NSUInteger idx = [parts indexOfObject:@"github.com"];
    if (idx != NSNotFound && idx + 2 < parts.count) {
        return [NSString stringWithFormat:@"%@/%@", parts[idx + 1], parts[idx + 2]];
    }
    return nil;
}

#pragma mark - Реакции

- (long long)releaseID {
    id releaseIDValue = self.releaseInfo[@"id"];
    if ([releaseIDValue respondsToSelector:@selector(longLongValue)]) {
        return [(NSNumber *)releaseIDValue longLongValue];
    }
    return 0;
}

- (void)loadReactions {
    long long releaseID = [self releaseID];
    if (releaseID == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] reactionsForOwner:self.ownerLogin
                                              repo:self.repoName
                                         releaseID:releaseID
                                        completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error || ![jsonObject isKindOfClass:[NSArray class]]) return;
        [strongSelf applyReactionsList:jsonObject];
    }];
}

- (void)applyReactionsList:(NSArray *)reactions {
    __weak typeof(self) weakSelf = self;
    void (^finish)(void) = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        NSMutableDictionary *mine = [NSMutableDictionary dictionary];
        for (NSDictionary *reaction in reactions) {
            if (![reaction isKindOfClass:[NSDictionary class]]) continue;
            NSString *content = reaction[@"content"];
            if (![content isKindOfClass:[NSString class]]) continue;

            counts[content] = @([counts[content] integerValue] + 1);

            id reactionID = reaction[@"id"];
            NSDictionary *user = [reaction[@"user"] isKindOfClass:[NSDictionary class]] ? reaction[@"user"] : nil;
            NSString *login = [user[@"login"] isKindOfClass:[NSString class]] ? user[@"login"] : nil;
            if (strongSelf.currentUsername.length > 0 && [login isEqualToString:strongSelf.currentUsername] &&
                [reactionID respondsToSelector:@selector(longLongValue)]) {
                mine[content] = reactionID;
            }
        }
        strongSelf.reactionCounts = counts;
        strongSelf.myReactionIDs = mine;

        [strongSelf.tableView reloadData];
    };

    if (self.currentUsername.length > 0 || ![GHAuthManager sharedManager].isAuthenticated) {
        finish();
        return;
    }

    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *login = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject[@"login"] : nil;
        if ([login isKindOfClass:[NSString class]]) strongSelf.currentUsername = login;
        finish();
    }];
}

static const NSInteger kReactionButtonTagBase = 9000;
static const NSInteger kReactionAddButtonTag = 9099;
static const NSInteger kReactionsScrollViewTag = 9600;

static const NSInteger kReactionPillBackgroundTagOffset = 100;
static const CGFloat kReactionButtonHeight = 30.0;
static const CGFloat kReactionsRowHeight = 46.0;

- (void)layoutReactionButtonsInCell:(UITableViewCell *)cell topY:(CGFloat)topY {
    [[cell.contentView viewWithTag:kReactionsScrollViewTag] removeFromSuperview];

    CGFloat width = cell.contentView.bounds.size.width > 0 ? cell.contentView.bounds.size.width : self.tableView.bounds.size.width;
    CGFloat scrollY = topY + (kReactionsRowHeight - kReactionButtonHeight) / 2.0;

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, scrollY, width, kReactionButtonHeight)];
    scrollView.tag = kReactionsScrollViewTag;
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.backgroundColor = [UIColor clearColor];

    scrollView.scrollEnabled = YES;
    scrollView.userInteractionEnabled = YES;

    CGFloat x = 15;
    CGFloat spacing = 8;

    UIButton *addButton = [self reactionAddButton];
    addButton.tag = kReactionAddButtonTag;
    addButton.frame = CGRectMake(x, 0, kReactionButtonHeight, kReactionButtonHeight);
    [scrollView addSubview:addButton];
    x += kReactionButtonHeight + spacing;

    NSArray *contents = GHReactionContents();
    for (NSInteger i = 0; i < (NSInteger)contents.count; i++) {
        NSString *content = contents[i];
        NSInteger count = [self.reactionCounts[content] integerValue];
        if (count <= 0) continue;

        BOOL isMine = self.myReactionIDs[content] != nil;
        NSString *title = [NSString stringWithFormat:@"%@ %ld", GHReactionEmoji(content), (long)count];

        UIButton *button = [self reactionPillButtonWithTitle:title height:kReactionButtonHeight];
        button.tag = kReactionButtonTagBase + i;
        [button setTitleColor:isMine ? GHReactionAccentColor() : GHPrimaryTextColor() forState:UIControlStateNormal];
        [button addTarget:self action:@selector(reactionPillTapped:) forControlEvents:UIControlEventTouchUpInside];

        CGSize fitSize = [button sizeThatFits:CGSizeMake(CGFLOAT_MAX, kReactionButtonHeight)];
        CGFloat itemWidth = MAX(fitSize.width, kReactionButtonHeight);
        CGRect pillFrame = CGRectMake(x, 0, itemWidth, kReactionButtonHeight);

        UIView *pillBackground = [[UIView alloc] initWithFrame:pillFrame];
        pillBackground.backgroundColor = isMine ? GHReactionSelectedBackgroundColor() : GHReactionPillBackgroundColor();
        pillBackground.layer.cornerRadius = kReactionButtonHeight / 2.0;
        pillBackground.layer.masksToBounds = YES;

        pillBackground.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
        pillBackground.layer.borderColor = GHReactionPillBorderColor().CGColor;
        pillBackground.userInteractionEnabled = NO;

        pillBackground.tag = kReactionButtonTagBase + kReactionPillBackgroundTagOffset + i;
        [scrollView addSubview:pillBackground];

        button.backgroundColor = [UIColor clearColor];
        button.frame = pillFrame;
        [scrollView addSubview:button];
        x += itemWidth + spacing;
    }

    scrollView.contentSize = CGSizeMake(x + 15 - spacing, kReactionButtonHeight);
    [cell.contentView addSubview:scrollView];
}

- (UIButton *)reactionAddButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.layer.cornerRadius = kReactionButtonHeight / 2.0;
    button.layer.masksToBounds = YES;
    UIImage *smileyIcon = [GHIconRenderer smileyIconWithColor:GHSecondaryTextColor() size:kReactionButtonHeight * 0.6];
    [button setImage:smileyIcon forState:UIControlStateNormal];
    button.backgroundColor = GHReactionPillBackgroundColor();

    button.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    button.layer.borderColor = GHReactionPillBorderColor().CGColor;
    [button addTarget:self action:@selector(reactionAddButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIButton *)reactionPillButtonWithTitle:(NSString *)title height:(CGFloat)height {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.titleLabel.font = [UIFont systemFontOfSize:15];
    [button setTitle:title forState:UIControlStateNormal];
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    return button;
}

- (void)bounceView:(UIView *)view {
    view.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [UIView animateWithDuration:0.1
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        view.transform = CGAffineTransformMakeScale(1.08, 1.08);
    }
                     completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1
                              delay:0
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            view.transform = CGAffineTransformIdentity;
        }
                         completion:nil];
    }];
}

- (void)reactionPillTapped:(UIButton *)sender {
    NSInteger index = sender.tag - kReactionButtonTagBase;
    NSArray *contents = GHReactionContents();
    if (index < 0 || index >= (NSInteger)contents.count) return;
    [self bounceView:sender];

    UIView *background = [sender.superview viewWithTag:sender.tag + kReactionPillBackgroundTagOffset];
    if (background != nil) {
        [self bounceView:background];
    }
    [self requestReactionForContent:contents[index]];
}

- (void)reactionAddButtonTapped:(UIButton *)sender {
    if (![GHAuthManager sharedManager].isAuthenticated) {
        [self presentLoginRequiredAlert];
        return;
    }
    [self bounceView:sender];
    [self presentReactionPickerFromButton:sender];
}

- (void)presentLoginRequiredAlert {
    UIAlertView *loginAlert = [[UIAlertView alloc] initWithTitle:GHL(@"Нужен вход")
                                                          message:GHL(@"Чтобы оставить реакцию, войдите в аккаунт в настройках.")
                                                         delegate:self
                                                cancelButtonTitle:GHL(@"Отмена")
                                                otherButtonTitles:GHL(@"Войти"), nil];
    loginAlert.tag = kLoginRequiredAlertTag;
    [loginAlert show];
}

#pragma mark - Попап выбора реакции

- (void)presentReactionPickerFromButton:(UIButton *)button {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;

    static const CGFloat kCardWidth = 210;
    static const CGFloat kCellSize = 60;
    static const NSInteger kColumns = 3;
    NSArray *contents = GHReactionContents();
    NSInteger rows = (contents.count + kColumns - 1) / kColumns;
    CGFloat cardHeight = rows * kCellSize + 16;

    UIControl *dimmer = [[UIControl alloc] initWithFrame:window.bounds];
    dimmer.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    dimmer.tag = 9500;
    dimmer.alpha = 0;
    [dimmer addTarget:self action:@selector(dismissReactionPicker) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:dimmer];

    CGRect buttonFrameInWindow = [button convertRect:button.bounds toView:window];
    CGFloat cardX = MIN(MAX(buttonFrameInWindow.origin.x - (kCardWidth - buttonFrameInWindow.size.width) / 2.0, 8),
                         window.bounds.size.width - kCardWidth - 8);
    BOOL showAbove = (buttonFrameInWindow.origin.y + buttonFrameInWindow.size.height + cardHeight + 12) > window.bounds.size.height;
    CGFloat cardY = showAbove
        ? buttonFrameInWindow.origin.y - cardHeight - 8
        : buttonFrameInWindow.origin.y + buttonFrameInWindow.size.height + 8;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(cardX, cardY, kCardWidth, cardHeight)];
    card.tag = 9501;
    card.backgroundColor = GHCellBackgroundColor();
    card.layer.cornerRadius = 14;
    card.layer.masksToBounds = NO;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.3;
    card.layer.shadowRadius = 10;
    card.layer.shadowOffset = CGSizeMake(0, 3);
    card.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [window addSubview:card];

    UIView *clip = [[UIView alloc] initWithFrame:card.bounds];
    clip.layer.cornerRadius = 14;
    clip.layer.masksToBounds = YES;
    clip.backgroundColor = [UIColor clearColor];
    clip.userInteractionEnabled = NO;
    [card addSubview:clip];

    for (NSInteger i = 0; i < contents.count; i++) {
        NSInteger row = i / kColumns;
        NSInteger col = i % kColumns;
        CGRect cellFrame = CGRectMake(col * kCellSize, row * kCellSize + 8, kCellSize, kCellSize);
        BOOL isMine = self.myReactionIDs[contents[i]] != nil;

        if (isMine) {
            static const CGFloat kHighlightInset = 8;
            UIView *highlight = [[UIView alloc] initWithFrame:CGRectInset(cellFrame, kHighlightInset, kHighlightInset)];
            highlight.backgroundColor = GHReactionSelectedBackgroundColor();
            highlight.layer.cornerRadius = (kCellSize - kHighlightInset * 2) / 2.0;
            highlight.layer.masksToBounds = YES;
            highlight.userInteractionEnabled = NO;
            [card addSubview:highlight];
        }

        UIButton *emojiButton = [UIButton buttonWithType:UIButtonTypeCustom];
        emojiButton.frame = cellFrame;
        emojiButton.tag = kReactionButtonTagBase + i;
        emojiButton.titleLabel.font = [UIFont systemFontOfSize:28];
        [emojiButton setTitle:GHReactionEmoji(contents[i]) forState:UIControlStateNormal];
        emojiButton.backgroundColor = [UIColor clearColor];
        [emojiButton addTarget:self action:@selector(reactionPickerEmojiTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:emojiButton];
    }

    [UIView animateWithDuration:0.18 animations:^{
        dimmer.alpha = 1;
        card.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismissReactionPicker {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIView *dimmer = [window viewWithTag:9500];
    UIView *card = [window viewWithTag:9501];
    [UIView animateWithDuration:0.15 animations:^{
        dimmer.alpha = 0;
        card.alpha = 0;
        card.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL finished) {
        [dimmer removeFromSuperview];
        [card removeFromSuperview];
    }];
}

- (void)reactionPickerEmojiTapped:(UIButton *)sender {
    NSInteger index = sender.tag - kReactionButtonTagBase;
    NSArray *contents = GHReactionContents();
    [self dismissReactionPicker];
    if (index < 0 || index >= (NSInteger)contents.count) return;
    [self requestReactionForContent:contents[index]];
}

#pragma mark - Отправка реакции

- (void)requestReactionForContent:(NSString *)content {
    if (![GHAuthManager sharedManager].isAuthenticated) {
        [self presentLoginRequiredAlert];
        return;
    }
    if (self.reactionsActionInProgress) return;
    [self toggleReactionForContent:content];
}

- (void)toggleReactionForContent:(NSString *)content {
    long long releaseID = [self releaseID];
    if (releaseID == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) return;

    id existingReactionID = self.myReactionIDs[content];
    BOOL wasMine = existingReactionID != nil;
    self.reactionsActionInProgress = YES;

    NSMutableDictionary *counts = [self.reactionCounts mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *mine = [self.myReactionIDs mutableCopy] ?: [NSMutableDictionary dictionary];
    NSInteger currentCount = [counts[content] integerValue];
    if (wasMine) {
        counts[content] = @(MAX(0, currentCount - 1));
        [mine removeObjectForKey:content];
    } else {
        counts[content] = @(currentCount + 1);
        mine[content] = @(-1);
    }
    self.reactionCounts = counts;
    self.myReactionIDs = mine;
    [self reloadReactionsRowAnimated];

    __weak typeof(self) weakSelf = self;
    void (^revertWithError)(NSString *) = ^(NSString *message) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.reactionsActionInProgress = NO;

        [strongSelf loadReactions];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось отправить реакцию")
                                                         message:message
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
    };

    if (wasMine) {
        [[GHAPIClient sharedClient] deleteReactionForOwner:self.ownerLogin
                                                        repo:self.repoName
                                                   releaseID:releaseID
                                                  reactionID:[existingReactionID longLongValue]
                                                  completion:^(NSInteger statusCode, NSString *message, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error || statusCode != 204) {
                revertWithError(message.length > 0 ? message : (error.localizedDescription ?: GHL(@"неизвестная ошибка")));
                return;
            }
            strongSelf.reactionsActionInProgress = NO;

        }];
    } else {
        [[GHAPIClient sharedClient] addReactionForOwner:self.ownerLogin
                                                     repo:self.repoName
                                                releaseID:releaseID
                                                  content:content
                                               completion:^(id jsonObject, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                revertWithError(error.localizedDescription ?: GHL(@"неизвестная ошибка"));
                return;
            }
            strongSelf.reactionsActionInProgress = NO;

            id realID = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject[@"id"] : nil;
            if ([realID respondsToSelector:@selector(longLongValue)]) {
                NSMutableDictionary *updatedMine = [strongSelf.myReactionIDs mutableCopy];
                updatedMine[content] = realID;
                strongSelf.myReactionIDs = updatedMine;
            }
        }];
    }
}

- (void)reloadReactionsRowAnimated {
    [UIView transitionWithView:self.tableView
                       duration:0.2
                        options:UIViewAnimationOptionTransitionCrossDissolve
                     animations:^{
        [self.tableView reloadData];
    }
                     completion:nil];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView
    shouldStartLoadWithRequest:(NSURLRequest *)request
                navigationType:(UIWebViewNavigationType)navigationType {
    if ([request.URL.scheme isEqualToString:@"app"] && [request.URL.host isEqualToString:@"release-notes-full"]) {
        if (self.notesFullHTML.length > 0) {
            ReadmeViewController *fullVC = [[ReadmeViewController alloc] init];
            fullVC.html = self.notesFullHTML;
            fullVC.baseURL = self.notesBaseURL;
            fullVC.title = GHL(@"Описание");

            fullVC.titleTranslationKey = @"Описание";
            [self.navigationController pushViewController:fullVC animated:YES];
        }
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {

    if (self.notesWebViewUnloadedForBackground) return;
    NSString *heightString = [self.notesWebView stringByEvaluatingJavaScriptFromString:@"document.body.scrollHeight"];
    CGFloat height = [heightString floatValue];
    if (height <= 0) height = 44;

    if (self.notesIsClipped) {

        static const CGFloat kClippedPreviewMaxHeight = 900.0;
        if (height > kClippedPreviewMaxHeight) height = kClippedPreviewMaxHeight;
    }

    static const CGFloat kMaxInlineHeight = 2600.0;
    if (height > kMaxInlineHeight) height = kMaxInlineHeight;

    self.notesWebViewHeight = height;
    self.notesHTMLReady = YES;

    CGRect frame = self.notesWebView.frame;
    frame.size.height = height;
    self.notesWebView.frame = frame;

    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kSectionNotes) return GHL(@"Описание");
    if (section == kSectionDownloads) return GHL(@"Файлы");
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    if (section == kSectionNotes) return kNotesSectionRowCount;
    if (section == kSectionDownloads) return self.downloadItems.count;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionNotes && indexPath.row == kNotesRowNotes) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NotesCell" forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        CGFloat notesHeight = [self notesContentHeight];

        if (self.notesHTMLReady && self.notesWebView) {
            cell.textLabel.text = nil;
            if (self.notesWebView.superview != cell.contentView) {
                [self.notesWebView removeFromSuperview];
                [cell.contentView addSubview:self.notesWebView];
            }
            CGRect frame = self.notesWebView.frame;
            frame.origin = CGPointMake(10, kNotesVerticalPadding);
            self.notesWebView.frame = frame;
        } else {
            id bodyValue = self.releaseInfo[@"body"];
            BOOL hasBody = [bodyValue isKindOfClass:[NSString class]] && [(NSString *)bodyValue length] > 0;
            cell.textLabel.text = hasBody ? GHL(@"Загрузка описания…") : GHL(@"У этого релиза нет описания");
            cell.textLabel.textColor = GHSecondaryTextColor();
            cell.textLabel.numberOfLines = 0;
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.frame = CGRectMake(15, kNotesVerticalPadding, tableView.bounds.size.width - 30, notesHeight);
        }

        [self layoutReactionButtonsInCell:cell topY:kNotesVerticalPadding + notesHeight];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"AssetCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"AssetCell"];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    GHDownloadItem *item = self.downloadItems[indexPath.row];

    cell.textLabel.text = item.displayName;
    cell.textLabel.textColor = GHPrimaryTextColor();

    if (item.sizeBytes > 0) {
        double sizeMB = (double)item.sizeBytes / (1024.0 * 1024.0);
        cell.detailTextLabel.text = [NSString stringWithFormat:GHL(@"%.2f МБ — нажмите для скачивания"), sizeMB];
    } else {
        cell.detailTextLabel.text = GHL(@"Нажмите для скачивания");
    }
    cell.detailTextLabel.textColor = GHSecondaryTextColor();
    cell.accessoryType = UITableViewCellAccessoryNone;

    // A dequeued cell can be reused for a row that is mid-download, so
    // rebuild the progress view from the model instead of always clearing
    // it - otherwise scrolling the active row offscreen and back loses it.
    if ([indexPath isEqual:self.downloadingIndexPath]) {
        cell.detailTextLabel.text = [NSString stringWithFormat:GHL(@"Скачивание: %.0f%%"), item.downloadProgress * 100];

        UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        progressView.frame = CGRectMake(0, 0, 80, progressView.frame.size.height);
        progressView.progress = item.downloadProgress;
        cell.accessoryView = progressView;
    } else {
        cell.accessoryView = nil;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)notesContentHeight {
    if (self.notesHTMLReady) return self.notesWebViewHeight;

    id bodyValue = self.releaseInfo[@"body"];
    BOOL hasBody = [bodyValue isKindOfClass:[NSString class]] && [(NSString *)bodyValue length] > 0;
    NSString *placeholder = hasBody ? GHL(@"Загрузка описания…") : GHL(@"У этого релиза нет описания");

    CGFloat width = self.tableView.bounds.size.width - 30;
    CGSize size = [placeholder sizeWithFont:[UIFont systemFontOfSize:15]
                           constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                               lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(size.height, 24);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionNotes && indexPath.row == kNotesRowNotes) {
        return (kNotesVerticalPadding * 2) + [self notesContentHeight] + kReactionsRowHeight;
    }
    return 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != kSectionDownloads) return;

    if (self.downloadingIndexPath) {

        return;
    }

    GHDownloadItem *item = self.downloadItems[indexPath.row];
    NSURL *url = [NSURL URLWithString:item.downloadURLString];

    self.downloadingIndexPath = indexPath;
    item.downloadProgress = 0.0;

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.detailTextLabel.text = GHL(@"Скачивание: 0%");

    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.frame = CGRectMake(0, 0, 80, progressView.frame.size.height);
    progressView.progress = 0.0;
    cell.accessoryView = progressView;

    __weak typeof(self) weakSelf = self;
    [[DownloadManager sharedManager] downloadFileAtURL:url
                                                fileName:item.fileName
                                                progress:^(float progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        item.downloadProgress = progress;
        UITableViewCell *progressCell = [strongSelf.tableView cellForRowAtIndexPath:indexPath];
        progressCell.detailTextLabel.text = [NSString stringWithFormat:GHL(@"Скачивание: %.0f%%"), progress * 100];
        UIProgressView *pv = (UIProgressView *)progressCell.accessoryView;
        if ([pv isKindOfClass:[UIProgressView class]]) {
            pv.progress = progress;
        }
    } completion:^(NSString *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        strongSelf.downloadingIndexPath = nil;
        item.downloadProgress = 0.0;

        UITableViewCell *doneCell = [strongSelf.tableView cellForRowAtIndexPath:indexPath];
        doneCell.accessoryView = nil;

        if (error) {
            doneCell.detailTextLabel.text = GHL(@"Ошибка скачивания");
            doneCell.accessoryType = UITableViewCellAccessoryNone;

            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка скачивания")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        } else {
            doneCell.detailTextLabel.text = GHL(@"Сохранено в Media/Downloads");
            doneCell.accessoryType = UITableViewCellAccessoryCheckmark;

            strongSelf.lastDownloadedFilePath = filePath;

            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Скачивание завершено")
                                                             message:filePath
                                                            delegate:strongSelf
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:GHL(@"Открыть"), nil];
            alert.tag = kDownloadCompleteAlertTag;
            [alert show];
        }
    }];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView.tag == kLoginRequiredAlertTag) {
        if (alertView.cancelButtonIndex == buttonIndex) return;
        SettingsViewController *settingsVC = [[SettingsViewController alloc] init];
        [self.navigationController pushViewController:settingsVC animated:YES];
        return;
    }

    if (alertView.tag != kDownloadCompleteAlertTag) return;
    if (alertView.cancelButtonIndex == buttonIndex) return;
    if (self.lastDownloadedFilePath.length == 0) return;

    [self presentOpenInMenuForDownloadedFile];
}

- (void)presentOpenInMenuForDownloadedFile {
    NSString *encodedPath = [self.lastDownloadedFilePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: self.lastDownloadedFilePath;

    NSURL *iFileURL = [NSURL URLWithString:[NSString stringWithFormat:@"ifile://%@", encodedPath]];
    if (iFileURL && [[UIApplication sharedApplication] canOpenURL:iFileURL]) {
        [[UIApplication sharedApplication] openURL:iFileURL];
        return;
    }

    NSURL *filzaURL = [NSURL URLWithString:[NSString stringWithFormat:@"filza://view%@", encodedPath]];
    if (filzaURL && [[UIApplication sharedApplication] canOpenURL:filzaURL]) {
        [[UIApplication sharedApplication] openURL:filzaURL];
        return;
    }

    [self presentSystemOpenInMenuForDownloadedFile];
}

- (void)presentSystemOpenInMenuForDownloadedFile {
    NSURL *fileURL = [NSURL fileURLWithPath:self.lastDownloadedFilePath];

    self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
    self.documentInteractionController.delegate = self;

    BOOL didPresent = [self.documentInteractionController presentOpenInMenuFromRect:self.view.bounds
                                                                                inView:self.view
                                                                              animated:YES];
    if (!didPresent) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Нет подходящих приложений")
                                                         message:GHL(@"На устройстве не нашлось приложения, заявившего поддержку этого типа файлов.")
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
    }
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self;
}

@end
