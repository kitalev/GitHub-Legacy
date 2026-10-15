#import "GHProfileHeaderView.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHCompat.h"

static const CGFloat kGHProfilePadding = 16;
static const CGFloat kGHProfileAvatarSize = 72;
static const CGFloat kGHProfileRowHeight = 24;
static const CGFloat kGHProfileRowSpacing = 6;
static const CGFloat kGHProfileIconSize = 16;

typedef NS_ENUM(NSInteger, GHProfileInfoIcon) {
    GHProfileInfoIconOrganization,
    GHProfileInfoIconLocation,
    GHProfileInfoIconMail,
    GHProfileInfoIconLink
};

@interface GHProfileInfoRow : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, assign) GHProfileInfoIcon iconKind;
@end

@implementation GHProfileInfoRow

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeCenter;
        [self addSubview:_iconView];

        _textLabel = [[UILabel alloc] init];
        _textLabel.backgroundColor = [UIColor clearColor];
        _textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_textLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.bounds.size.height;
    self.iconView.frame = CGRectMake(0, floor((height - kGHProfileIconSize) / 2.0), kGHProfileIconSize, kGHProfileIconSize);
    CGFloat textX = kGHProfileIconSize + 10;
    self.textLabel.frame = CGRectMake(textX, 0, self.bounds.size.width - textX, height);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.textLabel.alpha = highlighted ? 0.5 : 1.0;
}

@end

@interface GHProfileHeaderView ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *loginLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) UIView *statusView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *statusBadge;
@property (nonatomic, strong) UIImageView *statusEmojiView;
@property (nonatomic, copy) NSString *statusEmojiURL;
@property (nonatomic, strong) NSMutableArray *infoRows;
@property (nonatomic, strong) UIImageView *followersIconView;
@property (nonatomic, strong) UIButton *followersButton;
@property (nonatomic, strong) UILabel *followersSeparatorLabel;
@property (nonatomic, strong) UIButton *followingButton;

@property (nonatomic, strong) NSDictionary *userInfo;
@property (nonatomic, copy) NSString *fallbackLogin;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *requestedAvatarURL;
@end

@implementation GHProfileHeaderView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        _avatarView = [[UIImageView alloc] init];
        _avatarView.layer.cornerRadius = kGHProfileAvatarSize / 2.0;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_avatarView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:24];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        if ([_nameLabel respondsToSelector:@selector(setMinimumScaleFactor:)]) {
            _nameLabel.minimumScaleFactor = 0.7;
        } else {
            _nameLabel.minimumFontSize = 24.0 * 0.7;
        }
        [self addSubview:_nameLabel];

        _loginLabel = [[UILabel alloc] init];
        _loginLabel.backgroundColor = [UIColor clearColor];
        _loginLabel.font = [UIFont systemFontOfSize:18];
        _loginLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_loginLabel];

        _bioLabel = [[UILabel alloc] init];
        _bioLabel.backgroundColor = [UIColor clearColor];
        _bioLabel.font = [UIFont systemFontOfSize:15];
        _bioLabel.numberOfLines = 0;
        _bioLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self addSubview:_bioLabel];

        _statusView = [[UIView alloc] init];
        _statusView.layer.cornerRadius = 15;
        _statusView.layer.borderWidth = 1;
        _statusView.hidden = YES;
        [self addSubview:_statusView];

        _statusLabel = [[UILabel alloc] init];
        _statusLabel.backgroundColor = [UIColor clearColor];
        _statusLabel.font = [UIFont systemFontOfSize:14];
        _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_statusView addSubview:_statusLabel];

        _statusBadge = [[UIView alloc] init];
        _statusBadge.layer.cornerRadius = 14;
        _statusBadge.layer.borderWidth = 1;
        _statusBadge.hidden = YES;
        [self addSubview:_statusBadge];

        _statusEmojiView = [[UIImageView alloc] init];
        _statusEmojiView.contentMode = UIViewContentModeScaleAspectFit;
        [_statusBadge addSubview:_statusEmojiView];

        _infoRows = [NSMutableArray array];

        _followersIconView = [[UIImageView alloc] init];
        _followersIconView.contentMode = UIViewContentModeCenter;
        [self addSubview:_followersIconView];

        _followersButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _followersButton.titleLabel.font = [UIFont systemFontOfSize:15];
        [_followersButton addTarget:self action:@selector(followersTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_followersButton];

        _followersSeparatorLabel = [[UILabel alloc] init];
        _followersSeparatorLabel.backgroundColor = [UIColor clearColor];
        _followersSeparatorLabel.font = [UIFont boldSystemFontOfSize:15];
        _followersSeparatorLabel.text = @"•";
        [self addSubview:_followersSeparatorLabel];

        _followingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _followingButton.titleLabel.font = [UIFont systemFontOfSize:15];
        [_followingButton addTarget:self action:@selector(followingTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_followingButton];

        [self applyTheme];
    }
    return self;
}

- (void)setActionButton:(UIButton *)actionButton {
    if (_actionButton == actionButton) return;
    [_actionButton removeFromSuperview];
    _actionButton = actionButton;
    if (actionButton) [self addSubview:actionButton];
    [self setNeedsLayout];
}

#pragma mark - Data

- (NSString *)stringForKey:(NSString *)key {
    id value = [self.userInfo objectForKey:key];
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : nil;
}

- (NSNumber *)numberForKey:(NSString *)key {
    id value = [self.userInfo objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? value : @0;
}

- (void)configureWithUserInfo:(NSDictionary *)userInfo fallbackLogin:(NSString *)login loading:(BOOL)loading {
    self.userInfo = userInfo;
    self.fallbackLogin = login;
    self.loading = loading;
    [self reloadContent];
}

- (void)reloadContent {
    NSString *name = [self stringForKey:@"name"];
    NSString *login = [self stringForKey:@"login"] ?: self.fallbackLogin;
    BOOL hasData = self.userInfo != nil;

    self.nameLabel.text = self.loading && !self.userInfo ? GHL(@"Загрузка…") : (name ?: login ?: @"—");
    self.loginLabel.text = login ?: @"";
    self.bioLabel.text = hasData ? ([self stringForKey:@"bio"] ?: @"") : @"";
    self.statusLabel.text = hasData ? [self statusText] : @"";
    self.statusView.hidden = self.statusLabel.text.length == 0;
    [self updateStatusBadge:hasData];

    [self loadAvatarIfNeeded];
    [self rebuildInfoRows:hasData];

    self.followersIconView.hidden = !hasData;
    self.followersButton.hidden = !hasData;
    self.followersSeparatorLabel.hidden = !hasData;
    self.followingButton.hidden = !hasData;
    if (hasData) {
        [self setCountButton:self.followersButton count:[self numberForKey:@"followers"] caption:GHL(@"подписчиков")];
        [self setCountButton:self.followingButton count:[self numberForKey:@"following"] caption:GHL(@"подписок")];
    }

    [self setNeedsLayout];
}

- (NSString *)statusEmojiImageURL {
    NSString *emojiHTML = [self.statusInfo[@"emojiHTML"] isKindOfClass:[NSString class]] ? self.statusInfo[@"emojiHTML"] : @"";
    if (emojiHTML.length == 0) return nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?:fallback-src|src)=\"([^\"]+)\"" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:emojiHTML options:0 range:NSMakeRange(0, emojiHTML.length)];
    if (match == nil) return nil;
    NSString *url = [[emojiHTML substringWithRange:[match rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    if ([url hasPrefix:@"//"]) url = [@"https:" stringByAppendingString:url];
    if ([url hasPrefix:@"/"]) url = [@"https://github.githubassets.com" stringByAppendingString:url];
    return url;
}

- (void)updateStatusBadge:(BOOL)hasData {
    if (!hasData || self.statusInfo == nil) {
        self.statusBadge.hidden = YES;
        self.statusEmojiURL = nil;
        return;
    }
    BOOL busy = [self.statusInfo[@"indicatesLimitedAvailability"] boolValue];
    NSString *url = [self statusEmojiImageURL];
    if (url.length == 0) {
        self.statusEmojiURL = nil;
        self.statusEmojiView.image = busy ? [GHIconRenderer busyStatusIconWithSize:18] : [GHIconRenderer messageStatusIconWithColor:GHAccentColor() size:18];
        self.statusBadge.hidden = !busy && self.statusLabel.text.length == 0;
        return;
    }
    self.statusBadge.hidden = NO;
    if ([url isEqualToString:self.statusEmojiURL]) return;
    self.statusEmojiURL = url;
    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
    });
    UIImage *cached = [cache objectForKey:url];
    self.statusEmojiView.image = cached ?: [GHIconRenderer messageStatusIconWithColor:GHAccentColor() size:18];
    if (cached) return;
    NSURL *imageURL = [NSURL URLWithString:url];
    if (imageURL == nil) return;
    __weak typeof(self) weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:imageURL]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        if (image == nil) return;
        [cache setObject:image forKey:url];
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if ([strongSelf.statusEmojiURL isEqualToString:url]) strongSelf.statusEmojiView.image = image;
    }];
}

- (NSString *)statusText {
    NSDictionary *status = self.statusInfo;
    if (status == nil) return @"";
    NSString *message = [status[@"message"] isKindOfClass:[NSString class]] ? status[@"message"] : @"";
    message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (message.length == 0 && [status[@"indicatesLimitedAvailability"] boolValue]) message = GHL(@"Занят");
    return GHEmojiForDisplay(message) ?: @"";
}

- (void)setCountButton:(UIButton *)button count:(NSNumber *)count caption:(NSString *)caption {
    NSString *countText = [count stringValue];
    NSString *text = [NSString stringWithFormat:@"%@ %@", countText, caption];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange countRange = NSMakeRange(0, countText.length);
    NSRange captionRange = NSMakeRange(countText.length, text.length - countText.length);
    [attributed addAttribute:GHFontAttributeName() value:[UIFont boldSystemFontOfSize:15] range:countRange];
    [attributed addAttribute:GHForegroundColorAttributeName() value:GHPrimaryTextColor() range:countRange];
    [attributed addAttribute:GHFontAttributeName() value:[UIFont systemFontOfSize:15] range:captionRange];
    [attributed addAttribute:GHForegroundColorAttributeName() value:GHSecondaryTextColor() range:captionRange];
    [button setTitle:text forState:UIControlStateNormal];
    [button setTitleColor:GHSecondaryTextColor() forState:UIControlStateNormal];
    [button gh_setAttributedTitle:attributed forState:UIControlStateNormal];
    [button sizeToFit];
}

- (NSURL *)webURLFromString:(NSString *)string {
    if (string.length == 0) return nil;
    NSString *lower = string.lowercaseString;
    if (![lower hasPrefix:@"http://"] && ![lower hasPrefix:@"https://"]) {
        string = [@"http://" stringByAppendingString:string];
    }
    return [NSURL URLWithString:[string stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]] ?: [NSURL URLWithString:string];
}

- (void)rebuildInfoRows:(BOOL)hasData {
    for (UIView *row in self.infoRows) [row removeFromSuperview];
    [self.infoRows removeAllObjects];
    if (!hasData) return;

    NSString *company = [self stringForKey:@"company"];
    if (company) {
        NSURL *url = nil;
        if ([company hasPrefix:@"@"] && [company rangeOfString:@" "].location == NSNotFound && company.length > 1) {
            url = [NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@", [company substringFromIndex:1]]];
        }
        [self addInfoRowWithIcon:GHProfileInfoIconOrganization text:company url:url];
    }

    NSString *location = [self stringForKey:@"location"];
    if (location) [self addInfoRowWithIcon:GHProfileInfoIconLocation text:location url:nil];

    NSString *email = [self stringForKey:@"email"];
    if (email) [self addInfoRowWithIcon:GHProfileInfoIconMail text:email url:[NSURL URLWithString:[@"mailto:" stringByAppendingString:email]]];

    NSString *blog = [self stringForKey:@"blog"];
    if (blog) {
        NSString *display = blog;
        if ([display hasSuffix:@"/"]) display = [display substringToIndex:display.length - 1];
        [self addInfoRowWithIcon:GHProfileInfoIconLink text:display url:[self webURLFromString:blog]];
    }

    NSString *twitter = [self stringForKey:@"twitter_username"];
    if (twitter) {
        [self addInfoRowWithIcon:GHProfileInfoIconLink
                             text:[@"@" stringByAppendingString:twitter]
                              url:[NSURL URLWithString:[@"https://twitter.com/" stringByAppendingString:twitter]]];
    }

    NSString *shownBlog = [[[blog lowercaseString] stringByReplacingOccurrencesOfString:@"https://" withString:@""]
                           stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    for (NSDictionary *account in self.socialAccounts) {
        if (![account isKindOfClass:[NSDictionary class]]) continue;
        NSString *urlString = [account[@"url"] isKindOfClass:[NSString class]] ? account[@"url"] : nil;
        NSString *provider = [account[@"provider"] isKindOfClass:[NSString class]] ? [account[@"provider"] uppercaseString] : @"";
        if (urlString.length == 0) continue;
        if (twitter && [provider isEqualToString:@"TWITTER"]) continue;
        NSString *bare = [[[urlString lowercaseString] stringByReplacingOccurrencesOfString:@"https://" withString:@""]
                          stringByReplacingOccurrencesOfString:@"http://" withString:@""];
        if ([bare hasSuffix:@"/"]) bare = [bare substringToIndex:bare.length - 1];
        if (shownBlog.length > 0 && ([bare isEqualToString:shownBlog] || [[bare stringByAppendingString:@"/"] isEqualToString:shownBlog])) continue;
        NSString *display = [account[@"displayName"] isKindOfClass:[NSString class]] && [account[@"displayName"] length] > 0
            ? account[@"displayName"]
            : [urlString stringByReplacingOccurrencesOfString:@"https://" withString:@""];
        [self addInfoRowWithIcon:GHProfileInfoIconLink text:display url:[self webURLFromString:urlString]];
    }
}

- (void)addInfoRowWithIcon:(GHProfileInfoIcon)icon text:(NSString *)text url:(NSURL *)url {
    GHProfileInfoRow *row = [[GHProfileInfoRow alloc] initWithFrame:CGRectZero];
    row.iconKind = icon;
    row.url = url;
    row.textLabel.text = text;
    row.userInteractionEnabled = url != nil;
    [row addTarget:self action:@selector(infoRowTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self styleInfoRow:row];
    [self.infoRows addObject:row];
    [self addSubview:row];
}

- (void)styleInfoRow:(GHProfileInfoRow *)row {
    UIColor *iconColor = GHSecondaryTextColor();
    switch (row.iconKind) {
        case GHProfileInfoIconOrganization:
            row.iconView.image = [GHIconRenderer organizationIconWithColor:iconColor size:kGHProfileIconSize];
            break;
        case GHProfileInfoIconLocation:
            row.iconView.image = [GHIconRenderer locationIconWithColor:iconColor size:kGHProfileIconSize];
            break;
        case GHProfileInfoIconMail:
            row.iconView.image = [GHIconRenderer mailIconWithColor:iconColor size:kGHProfileIconSize];
            break;
        case GHProfileInfoIconLink:
            row.iconView.image = [GHIconRenderer linkIconWithColor:iconColor size:kGHProfileIconSize];
            break;
    }
    BOOL isLink = row.url != nil;
    row.textLabel.font = isLink ? [UIFont boldSystemFontOfSize:15] : [UIFont systemFontOfSize:15];
    row.textLabel.textColor = GHPrimaryTextColor();
}

- (void)loadAvatarIfNeeded {
    NSString *avatar = [self stringForKey:@"avatar_url"];
    if (avatar.length == 0 || [avatar isEqualToString:self.requestedAvatarURL]) return;
    self.requestedAvatarURL = avatar;

    NSString *sized = [avatar stringByAppendingString:([avatar rangeOfString:@"?"].location == NSNotFound ? @"?s=160" : @"&s=160")];
    NSURL *url = [NSURL URLWithString:sized];
    if (!url) return;

    __weak typeof(self) weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || error || data.length == 0) return;
        if (![strongSelf.requestedAvatarURL isEqualToString:avatar]) return;
        UIImage *image = [UIImage imageWithData:data];
        if (image) strongSelf.avatarView.image = image;
    }];
}

#pragma mark - Theme

- (void)applyTheme {
    self.avatarView.backgroundColor = GHSeparatorColor();
    self.nameLabel.textColor = GHPrimaryTextColor();
    self.loginLabel.textColor = GHSecondaryTextColor();
    self.bioLabel.textColor = GHPrimaryTextColor();
    self.statusView.backgroundColor = GHCellBackgroundColor();
    self.statusView.layer.borderColor = GHSeparatorColor().CGColor;
    self.statusLabel.textColor = GHPrimaryTextColor();
    self.statusBadge.backgroundColor = GHCellBackgroundColor();
    self.statusBadge.layer.borderColor = GHSeparatorColor().CGColor;
    self.followersIconView.image = [GHIconRenderer personOutlineIconWithColor:GHSecondaryTextColor() size:kGHProfileIconSize];
    self.followersSeparatorLabel.textColor = GHSecondaryTextColor();
    for (GHProfileInfoRow *row in self.infoRows) [self styleInfoRow:row];
    if (self.userInfo) [self reloadContent];
}

#pragma mark - Layout

- (CGFloat)heightForWidth:(CGFloat)width {
    return [self layoutForWidth:width apply:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutForWidth:self.bounds.size.width apply:YES];
}

- (CGFloat)layoutForWidth:(CGFloat)width apply:(BOOL)apply {
    CGFloat contentWidth = MAX(width - kGHProfilePadding * 2, 100);
    CGFloat y = kGHProfilePadding + 4;

    CGFloat textX = kGHProfilePadding + kGHProfileAvatarSize + 16;
    CGFloat textWidth = MAX(width - textX - kGHProfilePadding, 60);
    CGFloat nameHeight = 30;
    CGFloat loginHeight = self.loginLabel.text.length > 0 ? 22 : 0;
    CGFloat namesHeight = nameHeight + (loginHeight > 0 ? 2 + loginHeight : 0);
    CGFloat namesTop = y + floor((kGHProfileAvatarSize - namesHeight) / 2.0);

    if (apply) {
        self.avatarView.frame = CGRectMake(kGHProfilePadding, y, kGHProfileAvatarSize, kGHProfileAvatarSize);
        self.nameLabel.frame = CGRectMake(textX, namesTop, textWidth, nameHeight);
        self.loginLabel.frame = CGRectMake(textX, namesTop + nameHeight + 2, textWidth, loginHeight);
        self.statusBadge.frame = CGRectMake(kGHProfilePadding + kGHProfileAvatarSize - 24, y + kGHProfileAvatarSize - 24, 28, 28);
        self.statusEmojiView.frame = CGRectMake(5, 5, 18, 18);
    }
    y += kGHProfileAvatarSize + 16;

    if (!self.statusView.hidden) {
        CGSize statusSize = [self.statusLabel.text sizeWithFont:self.statusLabel.font];
        CGFloat statusWidth = MIN(contentWidth, ceil(statusSize.width) + 26);
        if (apply) {
            self.statusView.frame = CGRectMake(kGHProfilePadding, y, statusWidth, 30);
            self.statusLabel.frame = CGRectMake(13, 0, statusWidth - 26, 30);
        }
        y += 30 + 14;
    }

    if (self.bioLabel.text.length > 0) {
        CGSize bioSize = [self.bioLabel.text sizeWithFont:self.bioLabel.font
                                         constrainedToSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                             lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat bioHeight = ceil(bioSize.height);
        if (apply) self.bioLabel.frame = CGRectMake(kGHProfilePadding, y, contentWidth, bioHeight);
        y += bioHeight + 14;
    } else if (apply) {
        self.bioLabel.frame = CGRectMake(kGHProfilePadding, y, contentWidth, 0);
    }

    for (GHProfileInfoRow *row in self.infoRows) {
        if (apply) {
            CGSize textSize = [row.textLabel.text sizeWithFont:row.textLabel.font];
            CGFloat rowWidth = MIN(contentWidth, kGHProfileIconSize + 10 + ceil(textSize.width));
            row.frame = CGRectMake(kGHProfilePadding, y, rowWidth, kGHProfileRowHeight);
        }
        y += kGHProfileRowHeight + kGHProfileRowSpacing;
    }

    if (!self.followersButton.hidden) {
        if (apply) {
            self.followersIconView.frame = CGRectMake(kGHProfilePadding, y + floor((kGHProfileRowHeight - kGHProfileIconSize) / 2.0),
                                                      kGHProfileIconSize, kGHProfileIconSize);
            CGFloat x = kGHProfilePadding + kGHProfileIconSize + 10;
            CGFloat followersWidth = self.followersButton.bounds.size.width;
            self.followersButton.frame = CGRectMake(x, y, followersWidth, kGHProfileRowHeight);
            x += followersWidth + 6;
            [self.followersSeparatorLabel sizeToFit];
            self.followersSeparatorLabel.frame = CGRectMake(x, y, self.followersSeparatorLabel.bounds.size.width, kGHProfileRowHeight);
            x += self.followersSeparatorLabel.bounds.size.width + 6;
            CGFloat followingWidth = MIN(self.followingButton.bounds.size.width, MAX(width - kGHProfilePadding - x, 40));
            self.followingButton.frame = CGRectMake(x, y, followingWidth, kGHProfileRowHeight);
        }
        y += kGHProfileRowHeight;
    }

    if (self.actionButton && !self.actionButton.hidden) {
        y += 16;
        if (apply) self.actionButton.frame = CGRectMake(kGHProfilePadding, y, contentWidth, 36);
        y += 36;
    }

    y += 20;
    return y;
}

#pragma mark - Actions

- (void)infoRowTapped:(GHProfileInfoRow *)row {
    if (row.url && self.onLinkTapped) self.onLinkTapped(row.url);
}

- (void)followersTapped {
    if (self.onFollowersTapped) self.onFollowersTapped();
}

- (void)followingTapped {
    if (self.onFollowingTapped) self.onFollowingTapped();
}

@end
