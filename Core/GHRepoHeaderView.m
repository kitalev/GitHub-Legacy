#import "GHRepoHeaderView.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHAvatarLoader.h"
#import "GHCompat.h"

static const CGFloat kGHRepoPadding = 16;
static const CGFloat kGHRepoIconSize = 16;
static const CGFloat kGHRepoRowHeight = 24;

static NSString *GHRepoPluralCaption(NSInteger count, NSString *ruOne, NSString *ruFew, NSString *ruMany, NSString *enOne, NSString *enMany) {
    if (![[GHLocalization sharedManager].languageCode isEqualToString:@"ru"]) {
        return count == 1 ? enOne : enMany;
    }
    NSInteger mod10 = count % 10;
    NSInteger mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return ruOne;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return ruFew;
    return ruMany;
}

static UIColor *GHRepoStarYellow(void) {
    return [UIColor colorWithRed:0.89 green:0.70 blue:0.16 alpha:1.0];
}

@interface GHRepoHeaderView ()
@property (nonatomic, strong) UIControl *ownerControl;
@property (nonatomic, strong) UIImageView *ownerAvatarView;
@property (nonatomic, strong) UILabel *ownerLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIControl *homepageControl;
@property (nonatomic, strong) UIImageView *homepageIconView;
@property (nonatomic, strong) UILabel *homepageLabel;
@property (nonatomic, strong) UIImageView *starsIconView;
@property (nonatomic, strong) UILabel *starsLabel;
@property (nonatomic, strong) UIButton *forksButton;
@property (nonatomic, strong) UIImageView *forksIconView;
@property (nonatomic, strong) UIButton *starButton;

@property (nonatomic, strong) NSDictionary *repo;
@property (nonatomic, strong) NSURL *homepageURL;
@property (nonatomic, assign) GHRepoStarState starState;
@property (nonatomic, copy) NSString *requestedAvatarURL;
@end

@implementation GHRepoHeaderView

- (UILabel *)makeLabelWithFont:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.userInteractionEnabled = NO;
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        _ownerControl = [[UIControl alloc] init];
        [_ownerControl addTarget:self action:@selector(ownerTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_ownerControl];

        _ownerAvatarView = [[UIImageView alloc] init];
        _ownerAvatarView.layer.cornerRadius = 12;
        _ownerAvatarView.layer.masksToBounds = YES;
        _ownerAvatarView.userInteractionEnabled = NO;
        [_ownerControl addSubview:_ownerAvatarView];

        _ownerLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:17]];
        [_ownerControl addSubview:_ownerLabel];

        _nameLabel = [self makeLabelWithFont:[UIFont boldSystemFontOfSize:28]];
        _nameLabel.numberOfLines = 0;
        _nameLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:_nameLabel];

        _descriptionLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:16]];
        _descriptionLabel.numberOfLines = 0;
        _descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:_descriptionLabel];

        _homepageControl = [[UIControl alloc] init];
        [_homepageControl addTarget:self action:@selector(homepageTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_homepageControl];

        _homepageIconView = [[UIImageView alloc] init];
        _homepageIconView.contentMode = UIViewContentModeCenter;
        _homepageIconView.userInteractionEnabled = NO;
        [_homepageControl addSubview:_homepageIconView];

        _homepageLabel = [self makeLabelWithFont:[UIFont boldSystemFontOfSize:16]];
        [_homepageControl addSubview:_homepageLabel];

        _starsIconView = [[UIImageView alloc] init];
        _starsIconView.contentMode = UIViewContentModeCenter;
        [self addSubview:_starsIconView];

        _starsLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:16]];
        [self addSubview:_starsLabel];

        _forksIconView = [[UIImageView alloc] init];
        _forksIconView.contentMode = UIViewContentModeCenter;
        [self addSubview:_forksIconView];

        _forksButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _forksButton.titleLabel.font = [UIFont systemFontOfSize:16];
        _forksButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_forksButton addTarget:self action:@selector(forksTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_forksButton];

        _starButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _starButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _starButton.layer.cornerRadius = 8;
        _starButton.layer.masksToBounds = YES;
        _starButton.layer.borderWidth = 1;
        _starButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
        _starButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
        [_starButton addTarget:self action:@selector(starButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_starButton];

        _starState = GHRepoStarStateHidden;
        [self applyTheme];
    }
    return self;
}

#pragma mark - Data

- (NSString *)stringIn:(NSDictionary *)dict forKey:(NSString *)key {
    id value = [dict isKindOfClass:[NSDictionary class]] ? [dict objectForKey:key] : nil;
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

- (NSInteger)integerIn:(NSDictionary *)dict forKey:(NSString *)key {
    id value = [dict isKindOfClass:[NSDictionary class]] ? [dict objectForKey:key] : nil;
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

- (NSString *)formattedCount:(NSInteger)count {
    if (count >= 1000) return [NSString stringWithFormat:@"%.1fk", count / 1000.0];
    return [NSString stringWithFormat:@"%ld", (long)count];
}

- (void)configureWithRepo:(NSDictionary *)repo {
    self.repo = repo;
    [self reloadContent];
}

- (void)reloadContent {
    NSDictionary *owner = [[self.repo objectForKey:@"owner"] isKindOfClass:[NSDictionary class]] ? [self.repo objectForKey:@"owner"] : nil;
    self.ownerLabel.text = [self stringIn:owner forKey:@"login"] ?: @"";
    self.ownerControl.hidden = self.ownerLabel.text.length == 0;

    NSString *avatar = [self stringIn:owner forKey:@"avatar_url"];
    if (avatar.length > 0 && ![avatar isEqualToString:self.requestedAvatarURL]) {
        self.requestedAvatarURL = avatar;
        [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatar intoImageView:self.ownerAvatarView];
    }

    self.nameLabel.text = [self stringIn:self.repo forKey:@"name"] ?: @"";
    self.descriptionLabel.text = [self stringIn:self.repo forKey:@"description"] ?: @"";

    NSString *homepage = [self stringIn:self.repo forKey:@"homepage"];
    self.homepageURL = nil;
    if (homepage) {
        NSString *lower = homepage.lowercaseString;
        NSString *full = ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"]) ? homepage : [@"http://" stringByAppendingString:homepage];
        self.homepageURL = [NSURL URLWithString:full] ?: [NSURL URLWithString:[full stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    }
    self.homepageLabel.text = homepage ?: @"";
    self.homepageControl.hidden = self.homepageURL == nil;

    NSInteger stars = [self integerIn:self.repo forKey:@"stargazers_count"];
    NSInteger forks = [self integerIn:self.repo forKey:@"forks_count"];
    [self setCountLabel:self.starsLabel count:stars
                caption:GHRepoPluralCaption(stars, @"звезда", @"звезды", @"звёзд", @"star", @"stars")];
    [self setCountButton:self.forksButton count:forks
                 caption:GHRepoPluralCaption(forks, @"форк", @"форка", @"форков", @"fork", @"forks")];

    [self updateStarButton];
    [self setNeedsLayout];
}

- (NSAttributedString *)attributedCount:(NSInteger)count caption:(NSString *)caption {
    NSString *countText = [self formattedCount:count];
    NSString *text = [NSString stringWithFormat:@"%@ %@", countText, caption];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange countRange = NSMakeRange(0, countText.length);
    NSRange captionRange = NSMakeRange(countText.length, text.length - countText.length);
    [attributed addAttribute:GHFontAttributeName() value:[UIFont boldSystemFontOfSize:16] range:countRange];
    [attributed addAttribute:GHForegroundColorAttributeName() value:GHPrimaryTextColor() range:countRange];
    [attributed addAttribute:GHFontAttributeName() value:[UIFont systemFontOfSize:16] range:captionRange];
    [attributed addAttribute:GHForegroundColorAttributeName() value:GHSecondaryTextColor() range:captionRange];
    return attributed;
}

- (void)setCountLabel:(UILabel *)label count:(NSInteger)count caption:(NSString *)caption {
    NSString *plain = [NSString stringWithFormat:@"%@ %@", [self formattedCount:count], caption];
    label.text = plain;
    if ([label respondsToSelector:@selector(setAttributedText:)]) {
        label.attributedText = [self attributedCount:count caption:caption];
    }
}

- (void)setCountButton:(UIButton *)button count:(NSInteger)count caption:(NSString *)caption {
    NSString *plain = [NSString stringWithFormat:@"%@ %@", [self formattedCount:count], caption];
    [button setTitle:plain forState:UIControlStateNormal];
    [button setTitleColor:GHSecondaryTextColor() forState:UIControlStateNormal];
    [button gh_setAttributedTitle:[self attributedCount:count caption:caption] forState:UIControlStateNormal];
}

- (void)setStarState:(GHRepoStarState)state {
    _starState = state;
    [self updateStarButton];
    [self setNeedsLayout];
}

- (void)updateStarButton {
    self.starButton.hidden = self.starState == GHRepoStarStateHidden;
    self.starButton.enabled = self.starState == GHRepoStarStateStarred || self.starState == GHRepoStarStateNotStarred || self.starState == GHRepoStarStateError;

    NSString *title = nil;
    UIImage *image = nil;
    UIColor *titleColor = GHPrimaryTextColor();
    switch (self.starState) {
        case GHRepoStarStateStarred:
            title = GHL(@"В избранном");
            image = [GHIconRenderer starIconWithColor:GHRepoStarYellow() size:18 filled:YES];
            break;
        case GHRepoStarStateNotStarred:
            title = GHL(@"В избранное");
            image = [GHIconRenderer starIconWithColor:GHSecondaryTextColor() size:18 filled:NO];
            break;
        case GHRepoStarStateError:
            title = GHL(@"Не удалось проверить");
            image = [GHIconRenderer starIconWithColor:GHSecondaryTextColor() size:18 filled:NO];
            titleColor = [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
            break;
        default:
            title = @"…";
            image = [GHIconRenderer starIconWithColor:GHSecondaryTextColor() size:18 filled:NO];
            titleColor = GHSecondaryTextColor();
            break;
    }
    [self.starButton setTitle:title forState:UIControlStateNormal];
    [self.starButton setTitleColor:titleColor forState:UIControlStateNormal];
    [self.starButton setTitleColor:GHSecondaryTextColor() forState:UIControlStateDisabled];
    [self.starButton setImage:image forState:UIControlStateNormal];
    [self.starButton setImage:image forState:UIControlStateDisabled];
}

#pragma mark - Theme

- (void)applyTheme {
    self.ownerAvatarView.backgroundColor = GHSeparatorColor();
    self.ownerLabel.textColor = GHSecondaryTextColor();
    self.nameLabel.textColor = GHPrimaryTextColor();
    self.descriptionLabel.textColor = GHSecondaryTextColor();
    self.homepageIconView.image = [GHIconRenderer linkIconWithColor:GHSecondaryTextColor() size:kGHRepoIconSize];
    self.homepageLabel.textColor = GHPrimaryTextColor();
    self.starsIconView.image = [GHIconRenderer starIconWithColor:GHSecondaryTextColor() size:kGHRepoIconSize filled:NO];
    self.forksIconView.image = [GHIconRenderer forkIconWithColor:GHSecondaryTextColor() size:kGHRepoIconSize];
    self.starButton.backgroundColor = GHCellBackgroundColor();
    self.starButton.layer.borderColor = GHSeparatorColor().CGColor;
    if (self.repo) [self reloadContent];
}

#pragma mark - Layout

- (CGFloat)heightForWidth:(CGFloat)width {
    return [self layoutForWidth:width apply:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

- (CGFloat)textHeight:(NSString *)text font:(UIFont *)font width:(CGFloat)width {
    if (text.length == 0) return 0;
    return ceil([text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping].height);
}

- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat contentWidth = MAX(width - kGHRepoPadding * 2, 100);
    CGFloat y = kGHRepoPadding + 4;

    if (!self.ownerControl.hidden) {
        if (apply) {
            CGFloat labelWidth = MIN(ceil([self.ownerLabel.text sizeWithFont:self.ownerLabel.font].width), contentWidth - 32);
            self.ownerControl.frame = CGRectMake(kGHRepoPadding, y, 32 + labelWidth, 24);
            self.ownerAvatarView.frame = CGRectMake(0, 0, 24, 24);
            self.ownerLabel.frame = CGRectMake(32, 0, labelWidth, 24);
        }
        y += 24 + 10;
    }

    CGFloat nameHeight = MAX([self textHeight:self.nameLabel.text font:self.nameLabel.font width:contentWidth], 34);
    if (apply) self.nameLabel.frame = CGRectMake(kGHRepoPadding, y, contentWidth, nameHeight);
    y += nameHeight + 10;

    CGFloat descriptionHeight = [self textHeight:self.descriptionLabel.text font:self.descriptionLabel.font width:contentWidth];
    if (apply) self.descriptionLabel.frame = CGRectMake(kGHRepoPadding, y, contentWidth, descriptionHeight);
    if (descriptionHeight > 0) y += descriptionHeight + 16;

    if (!self.homepageControl.hidden) {
        if (apply) {
            CGFloat labelWidth = MIN(ceil([self.homepageLabel.text sizeWithFont:self.homepageLabel.font].width), contentWidth - kGHRepoIconSize - 10);
            self.homepageControl.frame = CGRectMake(kGHRepoPadding, y, kGHRepoIconSize + 10 + labelWidth, kGHRepoRowHeight);
            self.homepageIconView.frame = CGRectMake(0, floor((kGHRepoRowHeight - kGHRepoIconSize) / 2.0), kGHRepoIconSize, kGHRepoIconSize);
            self.homepageLabel.frame = CGRectMake(kGHRepoIconSize + 10, 0, labelWidth, kGHRepoRowHeight);
        }
        y += kGHRepoRowHeight + 10;
    }

    if (apply) {
        CGFloat iconY = y + floor((kGHRepoRowHeight - kGHRepoIconSize) / 2.0);
        CGFloat x = kGHRepoPadding;
        self.starsIconView.frame = CGRectMake(x, iconY, kGHRepoIconSize, kGHRepoIconSize);
        x += kGHRepoIconSize + 8;
        CGFloat starsWidth = ceil([self.starsLabel.text sizeWithFont:[UIFont boldSystemFontOfSize:16]].width);
        self.starsLabel.frame = CGRectMake(x, y, starsWidth, kGHRepoRowHeight);
        x += starsWidth + 22;
        self.forksIconView.frame = CGRectMake(x, iconY, kGHRepoIconSize, kGHRepoIconSize);
        x += kGHRepoIconSize + 8;
        CGFloat forksWidth = MIN(ceil([[self.forksButton titleForState:UIControlStateNormal] sizeWithFont:[UIFont boldSystemFontOfSize:16]].width) + 4,
                                 MAX(width - kGHRepoPadding - x, 40));
        self.forksButton.frame = CGRectMake(x, y, forksWidth, kGHRepoRowHeight);
    }
    y += kGHRepoRowHeight;

    if (!self.starButton.hidden) {
        y += 16;
        if (apply) self.starButton.frame = CGRectMake(kGHRepoPadding, y, contentWidth, 40);
        y += 40;
    }

    y += 18;
    return y;
}

#pragma mark - Actions

- (void)ownerTapped {
    if (self.onOwnerTapped) self.onOwnerTapped();
}

- (void)homepageTapped {
    if (self.homepageURL && self.onHomepageTapped) self.onHomepageTapped(self.homepageURL);
}

- (void)forksTapped {
    if (self.onForksTapped) self.onForksTapped();
}

- (void)starButtonTapped {
    if (self.onStarButtonTapped) self.onStarButtonTapped();
}

@end
