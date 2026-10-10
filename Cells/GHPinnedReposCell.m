#import "GHPinnedReposCell.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHIconRenderer.h"
#import "GHAvatarLoader.h"
#import "GHStarredRepoCell.h"

static const CGFloat kGHPinnedCardHeight = 152;
static const CGFloat kGHPinnedCardPadding = 14;
static const CGFloat kGHPinnedCardSpacing = 12;
static const CGFloat kGHPinnedInset = 16;
static const CGFloat kGHPinnedVerticalInset = 6;

@interface GHPinnedRepoCardView : UIControl
@property (nonatomic, strong) NSDictionary *repo;
@property (nonatomic, strong) UIImageView *ownerAvatarView;
@property (nonatomic, strong) UILabel *ownerLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIImageView *starView;
@property (nonatomic, strong) UILabel *starCountLabel;
@property (nonatomic, strong) UIView *languageDotView;
@property (nonatomic, strong) UILabel *languageLabel;
@end

@implementation GHPinnedRepoCardView

- (UILabel *)makeLabelWithFont:(UIFont *)font {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.userInteractionEnabled = NO;
    [self addSubview:label];
    return label;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 12.0;
        self.layer.borderWidth = 1.0;

        _ownerAvatarView = [[UIImageView alloc] init];
        _ownerAvatarView.layer.cornerRadius = 11.0;
        _ownerAvatarView.layer.masksToBounds = YES;
        _ownerAvatarView.userInteractionEnabled = NO;
        [self addSubview:_ownerAvatarView];

        _ownerLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:14]];
        _nameLabel = [self makeLabelWithFont:[UIFont boldSystemFontOfSize:17]];
        _descriptionLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:14]];
        _descriptionLabel.numberOfLines = 2;

        _starView = [[UIImageView alloc] initWithImage:[GHIconRenderer starIconWithColor:[UIColor colorWithRed:0.98 green:0.76 blue:0.10 alpha:1.0]
                                                                                    size:16
                                                                                  filled:YES]];
        _starView.userInteractionEnabled = NO;
        [self addSubview:_starView];

        _starCountLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:14]];

        _languageDotView = [[UIView alloc] init];
        _languageDotView.layer.cornerRadius = 6.0;
        _languageDotView.userInteractionEnabled = NO;
        [self addSubview:_languageDotView];

        _languageLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:14]];
    }
    return self;
}

- (NSString *)formattedCount:(NSNumber *)number {
    double value = [number respondsToSelector:@selector(doubleValue)] ? number.doubleValue : 0;
    if (value >= 1000) return [NSString stringWithFormat:@"%.1fk", value / 1000.0];
    return [NSString stringWithFormat:@"%.0f", value];
}

- (void)configureWithRepo:(NSDictionary *)repo {
    self.repo = repo;
    NSDictionary *owner = [[repo objectForKey:@"owner"] isKindOfClass:[NSDictionary class]] ? [repo objectForKey:@"owner"] : nil;
    NSString *ownerLogin = [[owner objectForKey:@"login"] isKindOfClass:[NSString class]] ? [owner objectForKey:@"login"] : @"";
    NSString *avatarURL = [[owner objectForKey:@"avatar_url"] isKindOfClass:[NSString class]] ? [owner objectForKey:@"avatar_url"] : nil;
    NSString *description = [[repo objectForKey:@"description"] isKindOfClass:[NSString class]] ? [repo objectForKey:@"description"] : nil;
    NSString *language = [[repo objectForKey:@"language"] isKindOfClass:[NSString class]] ? [repo objectForKey:@"language"] : nil;

    self.ownerLabel.text = ownerLogin;
    self.ownerAvatarView.image = nil;
    if (avatarURL.length > 0) {
        [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:self.ownerAvatarView];
    }
    self.nameLabel.text = [repo objectForKey:@"name"];
    self.descriptionLabel.text = description ?: @"";
    self.starCountLabel.text = [self formattedCount:[repo objectForKey:@"stargazers_count"]];
    self.languageLabel.text = language ?: @"";
    self.languageDotView.hidden = language.length == 0;
    self.languageDotView.backgroundColor = GHColorForLanguage(language);
    [self applyTheme];
    [self setNeedsLayout];
}

- (void)applyTheme {
    self.backgroundColor = GHCellBackgroundColor();
    self.layer.borderColor = GHSeparatorColor().CGColor;
    self.ownerAvatarView.backgroundColor = GHSeparatorColor();
    self.ownerLabel.textColor = GHSecondaryTextColor();
    self.nameLabel.textColor = GHPrimaryTextColor();
    self.descriptionLabel.textColor = GHSecondaryTextColor();
    self.starCountLabel.textColor = GHSecondaryTextColor();
    self.languageLabel.textColor = GHSecondaryTextColor();
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat contentWidth = width - kGHPinnedCardPadding * 2;
    CGFloat y = kGHPinnedCardPadding;

    self.ownerAvatarView.frame = CGRectMake(kGHPinnedCardPadding, y, 22, 22);
    self.ownerLabel.frame = CGRectMake(kGHPinnedCardPadding + 30, y, contentWidth - 30, 22);
    y += 22 + 8;

    self.nameLabel.frame = CGRectMake(kGHPinnedCardPadding, y, contentWidth, 22);
    y += 22 + 4;

    CGFloat statsY = self.bounds.size.height - kGHPinnedCardPadding - 20;
    CGFloat descriptionHeight = MAX(0, MIN(statsY - 6 - y, ceil(self.descriptionLabel.font.lineHeight * 2) + 2));
    self.descriptionLabel.frame = CGRectMake(kGHPinnedCardPadding, y, contentWidth, descriptionHeight);

    CGFloat x = kGHPinnedCardPadding;
    self.starView.frame = CGRectMake(x, statsY + 2, 16, 16);
    x += 16 + 6;
    CGSize starSize = [self.starCountLabel.text sizeWithFont:self.starCountLabel.font];
    self.starCountLabel.frame = CGRectMake(x, statsY, ceil(starSize.width), 20);
    x += ceil(starSize.width) + 16;

    self.languageDotView.frame = CGRectMake(x, statsY + 4, 12, 12);
    x += 12 + 6;
    self.languageLabel.frame = CGRectMake(x, statsY, MAX(0, width - kGHPinnedCardPadding - x), 20);
}

@end

@interface GHPinnedReposCell ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) NSMutableArray *cardViews;
@property (nonatomic, copy) NSString *reposSignature;
@end

@implementation GHPinnedReposCell

+ (CGFloat)cellHeight {
    return kGHPinnedCardHeight + kGHPinnedVerticalInset * 2;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        UIView *clearBackground = [[UIView alloc] init];
        clearBackground.backgroundColor = [UIColor clearColor];
        self.backgroundView = clearBackground;

        _cardViews = [NSMutableArray array];

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.alwaysBounceHorizontal = YES;
        _scrollView.scrollsToTop = NO;
        _scrollView.backgroundColor = [UIColor clearColor];
        [self addSubview:_scrollView];
    }
    return self;
}

- (NSString *)signatureForRepos:(NSArray *)repos {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSDictionary *repo in repos) {
        if (![repo isKindOfClass:[NSDictionary class]]) continue;
        id fullName = [repo objectForKey:@"full_name"];
        id stars = [repo objectForKey:@"stargazers_count"];
        [parts addObject:[NSString stringWithFormat:@"%@#%@", fullName, stars]];
    }
    return [parts componentsJoinedByString:@"|"];
}

- (void)configureWithRepos:(NSArray *)repos {
    NSString *signature = [self signatureForRepos:repos];
    if (self.cardViews.count > 0 && [signature isEqualToString:self.reposSignature]) {
        [self applyTheme];
        return;
    }
    self.reposSignature = signature;

    for (UIView *card in self.cardViews) [card removeFromSuperview];
    [self.cardViews removeAllObjects];

    for (NSDictionary *repo in repos) {
        if (![repo isKindOfClass:[NSDictionary class]]) continue;
        GHPinnedRepoCardView *card = [[GHPinnedRepoCardView alloc] initWithFrame:CGRectZero];
        [card configureWithRepo:repo];
        [card addTarget:self action:@selector(cardTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:card];
        [self.cardViews addObject:card];
    }
    self.scrollView.contentOffset = CGPointZero;
    [self setNeedsLayout];
}

- (void)applyTheme {
    for (GHPinnedRepoCardView *card in self.cardViews) [card applyTheme];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self bringSubviewToFront:self.scrollView];

    CGFloat width = self.bounds.size.width;
    self.scrollView.frame = CGRectMake(0, kGHPinnedVerticalInset, width, kGHPinnedCardHeight);

    NSUInteger count = self.cardViews.count;
    CGFloat available = width - kGHPinnedInset * 2;
    CGFloat cardWidth = count > 1 ? MIN(available - 36, 300) : MIN(available, 460);

    CGFloat x = kGHPinnedInset;
    for (GHPinnedRepoCardView *card in self.cardViews) {
        card.frame = CGRectMake(x, 0, cardWidth, kGHPinnedCardHeight);
        x += cardWidth + kGHPinnedCardSpacing;
    }
    CGFloat contentWidth = count > 0 ? x - kGHPinnedCardSpacing + kGHPinnedInset : width;
    self.scrollView.contentSize = CGSizeMake(MAX(contentWidth, width), kGHPinnedCardHeight);
}

- (void)cardTapped:(GHPinnedRepoCardView *)card {
    if (card.repo && self.onRepoSelected) self.onRepoSelected(card.repo);
}

@end
