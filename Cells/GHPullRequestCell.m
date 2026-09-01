#import "GHPullRequestCell.h"
#import "GHIconRenderer.h"
#import "GHThemeManager.h"

static const CGFloat kMargin = 15;
static const CGFloat kDotSize = 10;
static const CGFloat kTitleToDotGap = 8;
static const CGFloat kSubtitleHeight = 16;
static const CGFloat kRowSpacing = 4;
static const CGFloat kBadgeHSpacing = 6;
static const CGFloat kBadgeVSpacing = 6;
static const CGFloat kBadgePointSize = 10;

static NSString *GHSafeString(NSDictionary *dict, NSString *key) {
    id value = dict[key];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString *GHRelativeDateString(NSString *isoString) {
    if (isoString.length == 0) return @"";

    NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
    isoFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    isoFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];

    NSDate *date = [isoFormatter dateFromString:isoString];
    if (!date) return @"";

    NSTimeInterval seconds = -[date timeIntervalSinceNow];
    if (seconds < 0) seconds = 0;

    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    NSInteger months = days / 30;
    NSInteger years = days / 365;

    if (minutes < 1) return @"now";
    if (minutes < 60) return [NSString stringWithFormat:@"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:@"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:@"%ldd", (long)days];
    if (months < 12) return [NSString stringWithFormat:@"%ldmo", (long)months];
    return [NSString stringWithFormat:@"%ldy", (long)years];
}

static NSArray *GHValidLabels(NSDictionary *pullRequest) {
    NSMutableArray *validLabels = [NSMutableArray array];
    NSArray *rawLabels = [pullRequest[@"labels"] isKindOfClass:[NSArray class]] ? pullRequest[@"labels"] : nil;
    for (NSDictionary *label in rawLabels) {
        if (![label isKindOfClass:[NSDictionary class]]) continue;
        if (GHSafeString(label, @"name").length > 0) [validLabels addObject:label];
    }
    return validLabels;
}

static NSArray *GHLayoutBadgeFrames(NSArray *validLabels, CGFloat maxWidth, CGFloat *outTotalHeight) {
    NSMutableArray *frames = [NSMutableArray array];
    CGFloat x = 0, y = 0, rowHeight = 0;
    for (NSDictionary *label in validLabels) {
        NSString *labelName = GHSafeString(label, @"name");
        UIImage *badgeImage = [GHIconRenderer issueLabelBadgeWithText:labelName
                                                        backgroundColor:[UIColor whiteColor]
                                                              textColor:[UIColor blackColor]
                                                              pointSize:kBadgePointSize];
        CGFloat badgeWidth = badgeImage.size.width;
        CGFloat badgeHeight = badgeImage.size.height;
        if (x > 0 && x + badgeWidth > maxWidth) {
            x = 0;
            y += rowHeight + kBadgeVSpacing;
            rowHeight = 0;
        }
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(x, y, badgeWidth, badgeHeight)]];
        x += badgeWidth + kBadgeHSpacing;
        rowHeight = MAX(rowHeight, badgeHeight);
    }
    if (outTotalHeight != NULL) {
        *outTotalHeight = validLabels.count > 0 ? (y + rowHeight) : 0;
    }
    return frames;
}

@interface GHPullRequestCell ()
@property (nonatomic, strong) UIImageView *statusDotView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) NSArray *badgeImageViews;
@end

@implementation GHPullRequestCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;

        self.statusDotView = [[UIImageView alloc] init];
        [self.contentView addSubview:self.statusDotView];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.font = [UIFont systemFontOfSize:12];
        self.subtitleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.subtitleLabel];

        self.badgeImageViews = @[];
    }
    return self;
}

+ (CGFloat)contentWidthForWidth:(CGFloat)width {
    return width - kMargin * 2 - kDotSize - kTitleToDotGap;
}

+ (CGFloat)heightForPullRequest:(NSDictionary *)pullRequest width:(CGFloat)width {
    CGFloat contentWidth = [self contentWidthForWidth:width];

    NSString *title = GHSafeString(pullRequest, @"title");
    CGSize titleSize = [(title.length > 0 ? title : @" ") sizeWithFont:[UIFont boldSystemFontOfSize:15]
                                                       constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                                           lineBreakMode:NSLineBreakByTruncatingTail];
    CGFloat titleHeight = MIN(titleSize.height, [UIFont boldSystemFontOfSize:15].lineHeight * 1.3 * 2);

    CGFloat height = kMargin;
    height += titleHeight;
    height += kRowSpacing + kSubtitleHeight;

    NSArray *validLabels = GHValidLabels(pullRequest);
    if (validLabels.count > 0) {
        CGFloat badgesHeight = 0;
        GHLayoutBadgeFrames(validLabels, contentWidth, &badgesHeight);
        height += kRowSpacing + badgesHeight;
    }

    height += kMargin;
    return height;
}

- (void)configureWithPullRequest:(NSDictionary *)pullRequest isMerged:(BOOL)isMerged {
    NSDictionary *user = [pullRequest[@"user"] isKindOfClass:[NSDictionary class]] ? pullRequest[@"user"] : nil;
    NSString *title = GHSafeString(pullRequest, @"title");
    NSString *authorLogin = GHSafeString(user, @"login");
    NSNumber *number = [pullRequest[@"number"] isKindOfClass:[NSNumber class]] ? pullRequest[@"number"] : @0;
    NSNumber *comments = [pullRequest[@"comments"] isKindOfClass:[NSNumber class]] ? pullRequest[@"comments"] : @0;
    NSString *state = GHSafeString(pullRequest, @"state");
    NSString *createdAt = GHSafeString(pullRequest, @"created_at");

    self.titleLabel.text = title.length > 0 ? title : nil;
    self.titleLabel.textColor = GHPrimaryTextColor();

    UIColor *stateColor;
    if (isMerged) {
        stateColor = [UIColor colorWithRed:0.51 green:0.31 blue:0.87 alpha:1.0];
    } else if ([state isEqualToString:@"closed"]) {
        stateColor = [UIColor colorWithRed:0.56 green:0.56 blue:0.58 alpha:1.0];
    } else {
        stateColor = [UIColor colorWithRed:0.16 green:0.71 blue:0.29 alpha:1.0];
    }
    self.statusDotView.image = [GHIconRenderer dotIconWithColor:stateColor size:kDotSize];

    NSMutableString *subtitle = [NSMutableString stringWithFormat:@"#%@", number];
    if (authorLogin.length > 0) [subtitle appendFormat:@" · %@", authorLogin];
    if (comments.integerValue > 0) [subtitle appendFormat:@" · 💬 %@", comments];
    NSString *relativeDate = GHRelativeDateString(createdAt);
    if (relativeDate.length > 0) [subtitle appendFormat:@" · %@", relativeDate];
    self.subtitleLabel.text = subtitle;
    self.subtitleLabel.textColor = GHSecondaryTextColor();

    for (UIImageView *badgeView in self.badgeImageViews) [badgeView removeFromSuperview];

    NSArray *validLabels = GHValidLabels(pullRequest);
    NSMutableArray *newBadgeViews = [NSMutableArray array];
    for (NSDictionary *label in validLabels) {
        NSString *labelName = GHSafeString(label, @"name");
        UIColor *badgeColor = [GHIconRenderer colorFromHexString:GHSafeString(label, @"color")] ?: [UIColor colorWithWhite:0.85 alpha:1.0];
        UIColor *badgeTextColor = [GHIconRenderer readableTextColorOverColor:badgeColor];
        UIImage *badgeImage = [GHIconRenderer issueLabelBadgeWithText:labelName
                                                        backgroundColor:badgeColor
                                                              textColor:badgeTextColor
                                                              pointSize:kBadgePointSize];
        UIImageView *badgeView = [[UIImageView alloc] initWithImage:badgeImage];
        [self.contentView addSubview:badgeView];
        [newBadgeViews addObject:badgeView];
    }
    self.badgeImageViews = newBadgeViews;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = [[self class] contentWidthForWidth:width];
    CGFloat contentX = kMargin + kDotSize + kTitleToDotGap;

    CGSize titleSize = [(self.titleLabel.text.length > 0 ? self.titleLabel.text : @" ") sizeWithFont:self.titleLabel.font
                                                                                     constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                                                                         lineBreakMode:NSLineBreakByTruncatingTail];
    CGFloat titleHeight = MIN(titleSize.height, self.titleLabel.font.lineHeight * 1.3 * 2);

    self.statusDotView.frame = CGRectMake(kMargin, kMargin + (titleSize.height > 0 ? (self.titleLabel.font.lineHeight - kDotSize) / 2.0 : 0), kDotSize, kDotSize);
    self.titleLabel.frame = CGRectMake(contentX, kMargin, contentWidth, titleHeight);

    CGFloat subtitleY = kMargin + titleHeight + kRowSpacing;
    self.subtitleLabel.frame = CGRectMake(contentX, subtitleY, contentWidth, kSubtitleHeight);

    if (self.badgeImageViews.count > 0) {
        CGFloat badgesY = subtitleY + kSubtitleHeight + kRowSpacing;
        CGFloat x = 0, y = 0, rowHeight = 0;
        for (UIImageView *badgeView in self.badgeImageViews) {
            CGFloat badgeWidth = badgeView.image.size.width;
            CGFloat badgeHeight = badgeView.image.size.height;
            if (x > 0 && x + badgeWidth > contentWidth) {
                x = 0;
                y += rowHeight + kBadgeVSpacing;
                rowHeight = 0;
            }
            badgeView.frame = CGRectMake(contentX + x, badgesY + y, badgeWidth, badgeHeight);
            x += badgeWidth + kBadgeHSpacing;
            rowHeight = MAX(rowHeight, badgeHeight);
        }
    }
}

@end
