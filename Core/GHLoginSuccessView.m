#import "GHLoginSuccessView.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"
#import "GHAvatarLoader.h"

@interface GHLoginSuccessView ()
@property (nonatomic, strong) UIImageView *badgeView;
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *doneButton;
@end

@implementation GHLoginSuccessView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIColor *green = [UIColor colorWithRed:0.16 green:0.65 blue:0.27 alpha:1.0];
        _badgeView = [[UIImageView alloc] initWithImage:[GHIconRenderer successBadgeWithColor:green size:88]];
        [self addSubview:_badgeView];

        _avatarView = [[UIImageView alloc] init];
        _avatarView.layer.cornerRadius = 22.0;
        _avatarView.layer.masksToBounds = YES;
        _avatarView.hidden = YES;
        [self addSubview:_avatarView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:22];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.numberOfLines = 0;
        _titleLabel.text = GHL(@"Вход выполнен");
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.font = [UIFont systemFontOfSize:15];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.numberOfLines = 0;
        [self addSubview:_subtitleLabel];

        _doneButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [_doneButton setTitle:GHL(@"Готово") forState:UIControlStateNormal];
        _doneButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        [_doneButton addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_doneButton];

        [self applyTheme];
    }
    return self;
}

- (void)applyTheme {
    self.backgroundColor = GHBackgroundColor();
    self.titleLabel.textColor = GHPrimaryTextColor();
    self.subtitleLabel.textColor = GHSecondaryTextColor();
}

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.text.length == 0) return 0;
    return ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = MIN(self.bounds.size.width - 30, 460);
    CGFloat left = floor((self.bounds.size.width - width) / 2.0);

    CGFloat titleHeight = [self heightForLabel:self.titleLabel width:width];
    CGFloat subtitleHeight = [self heightForLabel:self.subtitleLabel width:width];
    BOOL hasAvatar = !self.avatarView.hidden;

    CGFloat total = 88 + 22 + titleHeight + 8 + (hasAvatar ? 44 + 10 : 0) + subtitleHeight + 30 + 44;
    CGFloat y = MAX(20, floor((self.bounds.size.height - total) / 2.0) - 20);

    self.badgeView.bounds = CGRectMake(0, 0, 88, 88);
    self.badgeView.center = CGPointMake(floor(self.bounds.size.width / 2.0), y + 44);
    y += 88 + 22;

    self.titleLabel.frame = CGRectMake(left, y, width, titleHeight);
    y += titleHeight + 8;

    if (hasAvatar) {
        self.avatarView.frame = CGRectMake(floor((self.bounds.size.width - 44) / 2.0), y, 44, 44);
        y += 44 + 10;
    }

    self.subtitleLabel.frame = CGRectMake(left, y, width, subtitleHeight);
    y += subtitleHeight + 30;

    self.doneButton.frame = CGRectMake(left, y, width, 44);
}

- (void)presentForLogin:(NSString *)login avatarURL:(NSString *)avatarURL {
    self.subtitleLabel.text = [NSString stringWithFormat:GHL(@"Вы вошли как @%@.\nЭто устройство подключено к вашему аккаунту GitHub."), login];

    if (avatarURL.length > 0) {
        self.avatarView.hidden = NO;
        [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:self.avatarView];
    }

    [self applyTheme];
    self.hidden = NO;
    self.alpha = 0.0;
    [self.superview bringSubviewToFront:self];
    [self setNeedsLayout];
    [self layoutIfNeeded];

    self.badgeView.transform = CGAffineTransformMakeScale(0.4, 0.4);
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1.0;
    }];
    [UIView animateWithDuration:0.45
                          delay:0.1
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.badgeView.transform = CGAffineTransformMakeScale(1.08, 1.08);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.badgeView.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)doneTapped {
    if (self.onDone) self.onDone();
}

@end
