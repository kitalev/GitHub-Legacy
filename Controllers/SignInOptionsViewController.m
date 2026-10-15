#import "SignInOptionsViewController.h"
#import "DeviceLoginViewController.h"
#import "TokenLoginViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"

static NSString * const kCellID = @"SignInOptionCell";

static UIImage *GHGoogleIcon(UIColor *color, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    UIFont *font = [UIFont boldSystemFontOfSize:floor(size * 0.72)];
    NSString *letter = @"G";
    CGSize textSize = [letter sizeWithFont:font];
    [color setFill];
    [letter drawAtPoint:CGPointMake(floor((size - textSize.width) / 2.0), floor((size - textSize.height) / 2.0)) withFont:font];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@interface GHSignInOptionCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
+ (CGFloat)heightForDetail:(NSString *)detail width:(CGFloat)width;
@end

@implementation GHSignInOptionCell

+ (UIFont *)titleFont {
    return [UIFont boldSystemFontOfSize:17];
}

+ (UIFont *)detailFont {
    return [UIFont systemFontOfSize:13];
}

+ (CGFloat)textWidthForCellWidth:(CGFloat)width {
    return MAX(100, width - 14 - 36 - 12 - 34);
}

+ (CGFloat)heightForDetail:(NSString *)detail width:(CGFloat)width {
    CGSize detailSize = [detail sizeWithFont:[self detailFont]
                            constrainedToSize:CGSizeMake([self textWidthForCellWidth:width], CGFLOAT_MAX)
                                lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(64, 12 + 21 + 3 + ceil(detailSize.height) + 12);
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _iconView = [[UIImageView alloc] init];
        _iconView.contentMode = UIViewContentModeCenter;
        [self.contentView addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [[self class] titleFont];
        _titleLabel.adjustsFontSizeToFitWidth = YES;
        if ([_titleLabel respondsToSelector:@selector(setMinimumScaleFactor:)]) {
            _titleLabel.minimumScaleFactor = 0.75;
        } else {
            _titleLabel.minimumFontSize = 17.0 * 0.75;
        }
        [self.contentView addSubview:_titleLabel];

        _detailLabel = [[UILabel alloc] init];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = [[self class] detailFont];
        _detailLabel.numberOfLines = 0;
        _detailLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:_detailLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat height = self.contentView.bounds.size.height;
    CGFloat textWidth = [[self class] textWidthForCellWidth:self.bounds.size.width];
    CGFloat textLeft = 14 + 36 + 12;
    textWidth = MIN(textWidth, self.contentView.bounds.size.width - textLeft - 6);

    self.iconView.frame = CGRectMake(14, floor((height - 36) / 2.0), 36, 36);

    CGSize detailSize = [self.detailLabel.text sizeWithFont:self.detailLabel.font
                                          constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                                              lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat blockHeight = 21 + 3 + ceil(detailSize.height);
    CGFloat y = floor((height - blockHeight) / 2.0);

    self.titleLabel.frame = CGRectMake(textLeft, y, textWidth, 21);
    self.detailLabel.frame = CGRectMake(textLeft, y + 21 + 3, textWidth, ceil(detailSize.height));
}

@end

@interface SignInOptionsViewController ()
@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;
@end

@implementation SignInOptionsViewController

- (id)init {
    return [self initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = GHL(@"Вход");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10)];
    header.backgroundColor = [UIColor clearColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.headerIconView = [[UIImageView alloc] init];
    self.headerIconView.contentMode = UIViewContentModeCenter;
    self.headerIconView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.headerIconView];

    self.headerTitleLabel = [[UILabel alloc] init];
    self.headerTitleLabel.backgroundColor = [UIColor clearColor];
    self.headerTitleLabel.font = [UIFont boldSystemFontOfSize:22];
    self.headerTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.headerTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = [[UILabel alloc] init];
    self.headerSubtitleLabel.backgroundColor = [UIColor clearColor];
    self.headerSubtitleLabel.font = [UIFont systemFontOfSize:15];
    self.headerSubtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.headerSubtitleLabel.numberOfLines = 0;
    self.headerSubtitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.headerSubtitleLabel];

    self.tableView.tableHeaderView = header;
    [self applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeader];
}

- (void)layoutHeader {
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;

    CGFloat width = self.tableView.bounds.size.width;
    CGFloat textWidth = MIN(width - 40, 440);
    CGFloat textLeft = floor((width - textWidth) / 2.0);

    self.headerTitleLabel.text = GHL(@"Вход в GitHub");
    self.headerSubtitleLabel.text = GHL(@"Выберите, как войти в аккаунт");

    CGFloat y = 24;
    self.headerIconView.frame = CGRectMake(0, y, width, 64);
    y += 64 + 12;

    self.headerTitleLabel.frame = CGRectMake(textLeft, y, textWidth, 28);
    y += 28 + 4;

    CGFloat subtitleHeight = ceil([self.headerSubtitleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height);
    self.headerSubtitleLabel.frame = CGRectMake(textLeft, y, textWidth, subtitleHeight);
    y += subtitleHeight + 8;

    if (fabs(header.frame.size.height - y) > 0.5 || fabs(header.frame.size.width - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, y);
        self.tableView.tableHeaderView = header;
    }
}

- (void)applyTheme {
    self.tableView.backgroundView = nil;
    self.tableView.backgroundColor = GHBackgroundColor();
    self.tableView.separatorColor = GHSeparatorColor();

    self.headerIconView.image = [GHIconRenderer personIconWithColor:GHAccentColor() size:56];
    self.headerTitleLabel.textColor = GHPrimaryTextColor();
    self.headerSubtitleLabel.textColor = GHSecondaryTextColor();

    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? GHL(@"Рекомендуется") : GHL(@"Другие способы");
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat groupedInset = tableView.bounds.size.width > 480 ? 90 : 20;
    return [GHSignInOptionCell heightForDetail:[self detailForOption:[self optionAtIndexPath:indexPath]]
                                         width:tableView.bounds.size.width - groupedInset];
}

- (NSInteger)optionAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? 0 : 1 + indexPath.row;
}

- (NSString *)titleForOption:(NSInteger)option {
    switch (option) {
        case 0: return GHL(@"Войти в приложении");
        case 1: return GHL(@"Войти через Google");
        case 2: return GHL(@"Войти через github.com");
        default: return GHL(@"Войти по токену");
    }
}

- (NSString *)detailForOption:(NSInteger)option {
    switch (option) {
        case 0: return GHL(@"Логин и пароль вводятся прямо в приложении. Вход подтверждается через GitHub Mobile, кодом из приложения-аутентификатора или кодом восстановления.");
        case 1: return GHL(@"Вход через аккаунт Google, привязанный к GitHub. Всё происходит прямо в приложении.");
        case 2: return GHL(@"Введите короткий код на github.com/login/device с компьютера или другого телефона. Пароль приложение не видит.");
        default: return GHL(@"Вставьте Personal Access Token, созданный вручную на github.com.");
    }
}

- (UIImage *)iconForOption:(NSInteger)option {
    switch (option) {
        case 0: return [GHIconRenderer personIconWithColor:GHAccentColor() size:36];
        case 1: return GHGoogleIcon(GHSecondaryTextColor(), 36);
        case 2: return [GHIconRenderer devicesIconWithColor:GHSecondaryTextColor() size:36];
        default: return [GHIconRenderer keyIconWithColor:GHSecondaryTextColor() size:36];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GHSignInOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID];
    if (!cell) {
        cell = [[GHSignInOptionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellID];
    }

    NSInteger option = [self optionAtIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.titleLabel.text = [self titleForOption:option];
    cell.titleLabel.textColor = GHPrimaryTextColor();
    cell.detailLabel.text = [self detailForOption:option];
    cell.detailLabel.textColor = GHSecondaryTextColor();
    cell.iconView.image = [self iconForOption:option];
    GHApplyDisclosureIndicator(cell);
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    __weak typeof(self) weakSelf = self;
    NSInteger option = [self optionAtIndexPath:indexPath];
    if (option < 3) {
        DeviceLoginViewController *deviceVC = [[DeviceLoginViewController alloc] init];
        deviceVC.opensInApp = option < 2;
        deviceVC.usesGoogle = option == 1;
        deviceVC.onLoggedIn = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.onLoggedIn) strongSelf.onLoggedIn();
        };
        [self.navigationController pushViewController:deviceVC animated:YES];
    } else {
        TokenLoginViewController *tokenVC = [[TokenLoginViewController alloc] init];
        tokenVC.onLoggedIn = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf.onLoggedIn) strongSelf.onLoggedIn();
        };
        [self.navigationController pushViewController:tokenVC animated:YES];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
