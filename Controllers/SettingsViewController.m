#import "SettingsViewController.h"
#import "GHCompat.h"
#import "GHThemeManager.h"
#import "GHAuthManager.h"
#import "GHAPIClient.h"
#import "GHLocalization.h"
#import "LanguageViewController.h"
#import "TokenLoginViewController.h"
#import "SignInOptionsViewController.h"
#import "RepoOverviewViewController.h"
#import "ReleaseDetailViewController.h"

static NSString * const kGHSafariRedirectPrefsPath = @"/var/mobile/Library/Preferences/com.githublegacy.safariredirect.plist";
static NSString * const kGHSafariRedirectEnabledKey = @"Enabled";

typedef NS_ENUM(NSInteger, GHSettingsSection) {
    kSettingsSectionAccount = 0,
    kSettingsSectionAppearance,
    kSettingsSectionLinks,
    kSettingsSectionAbout,
    kSettingsSectionCount
};

static NSString * const kAboutCellID = @"AboutCell";
static NSString * const kDescriptionCellID = @"DescriptionCell";
static NSString * const kSwitchCellID = @"SwitchCell";
static NSString * const kAccountCellID = @"AccountCell";
static NSString * const kValueCellID = @"ValueCell";
static NSString * const kRepoLinkCellID = @"RepoLinkCell";
static NSString * const kRepoURLCellID = @"RepoURLCell";
static NSString * const kSwitchDescriptionCellID = @"SwitchDescriptionCell";
static NSString * const kUpdateCellID = @"UpdateCell";

static const CGFloat kGHSwitchCellPaddingX = 12.0;
static const CGFloat kGHSwitchCellPaddingY = 10.0;
static const CGFloat kGHSwitchCellTitleHeight = 21.0;
static const CGFloat kGHSwitchCellGap = 4.0;

@interface GHSwitchDescriptionCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UISwitch *toggle;
+ (UIFont *)titleFont;
+ (UIFont *)descriptionFont;
+ (CGFloat)heightForDescription:(NSString *)description cellWidth:(CGFloat)cellWidth;
@end

static BOOL GHUsesPreFlatDesignDefaults(void) {
    static BOOL legacy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *version = [[UIDevice currentDevice] systemVersion];
        legacy = [version compare:@"7.0" options:NSNumericSearch] == NSOrderedAscending;
    });
    return legacy;
}

@implementation GHSwitchDescriptionCell

+ (UIFont *)titleFont {
    return GHUsesPreFlatDesignDefaults() ? [UIFont boldSystemFontOfSize:17] : [UIFont systemFontOfSize:17];
}

+ (UIFont *)descriptionFont {
    return [UIFont systemFontOfSize:13];
}

+ (CGFloat)heightForDescription:(NSString *)description cellWidth:(CGFloat)cellWidth {
    CGFloat textWidth = cellWidth - (kGHSwitchCellPaddingX * 2);
    if (textWidth < 1) textWidth = 1;

    CGSize size = [description sizeWithFont:[self descriptionFont]
                           constrainedToSize:CGSizeMake(textWidth, CGFLOAT_MAX)
                               lineBreakMode:NSLineBreakByWordWrapping];

    return kGHSwitchCellPaddingY + kGHSwitchCellTitleHeight + kGHSwitchCellGap
         + size.height + kGHSwitchCellPaddingY;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [[self class] titleFont];
        [self.contentView addSubview:_titleLabel];

        _descriptionLabel = [[UILabel alloc] init];
        _descriptionLabel.backgroundColor = [UIColor clearColor];
        _descriptionLabel.font = [[self class] descriptionFont];
        _descriptionLabel.numberOfLines = 0;
        _descriptionLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:_descriptionLabel];

        _toggle = [[UISwitch alloc] init];
        [self.contentView addSubview:_toggle];

        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.accessoryType = UITableViewCellAccessoryNone;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.contentView.bounds;
    CGSize switchSize = self.toggle.bounds.size;

    self.toggle.frame = CGRectMake(bounds.size.width - kGHSwitchCellPaddingX - switchSize.width,
                                   kGHSwitchCellPaddingY + (kGHSwitchCellTitleHeight - switchSize.height) / 2.0,
                                   switchSize.width,
                                   switchSize.height);

    CGFloat titleWidth = bounds.size.width - (kGHSwitchCellPaddingX * 2) - switchSize.width - 8;
    if (titleWidth < 1) titleWidth = 1;
    self.titleLabel.frame = CGRectMake(kGHSwitchCellPaddingX,
                                       kGHSwitchCellPaddingY,
                                       titleWidth,
                                       kGHSwitchCellTitleHeight);

    CGFloat descriptionWidth = bounds.size.width - (kGHSwitchCellPaddingX * 2);
    CGSize descriptionSize = [self.descriptionLabel.text sizeWithFont:self.descriptionLabel.font
                                                    constrainedToSize:CGSizeMake(descriptionWidth, CGFLOAT_MAX)
                                                        lineBreakMode:NSLineBreakByWordWrapping];
    self.descriptionLabel.frame = CGRectMake(kGHSwitchCellPaddingX,
                                             kGHSwitchCellPaddingY + kGHSwitchCellTitleHeight + kGHSwitchCellGap,
                                             descriptionWidth,
                                             descriptionSize.height);
}

@end

static NSString * const kProjectRepoOwner = @"kitalev";static NSString * const kProjectRepoName = @"GitHub-Legacy";

static const NSInteger kLogoutAlertTag = 1;
static const NSInteger kUpdateAlertTag = 2;

@interface SettingsViewController ()

@property (nonatomic, copy) NSString *loggedInUsername;
@property (nonatomic, assign) BOOL accountRowLoading;

@property (nonatomic, assign) BOOL repoRowLoading;

@property (nonatomic, assign) BOOL updateRowLoading;
@property (nonatomic, strong) NSDictionary *pendingUpdateRelease;
@end

@implementation SettingsViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.title = GHL(@"Настройки");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.tableView gh_registerCellClass:[UITableViewCell class] forCellReuseIdentifier:kDescriptionCellID];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(languageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];
    [self applyTheme];
    [self refreshAccountRow];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)languageDidChange {
    self.title = GHL(@"Настройки");
    [self.tableView reloadData];
}

- (void)applyTheme {
    self.tableView.backgroundColor = GHBackgroundColor();

    self.tableView.backgroundView = nil;
    self.tableView.separatorColor = GHSeparatorColor();
    [self.tableView reloadData];
}

#pragma mark - Аккаунт

- (void)refreshAccountRow {
    if (![GHAuthManager sharedManager].isAuthenticated) {
        self.loggedInUsername = nil;
        self.accountRowLoading = NO;
        [self.tableView reloadData];
        return;
    }

    self.accountRowLoading = YES;
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.accountRowLoading = NO;
        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            NSString *login = jsonObject[@"login"];
            strongSelf.loggedInUsername = [login isKindOfClass:[NSString class]] ? login : nil;
        }
        [strongSelf.tableView reloadData];
    }];
}

- (void)accountRowTapped {
    if ([GHAuthManager sharedManager].isAuthenticated) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Выйти из аккаунта?")
                                                         message:nil
                                                        delegate:self
                                               cancelButtonTitle:GHL(@"Отмена")
                                               otherButtonTitles:GHL(@"Выйти"), nil];
        alert.tag = kLogoutAlertTag;
        [alert show];
        return;
    }

    [self presentTokenLogin];
}

- (void)presentTokenLogin {

    SignInOptionsViewController *signInVC = [[SignInOptionsViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    signInVC.onLoggedIn = ^{
        [weakSelf refreshAccountRow];
    };
    [self.navigationController pushViewController:signInVC animated:YES];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (alertView.tag == kLogoutAlertTag) {
        if (alertView.cancelButtonIndex != buttonIndex) {
            [[GHAuthManager sharedManager] logout];
            [self refreshAccountRow];
        }
        return;
    }

    if (alertView.tag == kUpdateAlertTag) {
        NSDictionary *release = self.pendingUpdateRelease;
        self.pendingUpdateRelease = nil;
        if (alertView.cancelButtonIndex == buttonIndex || release == nil) return;

        id tagValue = [release objectForKey:@"tag_name"];
        ReleaseDetailViewController *detailVC = [[ReleaseDetailViewController alloc] init];
        detailVC.releaseInfo = release;
        detailVC.ownerLogin = kProjectRepoOwner;
        detailVC.repoName = kProjectRepoName;
        detailVC.title = [tagValue isKindOfClass:[NSString class]] ? tagValue : GHL(@"Релиз");
        [self.navigationController pushViewController:detailVC animated:YES];
        return;
    }
}

#pragma mark - Об экране

- (NSString *)appDisplayName {
    return @"GitHub Legacy";
}

- (NSString *)versionString {
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return version.length > 0 ? version : @"1.0";
}

- (NSString *)descriptionText {
    return GHL(@"Лёгкий нативный клиент GitHub для iOS 4 и новее: репозитории, README на нескольких языках, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на старых версиях уже не запустить.\n\nmade by kitalev");
}

- (CGFloat)heightForText:(NSString *)text width:(CGFloat)width {
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:15]
                    constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                        lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(size.height, 20);
}

- (void)darkModeSwitchToggled:(UISwitch *)sender {

    [GHThemeManager sharedManager].darkModeEnabled = sender.isOn;
}

- (BOOL)isSafariTweakInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/GitHubLegacySafariRedirect.dylib"];
}

- (BOOL)isSafariRedirectEnabled {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kGHSafariRedirectPrefsPath];
    id value = prefs[kGHSafariRedirectEnabledKey];
    if (value == nil) return YES;
    return [value boolValue];
}

- (void)redirectSwitchToggled:(UISwitch *)sender {
    NSDictionary *prefs = @{kGHSafariRedirectEnabledKey: @(sender.isOn)};
    BOOL wrote = [prefs writeToFile:kGHSafariRedirectPrefsPath atomically:YES];
    if (!wrote) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка")
                                                         message:GHL(@"Не удалось сохранить настройку — нет доступа на запись к файлу настроек.")
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil];
        [alert show];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSettingsSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kSettingsSectionAccount) return GHL(@"Аккаунт");
    if (section == kSettingsSectionAppearance) return GHL(@"Внешний вид");
    if (section == kSettingsSectionLinks) return [self isSafariTweakInstalled] ? GHL(@"Ссылки GitHub") : nil;
    if (section == kSettingsSectionAbout) return GHL(@"О программе");
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderView([self tableView:tableView titleForHeaderInSection:section]);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return GHThemedSectionHeaderHeight([self tableView:tableView titleForHeaderInSection:section]);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kSettingsSectionAccount) return 1;
    if (section == kSettingsSectionAppearance) return 2;
    if (section == kSettingsSectionLinks) return [self isSafariTweakInstalled] ? 1 : 0;
    if (section == kSettingsSectionAbout) return 5;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSettingsSectionAccount) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAccountCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kAccountCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;

        BOOL authenticated = [GHAuthManager sharedManager].isAuthenticated;
        if (self.accountRowLoading) {
            cell.textLabel.text = authenticated ? GHL(@"Выйти") : GHL(@"Войти");
            cell.textLabel.textColor = GHSecondaryTextColor();
            cell.detailTextLabel.text = @"…";
        } else if (authenticated) {
            cell.textLabel.text = GHL(@"Выйти из аккаунта");
            cell.textLabel.textColor = [UIColor redColor];
            cell.detailTextLabel.text = self.loggedInUsername.length > 0 ? [NSString stringWithFormat:@"@%@", self.loggedInUsername] : @"";
        } else {
            cell.textLabel.text = GHL(@"Войти");
            cell.textLabel.textColor = GHAccentColor();
            cell.detailTextLabel.text = @"";
        }
        cell.detailTextLabel.textColor = GHSecondaryTextColor();
        return cell;
    }

    if (indexPath.section == kSettingsSectionAppearance) {
        if (indexPath.row == 0) {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCellID];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kSwitchCellID];
            }
            cell.backgroundColor = GHCellBackgroundColor();
            cell.textLabel.text = GHL(@"Тёмная тема");
            cell.textLabel.textColor = GHPrimaryTextColor();
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;

            UISwitch *darkSwitch = [[UISwitch alloc] init];
            darkSwitch.on = [GHThemeManager sharedManager].darkModeEnabled;
            [darkSwitch addTarget:self action:@selector(darkModeSwitchToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = darkSwitch;
            return cell;
        }

        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kValueCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kValueCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = GHL(@"Язык");
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.detailTextLabel.text = [[GHLocalization sharedManager].languageCode isEqualToString:@"en"] ? GHL(@"Английский") : GHL(@"Русский");
        cell.detailTextLabel.textColor = GHSecondaryTextColor();
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        GHApplyDisclosureIndicator(cell);
        return cell;
    }

    if (indexPath.section == kSettingsSectionLinks) {
        GHSwitchDescriptionCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchDescriptionCellID];
        if (!cell) {
            cell = [[GHSwitchDescriptionCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                   reuseIdentifier:kSwitchDescriptionCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.titleLabel.text = GHL(@"Переадресация");
        cell.titleLabel.textColor = GHPrimaryTextColor();
        cell.descriptionLabel.text = GHL(@"Ссылки github.com из Safari и других приложений будут открываться здесь");
        cell.descriptionLabel.textColor = GHSecondaryTextColor();

        [cell.toggle removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
        cell.toggle.on = [self isSafariRedirectEnabled];
        [cell.toggle addTarget:self action:@selector(redirectSwitchToggled:) forControlEvents:UIControlEventValueChanged];

        [cell setNeedsLayout];
        return cell;
    }

    if (indexPath.row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kAboutCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = [self appDisplayName];
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.detailTextLabel.text = [self versionString];
        cell.detailTextLabel.textColor = GHSecondaryTextColor();
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    if (indexPath.row == 2) {

        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRepoLinkCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRepoLinkCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = GHL(@"Репозиторий на GitHub");
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.detailTextLabel.text = nil;
        if (self.repoRowLoading) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
            [spinner startAnimating];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = spinner;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            GHApplyDisclosureIndicator(cell);
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
        return cell;
    }

    if (indexPath.row == 3) {

        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRepoURLCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRepoURLCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = [NSString stringWithFormat:@"github.com/%@/%@", kProjectRepoOwner, kProjectRepoName];
        cell.textLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.textColor = GHSecondaryTextColor();
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.row == 4) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUpdateCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kUpdateCellID];
        }
        cell.backgroundColor = GHCellBackgroundColor();
        cell.textLabel.text = GHL(@"Проверить обновления");
        cell.textLabel.textColor = GHPrimaryTextColor();
        cell.detailTextLabel.text = nil;
        if (self.updateRowLoading) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
            [spinner startAnimating];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = spinner;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.accessoryView = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
        return cell;
    }

    UITableViewCell *cell = [tableView gh_dequeueCellWithIdentifier:kDescriptionCellID forIndexPath:indexPath];
    cell.backgroundColor = GHCellBackgroundColor();
    cell.textLabel.text = [self descriptionText];
    cell.textLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.textLabel.textColor = GHSecondaryTextColor();
    cell.detailTextLabel.text = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == kSettingsSectionAccount && !self.accountRowLoading) {
        [self accountRowTapped];
        return;
    }
    if (indexPath.section == kSettingsSectionAppearance && indexPath.row == 1) {
        LanguageViewController *languageVC = [[LanguageViewController alloc] init];
        [self.navigationController pushViewController:languageVC animated:YES];
        return;
    }
    if (indexPath.section == kSettingsSectionAbout && indexPath.row == 2) {
        [self openProjectRepository];
        return;
    }
    if (indexPath.section == kSettingsSectionAbout && indexPath.row == 4) {
        [self checkForUpdates];
    }
}

- (NSString *)normalizedVersionString:(NSString *)version {
    NSString *trimmed = [version stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmed hasPrefix:@"v"] || [trimmed hasPrefix:@"V"]) {
        trimmed = [trimmed substringFromIndex:1];
    }
    return trimmed;
}

- (void)showUpdateAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:GHL(@"OK")
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)checkForUpdates {
    if (self.updateRowLoading) return;
    self.updateRowLoading = YES;

    NSIndexPath *rowPath = [NSIndexPath indexPathForRow:4 inSection:kSettingsSectionAbout];
    [self.tableView reloadRowsAtIndexPaths:@[rowPath] withRowAnimation:UITableViewRowAnimationNone];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] latestReleaseForOwner:kProjectRepoOwner
                                                  repo:kProjectRepoName
                                            completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.updateRowLoading = NO;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[rowPath] withRowAnimation:UITableViewRowAnimationNone];

        NSDictionary *release = [jsonObject isKindOfClass:[NSDictionary class]] ? jsonObject : nil;
        id tagValue = release ? [release objectForKey:@"tag_name"] : nil;
        NSString *tag = [tagValue isKindOfClass:[NSString class]] ? tagValue : nil;

        if (error || tag.length == 0) {
            [strongSelf showUpdateAlertWithTitle:GHL(@"Обновления")
                                          message:GHL(@"Не удалось проверить обновления. Попробуйте позже.")];
            return;
        }

        NSString *latest = [strongSelf normalizedVersionString:tag];
        NSString *current = [strongSelf normalizedVersionString:[strongSelf versionString]];

        if ([latest compare:current options:NSNumericSearch] != NSOrderedDescending) {
            [strongSelf showUpdateAlertWithTitle:GHL(@"Обновления")
                                          message:GHL(@"Установлена последняя версия.")];
            return;
        }

        strongSelf.pendingUpdateRelease = release;

        NSString *message = [NSString stringWithFormat:GHL(@"Доступна версия %@. Текущая — %@."), latest, current];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Доступно обновление")
                                                         message:message
                                                        delegate:strongSelf
                                               cancelButtonTitle:GHL(@"Позже")
                                               otherButtonTitles:GHL(@"Открыть"), nil];
        alert.tag = kUpdateAlertTag;
        [alert show];
    }];
}

- (void)openProjectRepository {
    if (self.repoRowLoading) return;
    self.repoRowLoading = YES;

    NSIndexPath *rowPath = [NSIndexPath indexPathForRow:2 inSection:kSettingsSectionAbout];
    [self.tableView reloadRowsAtIndexPaths:@[rowPath] withRowAnimation:UITableViewRowAnimationNone];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] repoDetailForOwner:kProjectRepoOwner
                                               repo:kProjectRepoName
                                         completion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        strongSelf.repoRowLoading = NO;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[rowPath] withRowAnimation:UITableViewRowAnimationNone];

        if (!error && [jsonObject isKindOfClass:[NSDictionary class]]) {
            RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
            overviewVC.repo = jsonObject;
            overviewVC.title = [jsonObject[@"name"] isKindOfClass:[NSString class]] ? jsonObject[@"name"] : kProjectRepoName;
            [strongSelf.navigationController pushViewController:overviewVC animated:YES];
            return;
        }

        NSString *urlString = [NSString stringWithFormat:@"https://github.com/%@/%@", kProjectRepoOwner, kProjectRepoName];
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]];
    }];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSettingsSectionAccount) return 44;
    if (indexPath.section == kSettingsSectionAppearance) return 44;
    if (indexPath.section == kSettingsSectionLinks) {
        CGFloat cellWidth = tableView.bounds.size.width - 20;
        return [GHSwitchDescriptionCell heightForDescription:GHL(@"Ссылки github.com из Safari и других приложений будут открываться здесь")
                                                    cellWidth:cellWidth];
    }
    if (indexPath.row == 0) return 44;
    if (indexPath.row == 2) return 44;
    if (indexPath.row == 3) return 30;
    if (indexPath.row == 4) return 44;
    CGFloat width = tableView.bounds.size.width - 40;
    return [self heightForText:[self descriptionText] width:width] + 24;
}

@end
