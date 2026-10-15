#import "ReleaseDetailViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
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
#import "GHAvatarLoader.h"
#import "PublicProfileViewController.h"
#import "CommitDetailViewController.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, GHReleaseSectionKind) {
    GHReleaseSectionKindHeader = 0,
    GHReleaseSectionKindNotes,
    GHReleaseSectionKindContributors,
    GHReleaseSectionKindInfo,
    GHReleaseSectionKindAssets
};

typedef NS_ENUM(NSInteger, GHReleaseInfoRow) {
    GHReleaseInfoRowCommit = 0,
    GHReleaseInfoRowTag
};

typedef NS_ENUM(NSInteger, GHDownloadState) {
    GHDownloadStateIdle = 0,
    GHDownloadStateDownloading,
    GHDownloadStateSaved,
    GHDownloadStateFailed
};

static const NSInteger kDownloadCompleteAlertTag = 1;
static const NSInteger kLoginRequiredAlertTag = 2;

static NSArray *GHReactionContents(void) {
    return @[@"+1", @"laugh", @"hooray", @"heart", @"rocket", @"eyes"];
}

static NSString *GHReactionEmoji(NSString *content) {
    if ([content isEqualToString:@"+1"]) return @"👍";
    if ([content isEqualToString:@"laugh"]) return @"😄";
    if ([content isEqualToString:@"hooray"]) return @"🎉";
    if ([content isEqualToString:@"heart"]) return GHEmojiForDisplay(@"❤️");
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
@property (nonatomic, assign) GHDownloadState state;
@property (nonatomic, assign) BOOL isSourceArchive;
@end

@implementation GHDownloadItem
@end

@interface ReleaseDetailViewController () <UIActionSheetDelegate>
@property (nonatomic, strong) NSArray *downloadItems;
@property (nonatomic, strong) NSArray *sectionKinds;
@property (nonatomic, strong) NSArray *contributors;
@property (nonatomic, assign) BOOL contributorsExpanded;
@property (nonatomic, assign) BOOL isLatestRelease;
@property (nonatomic, assign) NSInteger actionSheetItemIndex;
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

    [self.tableView gh_registerCellClass:[UITableViewCell class] forCellReuseIdentifier:@"NotesCell"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 24)];
    self.reactionCounts = [NSMutableDictionary dictionary];
    self.myReactionIDs = [NSMutableDictionary dictionary];
    self.actionSheetItemIndex = -1;
    [self buildDownloadItems];
    [self buildContributors];
    [self rebuildSections];
    [self loadReleaseNotesHTML];
    [self loadReactions];
    [self checkLatestRelease];

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
    [self buildContributors];
    [self rebuildSections];
    [self loadReleaseNotesHTML];
    [self.tableView reloadData];
}

- (void)handlePullToRefresh {
    long long releaseID = [self releaseID];
    if (releaseID == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) {
        if (GHPullToRefreshAvailable()) { [self.refreshControl endRefreshing]; } else { [self.gh_legacyRefreshControl endRefreshing]; }
        return;
    }

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] releaseForOwner:self.ownerLogin
                                            repo:self.repoName
                                       releaseID:releaseID
                                      completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }

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
        [strongSelf buildContributors];
        [strongSelf rebuildSections];
        [strongSelf loadReleaseNotesHTML];
        [strongSelf loadReactions];
        [strongSelf checkLatestRelease];
        [strongSelf.tableView reloadData];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.notesWebView.delegate = nil;
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHCellBackgroundColor();

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

    NSArray *assets = [self.releaseInfo[@"assets"] isKindOfClass:[NSArray class]] ? self.releaseInfo[@"assets"] : @[];
    for (NSDictionary *asset in assets) {
        if (![asset isKindOfClass:[NSDictionary class]]) continue;
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
        item.isSourceArchive = YES;
        item.fileName = [NSString stringWithFormat:@"source-%@.zip", tagName];
        item.downloadURLString = zipURL;
        item.sizeBytes = 0;
        [items addObject:item];
    }
    if (tarURL.length > 0) {
        GHDownloadItem *item = [[GHDownloadItem alloc] init];
        item.displayName = GHL(@"Исходный код (tar.gz)");
        item.isSourceArchive = YES;
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

                [NSString stringWithFormat:@"<div class=\"readme-clip\">%@</div><a href=\"app://release-notes-full\" class=\"show-more\">%@<span class=\"show-more-chev\"></span></a>",
                    previewBodyHTML, GHL(@"Читать полностью")]
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

#pragma mark - Helpers (новый дизайн)

static const CGFloat kReleaseSidePadding = 16.0;
static const CGFloat kReleaseSectionHeaderHeight = 56.0;
static const CGFloat kReleaseContributorRowHeight = 64.0;
static const CGFloat kReleaseViewAllRowHeight = 72.0;
static const CGFloat kReleaseInfoRowHeight = 56.0;
static const CGFloat kReleaseAssetRowHeight = 84.0;
static const CGFloat kReleaseAssetCompactRowHeight = 60.0;
static const NSInteger kReleaseContributorsPreviewCount = 5;

static const NSInteger kHeaderOwnerAvatarTag = 7101;
static const NSInteger kHeaderRepoLabelTag = 7102;
static const NSInteger kHeaderTitleLabelTag = 7103;
static const NSInteger kHeaderBadgeLabelTag = 7104;
static const NSInteger kHeaderAuthorAvatarTag = 7105;
static const NSInteger kHeaderAuthorLoginTag = 7106;
static const NSInteger kHeaderReleasedLabelTag = 7107;

static const NSInteger kContributorAvatarTag = 7201;
static const NSInteger kContributorLoginTag = 7202;
static const NSInteger kViewAllTitleTag = 7211;
static const NSInteger kViewAllSubtitleTag = 7212;
static const NSInteger kViewAllHairlineTag = 7213;

static const NSInteger kInfoIconTag = 7301;
static const NSInteger kInfoLabelTag = 7302;

static const NSInteger kAssetIconTag = 7401;
static const NSInteger kAssetNameTag = 7402;
static const NSInteger kAssetPillTag = 7403;
static const NSInteger kAssetPillIconTag = 7404;
static const NSInteger kAssetPillLabelTag = 7405;
static const NSInteger kAssetMoreButtonTag = 7406;

static NSString *GHReleaseString(NSDictionary *dict, NSString *key) {
    id value = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static BOOL GHReleaseFlag(NSDictionary *dict, NSString *key) {
    id value = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static UIColor *GHReleaseBadgeLatestColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.25 green:0.73 blue:0.31 alpha:1.0]
        : [UIColor colorWithRed:0.10 green:0.50 blue:0.22 alpha:1.0];
}

static UIColor *GHReleaseBadgePreReleaseColor(void) {
    return [GHThemeManager sharedManager].darkModeEnabled
        ? [UIColor colorWithRed:0.86 green:0.48 blue:0.15 alpha:1.0]
        : [UIColor colorWithRed:0.74 green:0.34 blue:0.00 alpha:1.0];
}

static NSString *GHReleaseFormattedSize(long long bytes) {
    if (bytes < 1024) return [NSString stringWithFormat:@"%lld %@", bytes, GHL(@"байт")];
    double kb = (double)bytes / 1024.0;
    if (kb < 1024.0) return [NSString stringWithFormat:@"%.0f %@", kb, GHL(@"КБ")];
    double mb = kb / 1024.0;
    if (mb < 10.0) return [NSString stringWithFormat:@"%.1f %@", mb, GHL(@"МБ")];
    if (mb < 1024.0) return [NSString stringWithFormat:@"%.0f %@", mb, GHL(@"МБ")];
    return [NSString stringWithFormat:@"%.2f %@", mb / 1024.0, GHL(@"ГБ")];
}

static NSString *GHReleaseDateString(NSString *isoString) {
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

    BOOL russian = [[GHLocalization sharedManager].languageCode isEqualToString:@"ru"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSInteger year = [[calendar components:NSYearCalendarUnit fromDate:date] year];
    NSInteger currentYear = [[calendar components:NSYearCalendarUnit fromDate:[NSDate date]] year];
    BOOL sameYear = (year == currentYear);

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:russian ? @"ru_RU" : @"en_US"];
    if (russian) {
        formatter.dateFormat = sameYear ? @"d MMMM" : @"d MMMM yyyy";
    } else {
        formatter.dateFormat = sameYear ? @"MMM d" : @"MMM d, yyyy";
    }
    return [formatter stringFromDate:date];
}

static NSString *GHReleaseAvatarURLForLogin(NSString *login) {
    if (login.length == 0) return nil;
    NSString *escaped = [login stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: login;
    return [NSString stringWithFormat:@"https://avatars.githubusercontent.com/%@?s=96", escaped];
}

static UILabel *GHReleaseLabel(UIView *container, NSInteger tag) {
    UILabel *label = (UILabel *)[container viewWithTag:tag];
    if (![label isKindOfClass:[UILabel class]]) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = tag;
        label.backgroundColor = [UIColor clearColor];
        [container addSubview:label];
    }
    return label;
}

static UIImageView *GHReleaseImageView(UIView *container, NSInteger tag, CGFloat cornerRadius) {
    UIImageView *imageView = (UIImageView *)[container viewWithTag:tag];
    if (![imageView isKindOfClass:[UIImageView class]]) {
        imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        imageView.tag = tag;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.layer.cornerRadius = cornerRadius;
        imageView.layer.masksToBounds = cornerRadius > 0;
        [container addSubview:imageView];
    }
    return imageView;
}

static void GHReleaseLoadAvatar(UIImageView *imageView, NSString *urlString) {
    if (urlString.length == 0) {
        imageView.image = nil;
        imageView.accessibilityLabel = nil;
        return;
    }
    if ([imageView.accessibilityLabel isEqualToString:urlString] && imageView.image != nil) return;
    imageView.accessibilityLabel = urlString;
    imageView.image = nil;
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:urlString intoImageView:imageView];
    // Загрузчик ставит contentMode = Center под 30-pt картинку; растягиваем под наш размер.
    imageView.contentMode = UIViewContentModeScaleAspectFill;
}

#pragma mark - Sections

- (void)rebuildSections {
    NSMutableArray *kinds = [NSMutableArray arrayWithObjects:@(GHReleaseSectionKindHeader), @(GHReleaseSectionKindNotes), nil];
    if (self.contributors.count > 0) [kinds addObject:@(GHReleaseSectionKindContributors)];
    if ([self infoRows].count > 0) [kinds addObject:@(GHReleaseSectionKindInfo)];
    if (self.downloadItems.count > 0) [kinds addObject:@(GHReleaseSectionKindAssets)];
    self.sectionKinds = kinds;
}

- (GHReleaseSectionKind)kindForSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sectionKinds.count) return GHReleaseSectionKindHeader;
    return (GHReleaseSectionKind)[self.sectionKinds[section] integerValue];
}

- (NSInteger)sectionForKind:(GHReleaseSectionKind)kind {
    NSUInteger index = [self.sectionKinds indexOfObject:@(kind)];
    return index == NSNotFound ? -1 : (NSInteger)index;
}

- (void)buildContributors {
    NSString *body = GHReleaseString(self.releaseInfo, @"body");
    if (body.length == 0) {
        self.contributors = @[];
        return;
    }

    static NSRegularExpression *mentionRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mentionRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<![A-Za-z0-9_./@`-])@([A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38})(?![A-Za-z0-9_/-])"
                                                                  options:0
                                                                    error:nil];
    });

    NSMutableArray *logins = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSArray *matches = [mentionRegex matchesInString:body options:0 range:NSMakeRange(0, body.length)];
    for (NSTextCheckingResult *match in matches) {
        if (match.numberOfRanges < 2) continue;
        NSString *login = [body substringWithRange:[match rangeAtIndex:1]];
        NSString *key = login.lowercaseString;
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [logins addObject:login];
    }
    self.contributors = logins;
}

- (NSArray *)infoRows {
    NSMutableArray *rows = [NSMutableArray array];
    if (GHReleaseString(self.releaseInfo, @"target_commitish").length > 0) [rows addObject:@(GHReleaseInfoRowCommit)];
    if (GHReleaseString(self.releaseInfo, @"tag_name").length > 0) [rows addObject:@(GHReleaseInfoRowTag)];
    return rows;
}

- (BOOL)targetIsCommitSHA {
    NSString *target = GHReleaseString(self.releaseInfo, @"target_commitish");
    if (target.length < 7 || target.length > 40) return NO;
    NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet];
    return [target rangeOfCharacterFromSet:nonHex].location == NSNotFound;
}

- (NSInteger)visibleContributorCount {
    if (self.contributorsExpanded) return self.contributors.count;
    return MIN((NSInteger)self.contributors.count, kReleaseContributorsPreviewCount);
}

- (BOOL)showsViewAllContributorsRow {
    return !self.contributorsExpanded && (NSInteger)self.contributors.count > kReleaseContributorsPreviewCount;
}

#pragma mark - Latest release badge

- (void)checkLatestRelease {
    self.isLatestRelease = NO;
    if (GHReleaseFlag(self.releaseInfo, @"draft") || GHReleaseFlag(self.releaseInfo, @"prerelease")) return;
    long long releaseID = [self releaseID];
    if (releaseID == 0 || self.ownerLogin.length == 0 || self.repoName.length == 0) return;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] latestReleaseForOwner:self.ownerLogin repo:self.repoName completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || ![jsonObject isKindOfClass:[NSDictionary class]]) return;
        id latestID = jsonObject[@"id"];
        BOOL isLatest = [latestID respondsToSelector:@selector(longLongValue)] && [latestID longLongValue] == [strongSelf releaseID];
        if (isLatest == strongSelf.isLatestRelease) return;
        strongSelf.isLatestRelease = isLatest;
        [strongSelf.tableView reloadData];
    }];
}

- (NSString *)badgeText {
    if (GHReleaseFlag(self.releaseInfo, @"draft")) return GHL(@"Черновик");
    if (GHReleaseFlag(self.releaseInfo, @"prerelease")) return GHL(@"Пре-релиз");
    if (self.isLatestRelease) return GHL(@"Последний релиз");
    return nil;
}

- (UIColor *)badgeColor {
    if (GHReleaseFlag(self.releaseInfo, @"draft")) return GHSecondaryTextColor();
    if (GHReleaseFlag(self.releaseInfo, @"prerelease")) return GHReleaseBadgePreReleaseColor();
    return GHReleaseBadgeLatestColor();
}

#pragma mark - Header layout

// Один и тот же код и меряет высоту (container == nil), и раскладывает вьюхи.
- (CGFloat)layoutHeaderInView:(UIView *)container width:(CGFloat)width {
    CGFloat textWidth = width - kReleaseSidePadding * 2;
    CGFloat y = 18;

    NSString *repoText = (self.ownerLogin.length > 0 && self.repoName.length > 0)
        ? [NSString stringWithFormat:@"%@ / %@", self.ownerLogin, self.repoName]
        : @"";
    if (repoText.length > 0) {
        if (container) {
            UIImageView *ownerAvatar = GHReleaseImageView(container, kHeaderOwnerAvatarTag, 12);
            ownerAvatar.frame = CGRectMake(kReleaseSidePadding, y, 24, 24);
            ownerAvatar.backgroundColor = GHReactionPillBackgroundColor();
            GHReleaseLoadAvatar(ownerAvatar, GHReleaseAvatarURLForLogin(self.ownerLogin));

            UILabel *repoLabel = GHReleaseLabel(container, kHeaderRepoLabelTag);
            repoLabel.font = [UIFont systemFontOfSize:16];
            repoLabel.textColor = GHSecondaryTextColor();
            repoLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            repoLabel.text = repoText;
            repoLabel.frame = CGRectMake(kReleaseSidePadding + 34, y + 2, textWidth - 34, 20);
        }
        y += 24 + 14;
    }

    NSString *name = GHReleaseString(self.releaseInfo, @"name");
    NSString *tag = GHReleaseString(self.releaseInfo, @"tag_name");
    NSString *titleText = name.length > 0 ? name : (tag.length > 0 ? tag : GHL(@"Релиз"));
    UIFont *titleFont = [UIFont boldSystemFontOfSize:30];
    CGSize titleSize = [titleText sizeWithFont:titleFont
                             constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                 lineBreakMode:NSLineBreakByWordWrapping];
    if (container) {
        UILabel *titleLabel = GHReleaseLabel(container, kHeaderTitleLabelTag);
        titleLabel.font = titleFont;
        titleLabel.textColor = GHPrimaryTextColor();
        titleLabel.numberOfLines = 0;
        titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        titleLabel.text = titleText;
        titleLabel.frame = CGRectMake(kReleaseSidePadding, y, textWidth, ceil(titleSize.height));
    }
    y += ceil(titleSize.height) + 12;

    NSString *badge = [self badgeText];
    UILabel *badgeLabel = container ? GHReleaseLabel(container, kHeaderBadgeLabelTag) : nil;
    if (badge.length > 0) {
        UIFont *badgeFont = [UIFont systemFontOfSize:16];
        CGSize badgeSize = [badge sizeWithFont:badgeFont];
        if (badgeLabel) {
            UIColor *color = [self badgeColor];
            badgeLabel.hidden = NO;
            badgeLabel.font = badgeFont;
            badgeLabel.textAlignment = NSTextAlignmentCenter;
            badgeLabel.text = badge;
            badgeLabel.textColor = color;
            badgeLabel.backgroundColor = [color colorWithAlphaComponent:0.14];
            badgeLabel.layer.cornerRadius = 8;
            badgeLabel.layer.masksToBounds = YES;
            badgeLabel.layer.borderWidth = 1.0;
            badgeLabel.layer.borderColor = [color colorWithAlphaComponent:0.45].CGColor;
            badgeLabel.frame = CGRectMake(kReleaseSidePadding, y, MIN(ceil(badgeSize.width) + 24, textWidth), 32);
        }
        y += 32 + 16;
    } else {
        badgeLabel.hidden = YES;
    }

    NSDictionary *author = [self.releaseInfo[@"author"] isKindOfClass:[NSDictionary class]] ? self.releaseInfo[@"author"] : nil;
    NSString *authorLogin = GHReleaseString(author, @"login");
    NSString *dateText = GHReleaseDateString(GHReleaseString(self.releaseInfo, @"published_at"));
    if (dateText.length == 0) dateText = GHReleaseDateString(GHReleaseString(self.releaseInfo, @"created_at"));

    UIImageView *authorAvatar = container ? GHReleaseImageView(container, kHeaderAuthorAvatarTag, 14) : nil;
    UILabel *loginLabel = container ? GHReleaseLabel(container, kHeaderAuthorLoginTag) : nil;
    UILabel *releasedLabel = container ? GHReleaseLabel(container, kHeaderReleasedLabelTag) : nil;

    if (authorLogin.length > 0 || dateText.length > 0) {
        if (container) {
            CGFloat x = kReleaseSidePadding;
            authorAvatar.hidden = authorLogin.length == 0;
            loginLabel.hidden = authorLogin.length == 0;
            if (authorLogin.length > 0) {
                authorAvatar.frame = CGRectMake(x, y, 28, 28);
                authorAvatar.backgroundColor = GHReactionPillBackgroundColor();
                NSString *avatarURL = GHReleaseString(author, @"avatar_url");
                GHReleaseLoadAvatar(authorAvatar, avatarURL.length > 0 ? avatarURL : GHReleaseAvatarURLForLogin(authorLogin));
                x += 28 + 10;

                loginLabel.font = [UIFont boldSystemFontOfSize:16];
                loginLabel.textColor = GHPrimaryTextColor();
                loginLabel.text = authorLogin;
                CGSize loginSize = [authorLogin sizeWithFont:loginLabel.font];
                CGFloat loginWidth = MIN(ceil(loginSize.width), width - kReleaseSidePadding - x);
                loginLabel.frame = CGRectMake(x, y + 4, loginWidth, 20);
                x += loginWidth + 5;
            }

            releasedLabel.hidden = dateText.length == 0;
            releasedLabel.font = [UIFont systemFontOfSize:16];
            releasedLabel.textColor = GHSecondaryTextColor();
            releasedLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            releasedLabel.text = [NSString stringWithFormat:GHL(@"опубликовал(а) %@"), dateText];
            releasedLabel.frame = CGRectMake(x, y + 4, MAX(0, width - kReleaseSidePadding - x), 20);
        }
        y += 28 + 18;
    } else if (container) {
        authorAvatar.hidden = YES;
        loginLabel.hidden = YES;
        releasedLabel.hidden = YES;
    }

    return y;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sectionKinds.count;
}

- (NSString *)titleForSectionKind:(GHReleaseSectionKind)kind {
    switch (kind) {
        case GHReleaseSectionKindContributors: return GHL(@"Участники");
        case GHReleaseSectionKindInfo: return GHL(@"Информация");
        case GHReleaseSectionKindAssets: return GHL(@"Файлы релиза");
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForSectionKind:[self kindForSection:section]];
    if (title.length == 0) return nil;

    CGFloat width = tableView.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kReleaseSectionHeaderHeight)];
    header.backgroundColor = GHCellBackgroundColor();

    CGFloat hairline = 1.0 / [UIScreen mainScreen].scale;
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, hairline)];
    line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    line.backgroundColor = GHSeparatorColor();
    [header addSubview:line];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kReleaseSidePadding, 24, width - kReleaseSidePadding * 2, 22)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = GHSecondaryTextColor();
    label.text = title;
    [header addSubview:label];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *title = [self titleForSectionKind:[self kindForSection:section]];
    return title.length > 0 ? kReleaseSectionHeaderHeight : 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self kindForSection:section]) {
        case GHReleaseSectionKindHeader: return 1;
        case GHReleaseSectionKindNotes: return 1;
        case GHReleaseSectionKindContributors:
            return [self visibleContributorCount] + ([self showsViewAllContributorsRow] ? 1 : 0);
        case GHReleaseSectionKindInfo: return [self infoRows].count;
        case GHReleaseSectionKindAssets: return self.downloadItems.count;
    }
    return 0;
}

- (UITableViewCell *)plainCellForTableView:(UITableView *)tableView identifier:(NSString *)identifier {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    }
    cell.backgroundColor = GHCellBackgroundColor();
    cell.contentView.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHReleaseSectionKind kind = [self kindForSection:indexPath.section];
    CGFloat width = tableView.bounds.size.width;

    if (kind == GHReleaseSectionKindHeader) {
        UITableViewCell *cell = [self plainCellForTableView:tableView identifier:@"ReleaseHeaderCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [self layoutHeaderInView:cell.contentView width:width];
        return cell;
    }

    if (kind == GHReleaseSectionKindNotes) {
        UITableViewCell *cell = [tableView gh_dequeueCellWithIdentifier:@"NotesCell" forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.contentView.backgroundColor = GHCellBackgroundColor();
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
            cell.textLabel.backgroundColor = [UIColor clearColor];
            cell.textLabel.textColor = GHSecondaryTextColor();
            cell.textLabel.numberOfLines = 0;
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.frame = CGRectMake(kReleaseSidePadding, kNotesVerticalPadding, width - kReleaseSidePadding * 2, notesHeight);
        }

        [self layoutReactionButtonsInCell:cell topY:kNotesVerticalPadding + notesHeight];
        return cell;
    }

    if (kind == GHReleaseSectionKindContributors) {
        if (indexPath.row >= [self visibleContributorCount]) {
            UITableViewCell *cell = [self plainCellForTableView:tableView identifier:@"ReleaseViewAllCell"];
            cell.selectionStyle = UITableViewCellSelectionStyleGray;

            CGFloat hairline = 1.0 / [UIScreen mainScreen].scale;
            UIView *line = [cell.contentView viewWithTag:kViewAllHairlineTag];
            if (!line) {
                line = [[UIView alloc] initWithFrame:CGRectZero];
                line.tag = kViewAllHairlineTag;
                [cell.contentView addSubview:line];
            }
            line.backgroundColor = GHSeparatorColor();
            line.frame = CGRectMake(72, 0, width - 72, hairline);

            UILabel *title = GHReleaseLabel(cell.contentView, kViewAllTitleTag);
            title.font = [UIFont systemFontOfSize:18];
            title.textColor = GHPrimaryTextColor();
            title.text = GHL(@"Показать всех");
            title.frame = CGRectMake(72, 14, width - 72 - kReleaseSidePadding, 24);

            UILabel *subtitle = GHReleaseLabel(cell.contentView, kViewAllSubtitleTag);
            subtitle.font = [UIFont systemFontOfSize:15];
            subtitle.textColor = GHSecondaryTextColor();
            subtitle.text = [NSString stringWithFormat:GHL(@"Участников: %ld"), (long)self.contributors.count];
            subtitle.frame = CGRectMake(72, 40, width - 72 - kReleaseSidePadding, 20);
            return cell;
        }

        UITableViewCell *cell = [self plainCellForTableView:tableView identifier:@"ReleaseContributorCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        NSString *login = self.contributors[indexPath.row];

        UIImageView *avatar = GHReleaseImageView(cell.contentView, kContributorAvatarTag, 20);
        avatar.backgroundColor = GHReactionPillBackgroundColor();
        avatar.frame = CGRectMake(kReleaseSidePadding, (kReleaseContributorRowHeight - 40) / 2.0, 40, 40);
        GHReleaseLoadAvatar(avatar, GHReleaseAvatarURLForLogin(login));

        UILabel *loginLabel = GHReleaseLabel(cell.contentView, kContributorLoginTag);
        loginLabel.font = [UIFont systemFontOfSize:18];
        loginLabel.textColor = GHPrimaryTextColor();
        loginLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        loginLabel.text = login;
        loginLabel.frame = CGRectMake(72, (kReleaseContributorRowHeight - 24) / 2.0, width - 72 - kReleaseSidePadding, 24);
        return cell;
    }

    if (kind == GHReleaseSectionKindInfo) {
        UITableViewCell *cell = [self plainCellForTableView:tableView identifier:@"ReleaseInfoCell"];
        NSArray *rows = [self infoRows];
        GHReleaseInfoRow row = (GHReleaseInfoRow)[rows[indexPath.row] integerValue];

        UIImageView *icon = GHReleaseImageView(cell.contentView, kInfoIconTag, 0);
        icon.contentMode = UIViewContentModeCenter;
        icon.frame = CGRectMake(kReleaseSidePadding, (kReleaseInfoRowHeight - 24) / 2.0, 24, 24);

        UILabel *label = GHReleaseLabel(cell.contentView, kInfoLabelTag);
        label.font = [UIFont systemFontOfSize:18];
        label.textColor = GHSecondaryTextColor();
        label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        label.frame = CGRectMake(56, (kReleaseInfoRowHeight - 24) / 2.0, width - 56 - kReleaseSidePadding, 24);

        if (row == GHReleaseInfoRowCommit) {
            NSString *target = GHReleaseString(self.releaseInfo, @"target_commitish");
            BOOL isSHA = [self targetIsCommitSHA];
            icon.image = isSHA ? [GHIconRenderer commitIconWithColor:GHSecondaryTextColor() size:22]
                               : [GHIconRenderer branchIconWithColor:GHSecondaryTextColor() size:22];
            label.text = (isSHA && target.length > 7) ? [target substringToIndex:7] : target;
            cell.selectionStyle = isSHA ? UITableViewCellSelectionStyleGray : UITableViewCellSelectionStyleNone;
        } else {
            icon.image = [GHIconRenderer tagIconWithColor:GHSecondaryTextColor() size:22];
            label.text = GHReleaseString(self.releaseInfo, @"tag_name");
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        return cell;
    }

    UITableViewCell *cell = [self plainCellForTableView:tableView identifier:@"ReleaseAssetCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    [self configureAssetCell:cell atRow:indexPath.row width:width];
    return cell;
}

- (NSString *)pillTextForItem:(GHDownloadItem *)item {
    switch (item.state) {
        case GHDownloadStateDownloading:
            return [NSString stringWithFormat:GHL(@"Скачивание: %.0f%%"), item.downloadProgress * 100];
        case GHDownloadStateSaved:
            return GHL(@"Сохранено");
        case GHDownloadStateFailed:
            return GHL(@"Ошибка скачивания");
        case GHDownloadStateIdle:
            break;
    }
    return item.sizeBytes > 0 ? GHReleaseFormattedSize(item.sizeBytes) : nil;
}

- (CGFloat)heightForAssetItem:(GHDownloadItem *)item {
    return [self pillTextForItem:item].length > 0 ? kReleaseAssetRowHeight : kReleaseAssetCompactRowHeight;
}

- (void)configureAssetCell:(UITableViewCell *)cell atRow:(NSInteger)row width:(CGFloat)width {
    if (row < 0 || row >= (NSInteger)self.downloadItems.count) return;
    GHDownloadItem *item = self.downloadItems[row];
    NSString *pillText = [self pillTextForItem:item];
    BOOL hasPill = pillText.length > 0;
    CGFloat rowHeight = hasPill ? kReleaseAssetRowHeight : kReleaseAssetCompactRowHeight;

    UIImageView *icon = GHReleaseImageView(cell.contentView, kAssetIconTag, 0);
    icon.contentMode = UIViewContentModeCenter;
    UIImage *fileIcon = item.isSourceArchive
        ? [GHIconRenderer codeIconWithColor:GHSecondaryTextColor() size:22]
        : [GHIconRenderer fileZipIconWithColor:GHSecondaryTextColor() size:24];
    icon.image = fileIcon;
    icon.frame = CGRectMake(kReleaseSidePadding, hasPill ? 16 : (rowHeight - 26) / 2.0, 26, 26);

    CGFloat moreSize = 44;
    UIButton *moreButton = (UIButton *)[cell.contentView viewWithTag:kAssetMoreButtonTag];
    if (![moreButton isKindOfClass:[UIButton class]]) {
        moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
        moreButton.tag = kAssetMoreButtonTag;
        [moreButton addTarget:self action:@selector(assetMoreButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:moreButton];
    }
    [moreButton setImage:[GHIconRenderer moreIconWithColor:GHSecondaryTextColor() size:22] forState:UIControlStateNormal];
    moreButton.frame = CGRectMake(width - moreSize - 6, hasPill ? 8 : (rowHeight - moreSize) / 2.0, moreSize, moreSize);

    CGFloat textX = 56;
    CGFloat textWidth = width - textX - moreSize - 10;
    UILabel *nameLabel = GHReleaseLabel(cell.contentView, kAssetNameTag);
    nameLabel.font = [UIFont systemFontOfSize:17];
    nameLabel.textColor = GHPrimaryTextColor();
    nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    nameLabel.text = item.displayName;
    nameLabel.frame = CGRectMake(textX, hasPill ? 18 : (rowHeight - 22) / 2.0, textWidth, 22);

    UIView *pill = [cell.contentView viewWithTag:kAssetPillTag];
    if (!pill) {
        pill = [[UIView alloc] initWithFrame:CGRectZero];
        pill.tag = kAssetPillTag;
        pill.userInteractionEnabled = NO;
        pill.layer.cornerRadius = 12;
        pill.layer.masksToBounds = YES;
        [cell.contentView addSubview:pill];
    }
    pill.hidden = !hasPill;
    if (!hasPill) return;

    pill.backgroundColor = GHReactionPillBackgroundColor();
    UIColor *pillTextColor = item.state == GHDownloadStateSaved ? GHReleaseBadgeLatestColor()
                           : (item.state == GHDownloadStateFailed ? [UIColor colorWithRed:0.85 green:0.25 blue:0.22 alpha:1.0]
                                                                  : GHSecondaryTextColor());

    UIImageView *pillIcon = GHReleaseImageView(pill, kAssetPillIconTag, 0);
    pillIcon.contentMode = UIViewContentModeCenter;
    pillIcon.image = [GHIconRenderer fileZipIconWithColor:pillTextColor size:13];
    pillIcon.frame = CGRectMake(9, 5, 14, 14);

    UILabel *pillLabel = GHReleaseLabel(pill, kAssetPillLabelTag);
    pillLabel.font = [UIFont systemFontOfSize:14];
    pillLabel.textColor = pillTextColor;
    pillLabel.text = pillText;
    CGSize pillTextSize = [pillText sizeWithFont:pillLabel.font];
    CGFloat pillWidth = MIN(ceil(pillTextSize.width) + 9 + 14 + 6 + 10, textWidth);
    pillLabel.frame = CGRectMake(9 + 14 + 6, 3, pillWidth - (9 + 14 + 6) - 10, 18);
    pill.frame = CGRectMake(textX, 48, pillWidth, 24);
}

- (void)refreshAssetRowForItem:(GHDownloadItem *)item {
    NSInteger section = [self sectionForKind:GHReleaseSectionKindAssets];
    NSUInteger row = [self.downloadItems indexOfObject:item];
    if (section < 0 || row == NSNotFound) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (cell) [self configureAssetCell:cell atRow:row width:self.tableView.bounds.size.width];
}

- (void)reloadAssetRowForItem:(GHDownloadItem *)item {
    NSInteger section = [self sectionForKind:GHReleaseSectionKindAssets];
    NSUInteger row = [self.downloadItems indexOfObject:item];
    if (section < 0 || row == NSNotFound) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDelegate

- (CGFloat)notesContentHeight {
    if (self.notesHTMLReady) return self.notesWebViewHeight;

    id bodyValue = self.releaseInfo[@"body"];
    BOOL hasBody = [bodyValue isKindOfClass:[NSString class]] && [(NSString *)bodyValue length] > 0;
    NSString *placeholder = hasBody ? GHL(@"Загрузка описания…") : GHL(@"У этого релиза нет описания");

    CGFloat width = self.tableView.bounds.size.width - kReleaseSidePadding * 2;
    CGSize size = [placeholder sizeWithFont:[UIFont systemFontOfSize:15]
                           constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                               lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(size.height, 24);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self kindForSection:indexPath.section]) {
        case GHReleaseSectionKindHeader:
            return [self layoutHeaderInView:nil width:tableView.bounds.size.width];
        case GHReleaseSectionKindNotes:
            return (kNotesVerticalPadding * 2) + [self notesContentHeight] + kReactionsRowHeight;
        case GHReleaseSectionKindContributors:
            return indexPath.row >= [self visibleContributorCount] ? kReleaseViewAllRowHeight : kReleaseContributorRowHeight;
        case GHReleaseSectionKindInfo:
            return kReleaseInfoRowHeight;
        case GHReleaseSectionKindAssets:
            if (indexPath.row < (NSInteger)self.downloadItems.count) {
                return [self heightForAssetItem:self.downloadItems[indexPath.row]];
            }
            return kReleaseAssetRowHeight;
    }
    return 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    GHReleaseSectionKind kind = [self kindForSection:indexPath.section];

    if (kind == GHReleaseSectionKindContributors) {
        if (indexPath.row >= [self visibleContributorCount]) {
            self.contributorsExpanded = YES;
            [tableView reloadSections:[NSIndexSet indexSetWithIndex:indexPath.section] withRowAnimation:UITableViewRowAnimationFade];
            return;
        }
        PublicProfileViewController *profileVC = [[PublicProfileViewController alloc] init];
        profileVC.login = self.contributors[indexPath.row];
        [self.navigationController pushViewController:profileVC animated:YES];
        return;
    }

    if (kind == GHReleaseSectionKindInfo) {
        NSArray *rows = [self infoRows];
        if ([rows[indexPath.row] integerValue] == GHReleaseInfoRowCommit && [self targetIsCommitSHA]) {
            CommitDetailViewController *commitVC = [[CommitDetailViewController alloc] init];
            commitVC.ownerLogin = self.ownerLogin;
            commitVC.repoName = self.repoName;
            commitVC.sha = GHReleaseString(self.releaseInfo, @"target_commitish");
            [self.navigationController pushViewController:commitVC animated:YES];
        }
        return;
    }

    if (kind == GHReleaseSectionKindAssets) {
        [self startDownloadForItemAtIndex:indexPath.row];
    }
}

#pragma mark - Скачивание файлов

- (void)assetMoreButtonTapped:(UIButton *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    if (!view) return;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
    if (!indexPath || indexPath.row >= (NSInteger)self.downloadItems.count) return;

    GHDownloadItem *item = self.downloadItems[indexPath.row];
    self.actionSheetItemIndex = indexPath.row;

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:item.displayName
                                                       delegate:self
                                              cancelButtonTitle:GHL(@"Отмена")
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:GHL(@"Скачать"), GHL(@"Скопировать ссылку"), nil];
    if (self.tabBarController.tabBar && !self.tabBarController.tabBar.hidden) {
        [sheet showFromTabBar:self.tabBarController.tabBar];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSInteger itemIndex = self.actionSheetItemIndex;
    self.actionSheetItemIndex = -1;
    if (buttonIndex == actionSheet.cancelButtonIndex) return;
    if (itemIndex < 0 || itemIndex >= (NSInteger)self.downloadItems.count) return;

    NSInteger firstOther = actionSheet.firstOtherButtonIndex;
    if (buttonIndex == firstOther) {
        [self startDownloadForItemAtIndex:itemIndex];
    } else if (buttonIndex == firstOther + 1) {
        GHDownloadItem *item = self.downloadItems[itemIndex];
        if (item.downloadURLString.length > 0) {
            [UIPasteboard generalPasteboard].string = item.downloadURLString;
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ссылка скопирована")
                                                             message:nil
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        }
    }
}

- (void)startDownloadForItemAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.downloadItems.count) return;
    if (self.downloadingIndexPath) return;

    GHDownloadItem *item = self.downloadItems[index];
    NSURL *url = [NSURL URLWithString:item.downloadURLString];
    if (!url) return;

    NSInteger section = [self sectionForKind:GHReleaseSectionKindAssets];
    self.downloadingIndexPath = [NSIndexPath indexPathForRow:index inSection:MAX(section, 0)];
    item.downloadProgress = 0.0;
    item.state = GHDownloadStateDownloading;
    [self reloadAssetRowForItem:item];

    __weak typeof(self) weakSelf = self;
    [[DownloadManager sharedManager] downloadFileAtURL:url
                                                fileName:item.fileName
                                                progress:^(float progress) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        item.downloadProgress = progress;
        [strongSelf refreshAssetRowForItem:item];
    } completion:^(NSString *filePath, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.downloadingIndexPath = nil;
        item.downloadProgress = 0.0;

        if (error) {
            item.state = GHDownloadStateFailed;
            [strongSelf reloadAssetRowForItem:item];

            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка скачивания")
                                                             message:error.localizedDescription
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil];
            [alert show];
        } else {
            item.state = GHDownloadStateSaved;
            [strongSelf reloadAssetRowForItem:item];

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
