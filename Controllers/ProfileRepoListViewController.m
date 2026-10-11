#import "ProfileRepoListViewController.h"
#import "GHCompat.h"
#import "RepoOverviewViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHStarredRepoCell.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kRepoCellID = @"RepoCell";
static NSString * const kRepoEmptyCellID = @"RepoEmptyCell";

static const CGFloat kRepoMargin = 16;
static const CGFloat kRepoTop = 12;
static const CGFloat kRepoNameHeight = 22;
static const CGFloat kRepoStatsHeight = 20;
static const CGFloat kRepoSpacing = 6;
static const CGFloat kRepoDescLines = 2;
static const CGFloat kRepoIconSize = 14;

static UIImage *GHProfileLockIcon(UIColor *color, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGFloat bodyW = size * 0.72;
    CGFloat bodyH = size * 0.5;
    CGRect body = CGRectMake((size - bodyW) / 2.0, size - bodyH - size * 0.04, bodyW, bodyH);
    UIBezierPath *bodyPath = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:size * 0.1];
    [bodyPath fill];
    CGFloat shackleW = bodyW * 0.62;
    CGFloat lw = MAX(1.5, size * 0.13);
    UIBezierPath *shackle = [UIBezierPath bezierPath];
    CGFloat sx = (size - shackleW) / 2.0;
    CGFloat sTop = size * 0.1 + lw / 2.0;
    CGFloat r = shackleW / 2.0;
    [shackle moveToPoint:CGPointMake(sx, body.origin.y + 1)];
    [shackle addLineToPoint:CGPointMake(sx, sTop + r)];
    [shackle addArcWithCenter:CGPointMake(size / 2.0, sTop + r) radius:r startAngle:M_PI endAngle:0 clockwise:YES];
    [shackle addLineToPoint:CGPointMake(sx + shackleW, body.origin.y + 1)];
    shackle.lineWidth = lw;
    [shackle stroke];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface GHProfileRepoCell : UITableViewCell
@property (nonatomic, strong) UIImageView *lockView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIImageView *starView;
@property (nonatomic, strong) UILabel *starCountLabel;
@property (nonatomic, strong) UIImageView *forkView;
@property (nonatomic, strong) UILabel *forkCountLabel;
@property (nonatomic, strong) UIView *languageDotView;
@property (nonatomic, strong) UILabel *languageLabel;
@property (nonatomic, assign) BOOL isPrivate;
+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width;
- (void)configureWithRepo:(NSDictionary *)repo showFullName:(BOOL)showFullName;
@end

@implementation GHProfileRepoCell

+ (NSString *)descriptionForRepo:(NSDictionary *)repo {
    id d = repo[@"description"];
    return [d isKindOfClass:[NSString class]] ? d : nil;
}

+ (CGFloat)descriptionHeightForText:(NSString *)text width:(CGFloat)width {
    if (text.length == 0) return 0;
    UIFont *font = [UIFont systemFontOfSize:14];
    CGSize size = [text sizeWithFont:font
                   constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                       lineBreakMode:NSLineBreakByTruncatingTail];
    return MIN(ceil(size.height), ceil(font.lineHeight) * kRepoDescLines);
}

+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width {
    CGFloat contentWidth = width - kRepoMargin * 2;
    CGFloat descHeight = [self descriptionHeightForText:[self descriptionForRepo:repo] width:contentWidth];
    CGFloat h = kRepoTop + kRepoNameHeight;
    if (descHeight > 0) h += kRepoSpacing + descHeight;
    h += kRepoSpacing + kRepoStatsHeight + kRepoTop;
    return h;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;

        self.lockView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.lockView];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont boldSystemFontOfSize:16];
        self.nameLabel.backgroundColor = [UIColor clearColor];
        self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:self.nameLabel];

        self.descriptionLabel = [[UILabel alloc] init];
        self.descriptionLabel.font = [UIFont systemFontOfSize:14];
        self.descriptionLabel.numberOfLines = (NSInteger)kRepoDescLines;
        self.descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        self.descriptionLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.descriptionLabel];

        self.starView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.starView];

        self.starCountLabel = [[UILabel alloc] init];
        self.starCountLabel.font = [UIFont systemFontOfSize:13];
        self.starCountLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.starCountLabel];

        self.forkView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.forkView];

        self.forkCountLabel = [[UILabel alloc] init];
        self.forkCountLabel.font = [UIFont systemFontOfSize:13];
        self.forkCountLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.forkCountLabel];

        self.languageDotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        self.languageDotView.layer.cornerRadius = 5;
        self.languageDotView.layer.masksToBounds = YES;
        [self.contentView addSubview:self.languageDotView];

        self.languageLabel = [[UILabel alloc] init];
        self.languageLabel.font = [UIFont systemFontOfSize:13];
        self.languageLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.languageLabel];
    }
    return self;
}

+ (NSString *)formattedCount:(NSNumber *)number {
    double value = number.doubleValue;
    if (value >= 1000) {
        return [NSString stringWithFormat:@"%.1fk", value / 1000.0];
    }
    return [NSString stringWithFormat:@"%.0f", value];
}

- (void)configureWithRepo:(NSDictionary *)repo showFullName:(BOOL)showFullName {
    NSString *name = showFullName ? repo[@"full_name"] : repo[@"name"];
    if (![name isKindOfClass:[NSString class]]) name = repo[@"full_name"];
    NSString *description = [GHProfileRepoCell descriptionForRepo:repo];
    NSString *language = [repo[@"language"] isKindOfClass:[NSString class]] ? repo[@"language"] : nil;
    NSNumber *stars = [repo[@"stargazers_count"] isKindOfClass:[NSNumber class]] ? repo[@"stargazers_count"] : @0;
    NSNumber *forks = [repo[@"forks_count"] isKindOfClass:[NSNumber class]] ? repo[@"forks_count"] : @0;
    self.isPrivate = [repo[@"private"] respondsToSelector:@selector(boolValue)] && [repo[@"private"] boolValue];

    UIColor *secondary = GHSecondaryTextColor();

    self.lockView.hidden = !self.isPrivate;
    self.lockView.image = self.isPrivate ? GHProfileLockIcon(secondary, kRepoIconSize) : nil;

    self.nameLabel.text = name;
    self.nameLabel.textColor = GHPrimaryTextColor();

    self.descriptionLabel.text = description ?: @"";
    self.descriptionLabel.textColor = secondary;
    self.descriptionLabel.hidden = description.length == 0;

    self.starView.image = [GHIconRenderer starIconWithColor:secondary size:kRepoIconSize filled:NO];
    self.starCountLabel.text = [GHProfileRepoCell formattedCount:stars];
    self.starCountLabel.textColor = secondary;

    BOOL showForks = forks.integerValue > 0;
    self.forkView.hidden = !showForks;
    self.forkCountLabel.hidden = !showForks;
    self.forkView.image = [GHIconRenderer forkIconWithColor:secondary size:kRepoIconSize];
    self.forkCountLabel.text = [GHProfileRepoCell formattedCount:forks];
    self.forkCountLabel.textColor = secondary;

    self.languageDotView.hidden = language.length == 0;
    self.languageLabel.hidden = language.length == 0;
    self.languageLabel.text = language ?: @"";
    self.languageLabel.textColor = secondary;
    self.languageDotView.backgroundColor = GHColorForLanguage(language);

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = width - kRepoMargin * 2;
    CGFloat y = kRepoTop;

    CGFloat nameX = kRepoMargin;
    if (!self.lockView.hidden) {
        self.lockView.frame = CGRectMake(kRepoMargin, y + (kRepoNameHeight - kRepoIconSize) / 2.0, kRepoIconSize, kRepoIconSize);
        nameX += kRepoIconSize + 6;
    }
    self.nameLabel.frame = CGRectMake(nameX, y, width - nameX - kRepoMargin, kRepoNameHeight);
    y += kRepoNameHeight;

    if (!self.descriptionLabel.hidden) {
        y += kRepoSpacing;
        CGFloat h = [GHProfileRepoCell descriptionHeightForText:self.descriptionLabel.text width:contentWidth];
        self.descriptionLabel.frame = CGRectMake(kRepoMargin, y, contentWidth, h);
        y += h;
    } else {
        self.descriptionLabel.frame = CGRectMake(kRepoMargin, y, contentWidth, 0);
    }

    y += kRepoSpacing;
    CGFloat x = kRepoMargin;
    CGFloat iconY = y + (kRepoStatsHeight - kRepoIconSize) / 2.0;

    self.starView.frame = CGRectMake(x, iconY, kRepoIconSize, kRepoIconSize);
    x += kRepoIconSize + 4;
    [self.starCountLabel sizeToFit];
    CGRect f = self.starCountLabel.frame;
    f.origin = CGPointMake(x, y + (kRepoStatsHeight - f.size.height) / 2.0);
    self.starCountLabel.frame = f;
    x += f.size.width + 16;

    if (!self.forkView.hidden) {
        self.forkView.frame = CGRectMake(x, iconY, kRepoIconSize, kRepoIconSize);
        x += kRepoIconSize + 4;
        [self.forkCountLabel sizeToFit];
        f = self.forkCountLabel.frame;
        f.origin = CGPointMake(x, y + (kRepoStatsHeight - f.size.height) / 2.0);
        self.forkCountLabel.frame = f;
        x += f.size.width + 16;
    }

    if (!self.languageDotView.hidden) {
        self.languageDotView.frame = CGRectMake(x, y + (kRepoStatsHeight - 10) / 2.0, 10, 10);
        x += 10 + 6;
        [self.languageLabel sizeToFit];
        f = self.languageLabel.frame;
        CGFloat maxW = MAX(0, width - kRepoMargin - x);
        f.size.width = MIN(f.size.width, maxW);
        f.origin = CGPointMake(x, y + (kRepoStatsHeight - f.size.height) / 2.0);
        self.languageLabel.frame = f;
    }
}

@end

@interface ProfileRepoListViewController ()
@property (nonatomic, copy) NSString *dominantOwner;
@end

@implementation ProfileRepoListViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = GHL(@"Репозитории");
    }
    return self;
}

- (void)setRepos:(NSArray *)repos {
    _repos = repos;
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    NSString *best = nil;
    NSInteger bestCount = 0;
    for (NSDictionary *repo in repos) {
        NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
        NSString *login = [owner[@"login"] isKindOfClass:[NSString class]] ? owner[@"login"] : nil;
        if (login.length == 0) continue;
        NSInteger c = [counts[login] integerValue] + 1;
        counts[login] = @(c);
        if (c > bestCount) {
            bestCount = c;
            best = login;
        }
    }
    self.dominantOwner = best;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.tableView gh_registerCellClass:[GHProfileRepoCell class] forCellReuseIdentifier:kRepoCellID];
    [self.tableView gh_registerCellClass:[UITableViewCell class] forCellReuseIdentifier:kRepoEmptyCellID];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX(self.repos.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.repos.count == 0) {
        UITableViewCell *cell = [tableView gh_dequeueCellWithIdentifier:kRepoEmptyCellID forIndexPath:indexPath];
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = GHL(@"Репозиториев нет");
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    GHProfileRepoCell *cell = [tableView gh_dequeueCellWithIdentifier:kRepoCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    NSDictionary *repo = self.repos[indexPath.row];
    NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
    NSString *login = owner[@"login"];
    BOOL showFull = self.dominantOwner.length > 0 && [login isKindOfClass:[NSString class]] && ![login isEqualToString:self.dominantOwner];
    [cell configureWithRepo:repo showFullName:showFull];
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.repos.count == 0) return 44;
    return [GHProfileRepoCell heightForRepo:self.repos[indexPath.row] width:tableView.bounds.size.width];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.repos.count == 0) return;

    NSDictionary *repo = self.repos[indexPath.row];
    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = repo;
    overviewVC.title = repo[@"name"];
    [self.navigationController pushViewController:overviewVC animated:YES];
}

@end
