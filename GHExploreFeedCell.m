#import "GHExploreFeedCell.h"
#import "GHAvatarLoader.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMargin = 16;
static const CGFloat kAvatarSize = 20;
static const CGFloat kUsernameRowHeight = 16;
static const CGFloat kCaptionRowHeight = 14;
static const CGFloat kHeaderRowSpacing = 1;
static const CGFloat kSectionSpacing = 6;
static const CGFloat kTitleRowHeight = 22;

static CGFloat GHExploreHeaderBlockHeight(void) {
    return kUsernameRowHeight + kHeaderRowSpacing + kCaptionRowHeight;
}

@interface GHExploreFeedCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *usernameLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation GHExploreFeedCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleBlue;

        self.avatarView = [[UIImageView alloc] init];
        self.avatarView.layer.cornerRadius = kAvatarSize / 2.0;
        self.avatarView.layer.masksToBounds = YES;
        self.avatarView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:self.avatarView];

        self.usernameLabel = [[UILabel alloc] init];
        self.usernameLabel.font = [UIFont boldSystemFontOfSize:13];
        self.usernameLabel.numberOfLines = 1;
        self.usernameLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.usernameLabel];

        self.captionLabel = [[UILabel alloc] init];
        self.captionLabel.font = [UIFont systemFontOfSize:12];
        self.captionLabel.numberOfLines = 1;
        self.captionLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.captionLabel];

        self.dateLabel = [[UILabel alloc] init];
        self.dateLabel.font = [UIFont systemFontOfSize:12];
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        self.dateLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.dateLabel];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.backgroundColor = [UIColor clearColor];
        [self.contentView addSubview:self.titleLabel];
    }
    return self;
}

+ (CGFloat)heightForEntryWithRepo:(NSDictionary *)repo release:(NSDictionary *)release width:(CGFloat)width {
    CGFloat height = kMargin;
    height += GHExploreHeaderBlockHeight() + kSectionSpacing;
    height += kTitleRowHeight;
    height += kMargin;
    return height;
}

- (void)configureWithRepo:(NSDictionary *)repo release:(NSDictionary *)release relativeDate:(NSString *)relativeDate {
    NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
    NSString *ownerLogin = [owner[@"login"] isKindOfClass:[NSString class]] ? owner[@"login"] : @"";
    NSString *avatarURL = owner[@"avatar_url"];
    NSString *repoName = [repo[@"name"] isKindOfClass:[NSString class]] ? repo[@"name"] : repo[@"full_name"];

    id nameValue = release[@"name"];
    id tagValue = release[@"tag_name"];
    NSString *releaseName = [nameValue isKindOfClass:[NSString class]] ? nameValue : nil;
    NSString *tagName = [tagValue isKindOfClass:[NSString class]] ? tagValue : nil;
    NSString *releaseTitle = releaseName.length > 0 ? releaseName : (tagName ?: GHL(@"новый релиз"));

    self.usernameLabel.text = ownerLogin;
    self.usernameLabel.textColor = GHPrimaryTextColor();

    self.captionLabel.text = GHL(@"опубликовал релиз");
    self.captionLabel.textColor = GHSecondaryTextColor();

    self.dateLabel.text = relativeDate;
    self.dateLabel.textColor = GHSecondaryTextColor();

    self.titleLabel.text = [NSString stringWithFormat:@"%@ · %@", repoName.length > 0 ? repoName : @"?", releaseTitle];
    self.titleLabel.textColor = GHPrimaryTextColor();

    [[GHAvatarLoader sharedLoader] loadAvatarWithURLString:avatarURL intoImageView:self.avatarView];

    GHApplyDisclosureIndicator(self);

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat contentWidth = width - kMargin * 2;
    CGFloat headerBlockHeight = GHExploreHeaderBlockHeight();

    CGFloat avatarY = kMargin + (headerBlockHeight - kAvatarSize) / 2.0;
    self.avatarView.frame = CGRectMake(kMargin, avatarY, kAvatarSize, kAvatarSize);

    CGFloat headerX = kMargin + kAvatarSize + 8;
    CGFloat dateWidth = 44;
    self.usernameLabel.frame = CGRectMake(headerX, kMargin, width - headerX - kMargin - dateWidth - 6, kUsernameRowHeight);
    self.dateLabel.frame = CGRectMake(width - kMargin - dateWidth, kMargin, dateWidth, kUsernameRowHeight);

    CGFloat captionY = kMargin + kUsernameRowHeight + kHeaderRowSpacing;
    self.captionLabel.frame = CGRectMake(headerX, captionY, width - headerX - kMargin, kCaptionRowHeight);

    CGFloat titleY = kMargin + headerBlockHeight + kSectionSpacing;
    self.titleLabel.frame = CGRectMake(kMargin, titleY, contentWidth, kTitleRowHeight);
}

@end
