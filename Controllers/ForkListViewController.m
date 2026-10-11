#import "ForkListViewController.h"
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import "GHAPIClient.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHStarredRepoCell.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHAvatarLoader.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kForkCellID = @"ForkCell";

static NSString * const kForkEmptyCellID = @"ForkEmptyCell";

static const NSInteger kForksPerPage = 30;

static const NSInteger kMaxForksRawPages = 10;

static const NSInteger kForksDisplayBatchSize = 25;

static const CGFloat kForkMargin = 16;
static const CGFloat kForkTop = 14;
static const CGFloat kForkOwnerHeight = 22;
static const CGFloat kForkNameHeight = 22;
static const CGFloat kForkRowHeight = 20;
static const CGFloat kForkSpacing = 6;
static const CGFloat kForkIconSize = 14;

static NSString *GHForkL(NSString *ru, NSString *en) {
    return [[GHLocalization sharedManager].languageCode isEqualToString:@"en"] ? en : ru;
}

@interface GHForkRepoCell : UITableViewCell
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *ownerLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIImageView *forkIconView;
@property (nonatomic, strong) UILabel *forkedFromLabel;
@property (nonatomic, strong) UIImageView *starView;
@property (nonatomic, strong) UILabel *starCountLabel;
@property (nonatomic, strong) UIView *languageDotView;
@property (nonatomic, strong) UILabel *languageLabel;
+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width;
- (void)configureWithRepo:(NSDictionary *)repo parentFullName:(NSString *)parentFullName;
@end

@implementation GHForkRepoCell

+ (NSString *)descriptionForRepo:(NSDictionary *)repo {
    id d = repo[@"description"];
    if (![d isKindOfClass:[NSString class]]) return nil;
    NSString *t = [d stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length > 0 ? t : nil;
}

+ (CGFloat)descriptionHeight:(NSString *)text width:(CGFloat)width {
    if (text.length == 0) return 0;
    UIFont *font = [UIFont systemFontOfSize:15];
    CGSize size = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByTruncatingTail];
    return MIN(ceil(size.height), ceil(font.lineHeight) * 3);
}

+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width {
    CGFloat contentWidth = width - kForkMargin * 2;
    CGFloat h = kForkTop + kForkOwnerHeight + 4 + kForkNameHeight;
    CGFloat d = [self descriptionHeight:[self descriptionForRepo:repo] width:contentWidth];
    if (d > 0) h += 4 + d;
    h += kForkSpacing + kForkRowHeight;
    h += kForkSpacing + kForkRowHeight;
    h += kForkTop;
    return h;
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

        self.avatarView = [[UIImageView alloc] init];
        self.avatarView.layer.cornerRadius = 11;
        self.avatarView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.avatarView];

        self.ownerLabel = [self labelWithFont:[UIFont systemFontOfSize:15]];
        self.nameLabel = [self labelWithFont:[UIFont boldSystemFontOfSize:17]];
        self.descriptionLabel = [self labelWithFont:[UIFont systemFontOfSize:15]];
        self.descriptionLabel.numberOfLines = 3;

        self.forkIconView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.forkIconView];
        self.forkedFromLabel = [self labelWithFont:[UIFont systemFontOfSize:14]];

        self.starView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.starView];
        self.starCountLabel = [self labelWithFont:[UIFont systemFontOfSize:14]];

        self.languageDotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        self.languageDotView.layer.cornerRadius = 5;
        self.languageDotView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.languageDotView];
        self.languageLabel = [self labelWithFont:[UIFont systemFontOfSize:14]];
    }
    return self;
}

- (void)configureWithRepo:(NSDictionary *)repo parentFullName:(NSString *)parentFullName {
    NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
    NSString *login = [owner[@"login"] isKindOfClass:[NSString class]] ? owner[@"login"] : @"";
    NSString *avatar = [owner[@"avatar_url"] isKindOfClass:[NSString class]] ? owner[@"avatar_url"] : nil;
    NSString *name = [repo[@"name"] isKindOfClass:[NSString class]] ? repo[@"name"] : @"";
    NSString *language = [repo[@"language"] isKindOfClass:[NSString class]] ? repo[@"language"] : nil;
    NSInteger stars = [repo[@"stargazers_count"] respondsToSelector:@selector(integerValue)] ? [repo[@"stargazers_count"] integerValue] : 0;
    NSString *description = [GHForkRepoCell descriptionForRepo:repo];

    UIColor *secondary = GHSecondaryTextColor();

    self.avatarView.backgroundColor = GHSeparatorColor();
    self.avatarView.image = nil;
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatar intoImageView:self.avatarView];
    self.ownerLabel.text = login;
    self.ownerLabel.textColor = secondary;

    self.nameLabel.text = name;
    self.nameLabel.textColor = GHPrimaryTextColor();

    self.descriptionLabel.text = description ?: @"";
    self.descriptionLabel.textColor = GHPrimaryTextColor();
    self.descriptionLabel.hidden = description.length == 0;

    self.forkIconView.image = [GHIconRenderer forkIconWithColor:secondary size:kForkIconSize];
    self.forkedFromLabel.text = [NSString stringWithFormat:GHForkL(@"Форк от %@", @"Forked from %@"), parentFullName ?: @""];
    self.forkedFromLabel.textColor = secondary;

    self.starView.image = [GHIconRenderer starIconWithColor:[UIColor colorWithRed:0.89 green:0.70 blue:0.16 alpha:1.0] size:kForkIconSize + 2 filled:YES];
    self.starCountLabel.text = stars >= 1000 ? [NSString stringWithFormat:@"%.1fk", stars / 1000.0] : [NSString stringWithFormat:@"%ld", (long)stars];
    self.starCountLabel.textColor = secondary;

    self.languageDotView.hidden = language.length == 0;
    self.languageLabel.hidden = language.length == 0;
    self.languageDotView.backgroundColor = GHColorForLanguage(language);
    self.languageLabel.text = language ?: @"";
    self.languageLabel.textColor = secondary;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = width - kForkMargin * 2;
    CGFloat y = kForkTop;

    self.avatarView.frame = CGRectMake(kForkMargin, y, 22, 22);
    self.ownerLabel.frame = CGRectMake(kForkMargin + 30, y, contentWidth - 30, kForkOwnerHeight);
    y += kForkOwnerHeight + 4;

    self.nameLabel.frame = CGRectMake(kForkMargin, y, contentWidth, kForkNameHeight);
    y += kForkNameHeight;

    if (!self.descriptionLabel.hidden) {
        y += 4;
        CGFloat h = [GHForkRepoCell descriptionHeight:self.descriptionLabel.text width:contentWidth];
        self.descriptionLabel.frame = CGRectMake(kForkMargin, y, contentWidth, h);
        y += h;
    }

    y += kForkSpacing;
    self.forkIconView.frame = CGRectMake(kForkMargin + 1, y + (kForkRowHeight - kForkIconSize) / 2.0, kForkIconSize, kForkIconSize);
    self.forkedFromLabel.frame = CGRectMake(kForkMargin + 30, y, contentWidth - 30, kForkRowHeight);
    y += kForkRowHeight + kForkSpacing;

    CGFloat x = kForkMargin;
    CGFloat starSize = kForkIconSize + 2;
    self.starView.frame = CGRectMake(x, y + (kForkRowHeight - starSize) / 2.0, starSize, starSize);
    x += 30;
    [self.starCountLabel sizeToFit];
    CGRect f = self.starCountLabel.frame;
    f.origin = CGPointMake(x, y + (kForkRowHeight - f.size.height) / 2.0);
    self.starCountLabel.frame = f;
    x += f.size.width + 18;

    if (!self.languageDotView.hidden) {
        self.languageDotView.frame = CGRectMake(x, y + (kForkRowHeight - 10) / 2.0, 10, 10);
        x += 10 + 8;
        [self.languageLabel sizeToFit];
        f = self.languageLabel.frame;
        f.size.width = MIN(f.size.width, MAX(width - kForkMargin - x, 0));
        f.origin = CGPointMake(x, y + (kForkRowHeight - f.size.height) / 2.0);
        self.languageLabel.frame = f;
    }
}

@end

static const NSInteger kPeriodActionSheetTag = 1;
static const NSInteger kSortActionSheetTag = 2;

@interface ForkListViewController ()
@property (nonatomic, strong) NSMutableArray *forks;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) NSInteger nextRawPage;
@property (nonatomic, assign) BOOL hasMoreForks;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL loadAttempted;

@property (nonatomic, assign) BOOL loadInProgress;

@property (nonatomic, copy) NSString *selectedSortValue;
@property (nonatomic, assign) NSInteger selectedPeriodYears;
@property (nonatomic, strong) UIButton *periodButton;
@property (nonatomic, strong) UIButton *sortButton;
@property (nonatomic, strong) UIView *headerView;

@property (nonatomic, strong) UIActionSheet *presentedActionSheet;
@end

@implementation ForkListViewController

+ (BOOL)forkListInfoFromURL:(NSURL *)url
                  ownerLogin:(NSString **)ownerLogin
                    repoName:(NSString **)repoName {
    if (url == nil) return NO;
    static NSRegularExpression *forksRegex = nil;
    static NSRegularExpression *networkMembersRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        forksRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/forks/?(?:[?#].*)?$"
                                                                 options:NSRegularExpressionCaseInsensitive
                                                                   error:nil];
        networkMembersRegex = [NSRegularExpression regularExpressionWithPattern:
            @"^https?://github\\.com/([^/]+)/([^/]+)/network/members/?(?:[?#].*)?$"
                                                                          options:NSRegularExpressionCaseInsensitive
                                                                            error:nil];
    });
    NSString *urlString = url.absoluteString;
    NSTextCheckingResult *match = [forksRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    if (match == nil) {
        match = [networkMembersRegex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
    }
    if (match == nil) return NO;

    if (ownerLogin != NULL) *ownerLogin = [urlString substringWithRange:[match rangeAtIndex:1]];
    if (repoName != NULL) *repoName = [urlString substringWithRange:[match rangeAtIndex:2]];
    return YES;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Форки");
        _forks = [NSMutableArray array];
        _selectedSortValue = @"newest";
        _selectedPeriodYears = 0;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView gh_registerCellClass:[GHForkRepoCell class] forCellReuseIdentifier:kForkCellID];
    self.tableView.tableHeaderView = [self buildHeaderView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    if (GHPullToRefreshAvailable()) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        [self.refreshControl addTarget:self action:@selector(reloadForks) forControlEvents:UIControlEventValueChanged];
    } else {
        self.gh_legacyRefreshControl = [GHLegacyRefreshControl gh_attachToScrollView:self.tableView];
        [self.gh_legacyRefreshControl addTarget:self action:@selector(reloadForks) forControlEvents:UIControlEventValueChanged];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(handleLanguageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];

    [self reloadForks];
}

- (void)handleLanguageDidChange {
    self.title = GHL(@"Форки");
    [self updateFilterButtonTitles];
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Заголовок с фильтрами

- (UIView *)buildHeaderView {
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 52)];
    headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.periodButton = [self filterButtonWithFrame:CGRectMake(16, 10, 100, 32)];
    [self.periodButton addTarget:self action:@selector(periodButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:self.periodButton];

    self.sortButton = [self filterButtonWithFrame:CGRectMake(126, 10, 100, 32)];
    [self.sortButton addTarget:self action:@selector(sortButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [headerView addSubview:self.sortButton];

    self.headerView = headerView;
    [self updateFilterButtonTitles];
    return headerView;
}

- (UIButton *)filterButtonWithFrame:(CGRect)frame {

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    button.layer.cornerRadius = 16.0;
    button.layer.borderWidth = 1.0;
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;

    if ([button.titleLabel respondsToSelector:@selector(setMinimumScaleFactor:)]) {
        button.titleLabel.minimumScaleFactor = 0.7;
    } else {
        button.titleLabel.minimumFontSize = 13.0 * 0.7;
    }
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 14, 0, 14);
    return button;
}

- (NSString *)periodDisplayNameForYears:(NSInteger)years {
    if (years == 0) return GHL(@"Всё время");
    if (years == 1) return GHL(@"Последний год");
    return [NSString stringWithFormat:GHL(@"Последние %ld года"), (long)years];
}

- (NSString *)sortDisplayNameForValue:(NSString *)value {
    if ([value isEqualToString:@"stargazers"]) return GHL(@"По звёздам");
    if ([value isEqualToString:@"oldest"]) return GHL(@"Сначала старые");
    return GHL(@"Сначала новые");
}

- (void)updateFilterButtonTitles {

    NSString *periodTitle = [NSString stringWithFormat:@"%@ ▾", [self periodDisplayNameForYears:self.selectedPeriodYears]];
    NSString *sortTitle = [NSString stringWithFormat:@"%@ ▾", [self sortDisplayNameForValue:self.selectedSortValue]];
    [self.periodButton setTitle:periodTitle forState:UIControlStateNormal];
    [self.sortButton setTitle:sortTitle forState:UIControlStateNormal];
    [self layoutFilterButtons];
}

- (void)layoutFilterButtons {
    CGFloat maxWidth = MAX((self.headerView.bounds.size.width - 16 * 2 - 10) / 2.0, 60);
    CGFloat x = 16;
    for (UIButton *button in @[self.periodButton, self.sortButton]) {
        NSString *title = [button titleForState:UIControlStateNormal];
        CGFloat w = ceil([title sizeWithFont:button.titleLabel.font].width) + 28;
        w = MIN(w, maxWidth);
        button.frame = CGRectMake(x, 10, w, 32);
        x += w + 10;
    }
}

- (void)periodButtonTapped {
    if (self.presentedActionSheet) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                          destructiveButtonTitle:nil
                                               otherButtonTitles:GHL(@"Всё время"),
                                                                  GHL(@"Последний год"),
                                                                  GHL(@"Последние 2 года"), nil];
    sheet.tag = kPeriodActionSheetTag;
    self.presentedActionSheet = sheet;
    [sheet showInView:[self actionSheetHostView]];
}

- (void)sortButtonTapped {
    if (self.presentedActionSheet) return;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                          destructiveButtonTitle:nil
                                               otherButtonTitles:GHL(@"Сначала новые"),
                                                                  GHL(@"По звёздам"),
                                                                  GHL(@"Сначала старые"), nil];
    sheet.tag = kSortActionSheetTag;
    self.presentedActionSheet = sheet;
    [sheet showInView:[self actionSheetHostView]];
}

- (UIView *)actionSheetHostView {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    return keyWindow ?: self.view.window ?: self.navigationController.view ?: self.view;
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet == self.presentedActionSheet) self.presentedActionSheet = nil;
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (actionSheet.tag == kPeriodActionSheetTag) {
        NSArray *years = @[@0, @1, @2];
        if ((NSUInteger)buttonIndex >= years.count) return;
        NSInteger newValue = [years[buttonIndex] integerValue];
        if (newValue == self.selectedPeriodYears) return;
        self.selectedPeriodYears = newValue;
        [self updateFilterButtonTitles];

        [self reloadForks];
        return;
    }

    if (actionSheet.tag == kSortActionSheetTag) {
        NSArray *values = @[@"newest", @"stargazers", @"oldest"];
        if ((NSUInteger)buttonIndex >= values.count) return;
        NSString *newValue = values[buttonIndex];
        if ([newValue isEqualToString:self.selectedSortValue]) return;
        self.selectedSortValue = newValue;
        [self updateFilterButtonTitles];
        [self reloadForks];
        return;
    }
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.separatorColor = GHSeparatorColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();

    self.headerView.backgroundColor = GHCellBackgroundColor();

    for (UIButton *button in @[self.periodButton, self.sortButton]) {
        [button setBackgroundImage:nil forState:UIControlStateNormal];
        button.backgroundColor = [GHThemeManager sharedManager].darkModeEnabled ? [UIColor colorWithWhite:0.18 alpha:1.0] : [UIColor colorWithWhite:0.95 alpha:1.0];
        [button setTitleColor:GHPrimaryTextColor() forState:UIControlStateNormal];
        button.layer.borderColor = GHSeparatorColor().CGColor;
    }

    [self.tableView reloadData];
}

- (BOOL)passesPeriodFilter:(NSDictionary *)fork {
    if (self.selectedPeriodYears == 0) return YES;

    NSString *createdAt = [fork[@"created_at"] isKindOfClass:[NSString class]] ? fork[@"created_at"] : nil;
    if (createdAt.length == 0) return YES;

    NSDateFormatter *isoFormatter = GHISODateFormatter();
    NSDate *date = [isoFormatter dateFromString:createdAt];
    if (!date) return YES;

    NSTimeInterval secondsInPeriod = self.selectedPeriodYears * 365.25 * 24 * 60 * 60;
    return -[date timeIntervalSinceNow] <= secondsInPeriod;
}

- (void)reloadForks {
    self.nextRawPage = 1;
    self.hasMoreForks = YES;
    self.loadingMore = NO;
    self.loadAttempted = NO;
    self.loadInProgress = YES;
    [self.forks removeAllObjects];
    [self.tableView reloadData];
    [self.spinner startAnimating];
    [self fetchForksBatchWithAccumulator:[NSMutableArray array] isInitialLoad:YES];
}

- (void)fetchForksBatchWithAccumulator:(NSMutableArray *)accumulator isInitialLoad:(BOOL)isInitialLoad {
    NSInteger requestedPage = self.nextRawPage;

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] forksForOwner:self.ownerLogin
                                          repo:self.repoName
                                          sort:self.selectedSortValue
                                          page:requestedPage
                                    completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (error) {
            [strongSelf.spinner stopAnimating];
            if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }
            strongSelf.loadingMore = NO;
            strongSelf.loadAttempted = YES;
            strongSelf.loadInProgress = NO;
            if (isInitialLoad) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                                 message:error.localizedDescription
                                                                delegate:nil
                                                       cancelButtonTitle:@"OK"
                                                       otherButtonTitles:nil];
                [alert show];
            }
            [strongSelf.tableView reloadData];
            return;
        }

        NSArray *pageEntries = [jsonObject isKindOfClass:[NSArray class]] ? jsonObject : @[];
        for (NSDictionary *fork in pageEntries) {
            if (![fork isKindOfClass:[NSDictionary class]]) continue;
            if ([strongSelf passesPeriodFilter:fork]) [accumulator addObject:fork];
        }

        BOOL rawPageWasLast = pageEntries.count < kForksPerPage;
        NSInteger nextRawPage = strongSelf.nextRawPage + 1;
        BOOL hitPageCap = nextRawPage > kMaxForksRawPages;
        BOOL enoughForBatch = accumulator.count >= kForksDisplayBatchSize;

        if (!rawPageWasLast && !hitPageCap && !enoughForBatch) {
            strongSelf.nextRawPage = nextRawPage;
            [strongSelf fetchForksBatchWithAccumulator:accumulator isInitialLoad:isInitialLoad];
            return;
        }

        strongSelf.nextRawPage = nextRawPage;
        strongSelf.hasMoreForks = !rawPageWasLast && !hitPageCap;
        strongSelf.loadAttempted = YES;
        strongSelf.loadingMore = NO;
        strongSelf.loadInProgress = NO;

        if (isInitialLoad) [strongSelf.forks removeAllObjects];
        [strongSelf.forks addObjectsFromArray:accumulator];

        [strongSelf.spinner stopAnimating];
        if (GHPullToRefreshAvailable()) { [strongSelf.refreshControl endRefreshing]; } else { [strongSelf.gh_legacyRefreshControl endRefreshing]; }
        [strongSelf.tableView reloadData];
    }];
}

- (void)loadMoreForksIfNeeded {
    if (!self.hasMoreForks || self.loadingMore) return;
    self.loadingMore = YES;
    [self.tableView reloadData];
    [self fetchForksBatchWithAccumulator:[NSMutableArray array] isInitialLoad:NO];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.forks.count > 0) return self.forks.count;

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kForkEmptyCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kForkEmptyCellID];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = GHSecondaryTextColor();
        if (self.loadInProgress || !self.loadAttempted) {
            cell.textLabel.text = GHL(@"Загрузка…");
        } else {
            cell.textLabel.text = self.selectedPeriodYears > 0
                ? GHL(@"За выбранный период форков не найдено — попробуйте расширить период")
                : GHL(@"У репозитория пока нет форков");
        }
        return cell;
    }

    GHForkRepoCell *cell = [tableView gh_dequeueCellWithIdentifier:kForkCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    [cell configureWithRepo:self.forks[indexPath.row]
              parentFullName:[NSString stringWithFormat:@"%@/%@", self.ownerLogin ?: @"", self.repoName ?: @""]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0) {

        CGFloat headerHeight = self.tableView.tableHeaderView.frame.size.height;
        return MAX(120, tableView.bounds.size.height - headerHeight);
    }
    return [GHForkRepoCell heightForRepo:self.forks[indexPath.row] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.forks.count == 0 || indexPath.row != (NSInteger)self.forks.count - 1) return;
    [self loadMoreForksIfNeeded];
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
    if (indexPath.row >= (NSInteger)self.forks.count) return;

    NSDictionary *repo = self.forks[indexPath.row];
    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = repo[@"name"];
    [self.navigationController pushViewController:overviewVC animated:YES];
}

@end
