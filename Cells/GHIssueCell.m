#import "GHIssueCell.h"
#import <QuartzCore/QuartzCore.h>
#import "GHIconRenderer.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHCompat.h"

static const CGFloat kMargin = 16;
static const CGFloat kVerticalMargin = 14;
static const CGFloat kIconSize = 20;
static const CGFloat kIconGap = 12;
static const CGFloat kTimeWidth = 46;
static const CGFloat kTitleFontSize = 16;
static const CGFloat kBadgeHSpacing = 6;
static const CGFloat kBadgeVSpacing = 6;
static const CGFloat kBadgePointSize = 12;
static const CGFloat kBadgesTopGap = 8;
static const NSInteger kTitleMaxLines = 3;

static NSString *GHSafeString(NSDictionary *dict, NSString *key) {
    id value = [dict isKindOfClass:[NSDictionary class]] ? dict[key] : nil;
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSString *GHRelativeDateString(NSString *isoString) {
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

    NSTimeInterval seconds = MAX(0, -[date timeIntervalSinceNow]);
    NSInteger minutes = (NSInteger)(seconds / 60);
    NSInteger hours = minutes / 60;
    NSInteger days = hours / 24;
    BOOL russian = [[GHLocalization sharedManager].languageCode isEqualToString:@"ru"];

    if (minutes < 1) return russian ? @"сейчас" : @"now";
    if (minutes < 60) return [NSString stringWithFormat:russian ? @"%ldмин" : @"%ldm", (long)minutes];
    if (hours < 24) return [NSString stringWithFormat:russian ? @"%ldч" : @"%ldh", (long)hours];
    if (days < 30) return [NSString stringWithFormat:russian ? @"%ldд" : @"%ldd", (long)days];
    if (days < 365) return [NSString stringWithFormat:russian ? @"%ldмес" : @"%ldmo", (long)(days / 30)];
    return [NSString stringWithFormat:russian ? @"%ldг" : @"%ldy", (long)(days / 365)];
}

static NSArray *GHValidLabels(NSDictionary *issue) {
    NSMutableArray *validLabels = [NSMutableArray array];
    NSArray *rawLabels = [issue[@"labels"] isKindOfClass:[NSArray class]] ? issue[@"labels"] : nil;
    for (NSDictionary *label in rawLabels) {
        if (![label isKindOfClass:[NSDictionary class]]) continue;
        if (GHSafeString(label, @"name").length > 0) [validLabels addObject:label];
    }
    return validLabels;
}

static NSInteger GHCommentCount(NSDictionary *issue) {
    id value = issue[@"comments"];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

static UIImage *GHCommentPillImage(NSInteger count, UIColor *textColor, UIColor *backgroundColor) {
    UIFont *font = [UIFont systemFontOfSize:kBadgePointSize + 1];
    NSString *text = [NSString stringWithFormat:@"%ld", (long)count];
    CGSize textSize = [text sizeWithFont:font];
    CGFloat iconSize = 13;
    CGFloat height = ceil(MAX(textSize.height, iconSize) + 6);
    CGFloat width = ceil(8 + iconSize + 5 + textSize.width + 9);

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 0.0);
    [backgroundColor setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height) cornerRadius:height / 2.0] fill];
    UIImage *icon = [GHIconRenderer commentIconWithColor:textColor size:iconSize];
    [icon drawInRect:CGRectMake(8, floor((height - iconSize) / 2.0), iconSize, iconSize)];
    [textColor set];
    [text drawAtPoint:CGPointMake(8 + iconSize + 5, floor((height - textSize.height) / 2.0)) withFont:font];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static UIImage *GHLabelBadgeImage(NSDictionary *label) {
    NSString *name = GHSafeString(label, @"name");
    UIColor *badgeColor = [GHIconRenderer colorFromHexString:GHSafeString(label, @"color")] ?: [UIColor colorWithWhite:0.85 alpha:1.0];
    UIColor *textColor = [GHIconRenderer readableTextColorOverColor:badgeColor];
    return [GHIconRenderer issueLabelBadgeWithText:name backgroundColor:badgeColor textColor:textColor pointSize:kBadgePointSize];
}

static UIImage *GHStateIconForIssue(NSDictionary *issue) {
    NSString *state = GHSafeString(issue, @"state");
    NSString *reason = GHSafeString(issue, @"state_reason");
    if (![state isEqualToString:@"closed"]) {
        return [GHIconRenderer issueOpenIconWithColor:[UIColor colorWithRed:0.16 green:0.65 blue:0.27 alpha:1.0] size:kIconSize];
    }
    if ([reason isEqualToString:@"not_planned"] || [reason isEqualToString:@"duplicate"]) {
        return [GHIconRenderer issueNotPlannedIconWithColor:[UIColor colorWithRed:0.52 green:0.55 blue:0.59 alpha:1.0] size:kIconSize];
    }
    return [GHIconRenderer issueClosedIconWithColor:[UIColor colorWithRed:0.51 green:0.31 blue:0.87 alpha:1.0] size:kIconSize];
}

static NSString *GHTitleText(NSDictionary *issue) {
    NSString *title = GHSafeString(issue, @"title");
    if (title.length == 0) title = GHL(@"(без заголовка)");
    id number = issue[@"number"];
    if ([number respondsToSelector:@selector(integerValue)]) {
        return [NSString stringWithFormat:@"%@ #%ld", title, (long)[number integerValue]];
    }
    return title;
}

static CGFloat GHTitleHeight(NSString *text, CGFloat width) {
    UIFont *font = [UIFont systemFontOfSize:kTitleFontSize];
    CGSize size = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    return MIN(ceil(size.height), ceil(font.lineHeight * kTitleMaxLines));
}

static CGFloat GHFlowHeight(NSArray *sizes, CGFloat maxWidth) {
    if (sizes.count == 0) return 0;
    CGFloat x = 0, y = 0, rowHeight = 0;
    for (NSValue *value in sizes) {
        CGSize size = [value CGSizeValue];
        if (x > 0 && x + size.width > maxWidth) {
            x = 0;
            y += rowHeight + kBadgeVSpacing;
            rowHeight = 0;
        }
        x += size.width + kBadgeHSpacing;
        rowHeight = MAX(rowHeight, size.height);
    }
    return y + rowHeight;
}

@interface GHIssueCell ()
@property (nonatomic, strong) UIImageView *stateIconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) NSArray *badgeImageViews;
@end

@implementation GHIssueCell

+ (CGFloat)titleWidthForWidth:(CGFloat)width {
    return MAX(60, width - kMargin - kIconSize - kIconGap - 8 - kTimeWidth - kMargin);
}

+ (CGFloat)badgesWidthForWidth:(CGFloat)width {
    return MAX(60, width - kMargin - kIconSize - kIconGap - kMargin);
}

+ (NSArray *)badgeSizesForIssue:(NSDictionary *)issue {
    NSMutableArray *sizes = [NSMutableArray array];
    for (NSDictionary *label in GHValidLabels(issue)) {
        UIImage *image = GHLabelBadgeImage(label);
        [sizes addObject:[NSValue valueWithCGSize:image.size]];
    }
    NSInteger comments = GHCommentCount(issue);
    if (comments > 0) {
        UIImage *pill = GHCommentPillImage(comments, [UIColor grayColor], [UIColor lightGrayColor]);
        [sizes addObject:[NSValue valueWithCGSize:pill.size]];
    }
    return sizes;
}

+ (CGFloat)heightForIssue:(NSDictionary *)issue width:(CGFloat)width {
    CGFloat height = kVerticalMargin;
    height += MAX(GHTitleHeight(GHTitleText(issue), [self titleWidthForWidth:width]), kIconSize);
    CGFloat badgesHeight = GHFlowHeight([self badgeSizesForIssue:issue], [self badgesWidthForWidth:width]);
    if (badgesHeight > 0) height += kBadgesTopGap + badgesHeight;
    height += kVerticalMargin;
    return ceil(height);
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;

        _stateIconView = [[UIImageView alloc] init];
        [self.contentView addSubview:_stateIconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:kTitleFontSize];
        _titleLabel.numberOfLines = kTitleMaxLines;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:_titleLabel];

        _timeLabel = [[UILabel alloc] init];
        _timeLabel.font = [UIFont systemFontOfSize:14];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        _timeLabel.backgroundColor = [UIColor clearColor];
        _timeLabel.adjustsFontSizeToFitWidth = YES;
        [self.contentView addSubview:_timeLabel];

        _badgeImageViews = @[];
    }
    return self;
}

- (void)configureWithIssue:(NSDictionary *)issue {
    self.stateIconView.image = GHStateIconForIssue(issue);

    NSString *titleText = GHTitleText(issue);
    self.titleLabel.text = titleText;
    self.titleLabel.textColor = GHPrimaryTextColor();
    if ([self.titleLabel respondsToSelector:@selector(setAttributedText:)]) {
        NSRange hashRange = [titleText rangeOfString:@" #" options:NSBackwardsSearch];
        NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:titleText];
        [attributed addAttribute:GHForegroundColorAttributeName() value:GHPrimaryTextColor() range:NSMakeRange(0, titleText.length)];
        [attributed addAttribute:GHFontAttributeName() value:[UIFont systemFontOfSize:kTitleFontSize] range:NSMakeRange(0, titleText.length)];
        if (hashRange.location != NSNotFound && issue[@"number"]) {
            [attributed addAttribute:GHForegroundColorAttributeName()
                               value:GHSecondaryTextColor()
                               range:NSMakeRange(hashRange.location, titleText.length - hashRange.location)];
        }
        self.titleLabel.attributedText = attributed;
    }

    self.timeLabel.text = GHRelativeDateString(GHSafeString(issue, @"created_at"));
    self.timeLabel.textColor = GHSecondaryTextColor();

    for (UIImageView *badgeView in self.badgeImageViews) [badgeView removeFromSuperview];
    NSMutableArray *newBadgeViews = [NSMutableArray array];
    for (NSDictionary *label in GHValidLabels(issue)) {
        UIImageView *badgeView = [[UIImageView alloc] initWithImage:GHLabelBadgeImage(label)];
        [self.contentView addSubview:badgeView];
        [newBadgeViews addObject:badgeView];
    }
    NSInteger comments = GHCommentCount(issue);
    if (comments > 0) {
        BOOL dark = [GHThemeManager sharedManager].darkModeEnabled;
        UIColor *pillBackground = dark ? [UIColor colorWithWhite:1.0 alpha:0.10] : [UIColor colorWithWhite:0.0 alpha:0.06];
        UIImageView *pillView = [[UIImageView alloc] initWithImage:GHCommentPillImage(comments, GHSecondaryTextColor(), pillBackground)];
        [self.contentView addSubview:pillView];
        [newBadgeViews addObject:pillView];
    }
    self.badgeImageViews = newBadgeViews;

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat textX = kMargin + kIconSize + kIconGap;
    CGFloat titleWidth = [[self class] titleWidthForWidth:width];
    CGFloat titleHeight = GHTitleHeight(self.titleLabel.text ?: @" ", titleWidth);
    CGFloat lineHeight = self.titleLabel.font.lineHeight;

    self.stateIconView.frame = CGRectMake(kMargin, kVerticalMargin + floor((lineHeight - kIconSize) / 2.0), kIconSize, kIconSize);
    self.titleLabel.frame = CGRectMake(textX, kVerticalMargin, titleWidth, titleHeight);
    self.timeLabel.frame = CGRectMake(width - kMargin - kTimeWidth, kVerticalMargin, kTimeWidth, ceil(lineHeight));

    CGFloat badgesY = kVerticalMargin + MAX(titleHeight, kIconSize) + kBadgesTopGap;
    CGFloat maxWidth = [[self class] badgesWidthForWidth:width];
    CGFloat x = 0, y = 0, rowHeight = 0;
    for (UIImageView *badgeView in self.badgeImageViews) {
        CGSize size = badgeView.image.size;
        if (x > 0 && x + size.width > maxWidth) {
            x = 0;
            y += rowHeight + kBadgeVSpacing;
            rowHeight = 0;
        }
        badgeView.frame = CGRectMake(textX + x, badgesY + y, size.width, size.height);
        x += size.width + kBadgeHSpacing;
        rowHeight = MAX(rowHeight, size.height);
    }
}

@end
