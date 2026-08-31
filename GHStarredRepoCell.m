#import "GHStarredRepoCell.h"
#import "GHAvatarLoader.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMargin = 16;
static const CGFloat kAvatarSize = 20;
static const CGFloat kOwnerRowHeight = 20;
static const CGFloat kNameRowHeight = 24;
static const CGFloat kStatsRowHeight = 20;
static const CGFloat kRowSpacing = 6;

static UIColor *GHColorForLanguage(NSString *language) {
    NSDictionary *colors = @{
        @"JavaScript": [UIColor colorWithRed:0.94 green:0.84 blue:0.20 alpha:1.0],
        @"TypeScript": [UIColor colorWithRed:0.18 green:0.47 blue:0.78 alpha:1.0],
        @"Python": [UIColor colorWithRed:0.22 green:0.45 blue:0.69 alpha:1.0],
        @"Swift": [UIColor colorWithRed:0.96 green:0.42 blue:0.14 alpha:1.0],
        @"Objective-C": [UIColor colorWithRed:0.26 green:0.53 blue:0.96 alpha:1.0],
        @"Kotlin": [UIColor colorWithRed:0.65 green:0.48 blue:1.0 alpha:1.0],
        @"Java": [UIColor colorWithRed:0.69 green:0.30 blue:0.15 alpha:1.0],
        @"C++": [UIColor colorWithRed:0.96 green:0.42 blue:0.55 alpha:1.0],
        @"C": [UIColor colorWithWhite:0.55 alpha:1.0],
        @"Go": [UIColor colorWithRed:0.0 green:0.68 blue:0.94 alpha:1.0],
        @"Ruby": [UIColor colorWithRed:0.70 green:0.11 blue:0.17 alpha:1.0],
        @"PHP": [UIColor colorWithRed:0.31 green:0.36 blue:0.62 alpha:1.0],
        @"C#": [UIColor colorWithRed:0.13 green:0.55 blue:0.13 alpha:1.0],
        @"Rust": [UIColor colorWithRed:0.87 green:0.46 blue:0.32 alpha:1.0],
        @"HTML": [UIColor colorWithRed:0.89 green:0.30 blue:0.15 alpha:1.0],
        @"CSS": [UIColor colorWithRed:0.33 green:0.42 blue:0.94 alpha:1.0],
        @"Shell": [UIColor colorWithRed:0.35 green:0.62 blue:0.35 alpha:1.0],
        @"Dart": [UIColor colorWithRed:0.0 green:0.68 blue:0.94 alpha:1.0],
    };
    return colors[language] ?: [UIColor colorWithWhite:0.6 alpha:1.0];
}

@interface GHStarredRepoCell ()
@property (nonatomic, strong) UIImageView *ownerAvatarView;
@property (nonatomic, strong) UILabel *ownerLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UILabel *starIconLabel;
@property (nonatomic, strong) UILabel *starCountLabel;
@property (nonatomic, strong) UIView *languageDotView;
@property (nonatomic, strong) UILabel *languageLabel;
@end

@implementation GHStarredRepoCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;

        self.ownerAvatarView = [[UIImageView alloc] init];
        self.ownerAvatarView.layer.cornerRadius = kAvatarSize / 2.0;
        self.ownerAvatarView.layer.masksToBounds = YES;
        self.ownerAvatarView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:self.ownerAvatarView];

        self.ownerLabel = [[UILabel alloc] init];
        self.ownerLabel.font = [UIFont systemFontOfSize:13];
        self.ownerLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.ownerLabel];

        self.nameLabel = [[UILabel alloc] init];
        self.nameLabel.font = [UIFont boldSystemFontOfSize:17];
        self.nameLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.nameLabel];

        self.descriptionLabel = [[UILabel alloc] init];
        self.descriptionLabel.font = [UIFont systemFontOfSize:14];
        self.descriptionLabel.numberOfLines = 3;
        self.descriptionLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.descriptionLabel];

        self.starIconLabel = [[UILabel alloc] init];
        self.starIconLabel.font = [UIFont systemFontOfSize:14];
        self.starIconLabel.text = @"★";
        self.starIconLabel.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.0 alpha:1.0];
        self.starIconLabel.backgroundColor = [UIColor clearColor];
        [self.starIconLabel sizeToFit];
        [self.contentView addSubview:self.starIconLabel];

        self.starCountLabel = [[UILabel alloc] init];
        self.starCountLabel.font = [UIFont systemFontOfSize:13];
        self.starCountLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.starCountLabel];

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

+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width {
    CGFloat contentWidth = width - kMargin * 2;

    NSString *description = [repo[@"description"] isKindOfClass:[NSString class]] ? repo[@"description"] : nil;
    CGFloat descriptionHeight = 0;
    if (description.length > 0) {
        CGSize size = [description sizeWithFont:[UIFont systemFontOfSize:14]
                               constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                   lineBreakMode:NSLineBreakByTruncatingTail];

        descriptionHeight = MIN(size.height, 14 * 1.3 * 3);
    }

    CGFloat height = kMargin;
    height += kOwnerRowHeight + kRowSpacing;
    height += kNameRowHeight;
    if (descriptionHeight > 0) {
        height += kRowSpacing + descriptionHeight;
    }
    height += kRowSpacing + kStatsRowHeight;
    height += kMargin;

    return height;
}

- (void)configureWithRepo:(NSDictionary *)repo {
    NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
    NSString *ownerLogin = [owner[@"login"] isKindOfClass:[NSString class]] ? owner[@"login"] : @"";
    NSString *avatarURL = owner[@"avatar_url"];
    NSString *name = [repo[@"name"] isKindOfClass:[NSString class]] ? repo[@"name"] : repo[@"full_name"];
    NSString *description = [repo[@"description"] isKindOfClass:[NSString class]] ? repo[@"description"] : nil;
    NSNumber *stars = repo[@"stargazers_count"];
    NSString *language = [repo[@"language"] isKindOfClass:[NSString class]] ? repo[@"language"] : nil;

    self.ownerLabel.text = ownerLogin;
    self.ownerLabel.textColor = GHSecondaryTextColor();
    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:self.ownerAvatarView];

    self.nameLabel.text = name;
    self.nameLabel.textColor = GHPrimaryTextColor();

    self.descriptionLabel.text = description ?: @"";
    self.descriptionLabel.textColor = GHSecondaryTextColor();
    self.descriptionLabel.hidden = description.length == 0;

    self.starCountLabel.text = [self formattedCount:stars];
    self.starCountLabel.textColor = GHSecondaryTextColor();

    self.languageDotView.hidden = language.length == 0;
    self.languageLabel.hidden = language.length == 0;
    self.languageLabel.text = language ?: @"";
    self.languageLabel.textColor = GHSecondaryTextColor();
    self.languageDotView.backgroundColor = GHColorForLanguage(language);

    GHApplyDisclosureIndicator(self);

    [self setNeedsLayout];
}

- (NSString *)formattedCount:(NSNumber *)number {
    double value = number.doubleValue;
    if (value >= 1000) {
        double thousands = value / 1000.0;
        return [NSString stringWithFormat:@"%.1fk", thousands];
    }
    return [NSString stringWithFormat:@"%.0f", value];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = width - kMargin * 2;

    self.ownerAvatarView.frame = CGRectMake(kMargin, kMargin, kAvatarSize, kAvatarSize);
    CGFloat ownerLabelX = kMargin + kAvatarSize + 8;
    self.ownerLabel.frame = CGRectMake(ownerLabelX, kMargin, width - ownerLabelX - kMargin, kOwnerRowHeight);

    CGFloat nameY = kMargin + kOwnerRowHeight + kRowSpacing;
    self.nameLabel.frame = CGRectMake(kMargin, nameY, contentWidth, kNameRowHeight);

    CGFloat descriptionY = nameY + kNameRowHeight;
    CGFloat descriptionHeight = 0;
    if (!self.descriptionLabel.hidden) {
        descriptionY += kRowSpacing;
        CGSize size = [self.descriptionLabel.text sizeWithFont:self.descriptionLabel.font
                                               constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                                   lineBreakMode:NSLineBreakByTruncatingTail];
        descriptionHeight = MIN(size.height, self.descriptionLabel.font.lineHeight * 1.3 * 3);
        self.descriptionLabel.frame = CGRectMake(kMargin, descriptionY, contentWidth, descriptionHeight);
    } else {
        self.descriptionLabel.frame = CGRectMake(kMargin, descriptionY, contentWidth, 0);
    }

    CGFloat statsY = descriptionY + descriptionHeight + kRowSpacing;

    CGFloat x = kMargin;
    CGRect starIconFrame = self.starIconLabel.frame;
    starIconFrame.origin = CGPointMake(x, statsY + (kStatsRowHeight - starIconFrame.size.height) / 2.0);
    self.starIconLabel.frame = starIconFrame;
    x += starIconFrame.size.width + 6;

    [self.starCountLabel sizeToFit];
    CGRect starCountFrame = self.starCountLabel.frame;
    starCountFrame.origin = CGPointMake(x, statsY + (kStatsRowHeight - starCountFrame.size.height) / 2.0);
    self.starCountLabel.frame = starCountFrame;
    x += starCountFrame.size.width + 16;

    if (!self.languageDotView.hidden) {
        self.languageDotView.frame = CGRectMake(x, statsY + (kStatsRowHeight - 10) / 2.0, 10, 10);
        x += 10 + 6;

        [self.languageLabel sizeToFit];
        CGRect languageFrame = self.languageLabel.frame;
        languageFrame.origin = CGPointMake(x, statsY + (kStatsRowHeight - languageFrame.size.height) / 2.0);
        self.languageLabel.frame = languageFrame;
        x += languageFrame.size.width + 16;
    }
}

@end
