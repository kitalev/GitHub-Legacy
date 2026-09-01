#import "SettingsViewController.h"
#import "GHThemeManager.h"
#import "GHAuthManager.h"
#import "GHAPIClient.h"
#import "GHLocalization.h"
#import "LanguageViewController.h"
#import "TokenLoginViewController.h"
#import "RepoOverviewViewController.h"

typedef NS_ENUM(NSInteger, GHSettingsSection) {
    kSettingsSectionAccount = 0,
    kSettingsSectionAppearance,
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

static NSString * const kProjectRepoOwner = @"kitalev";
static NSString * const kProjectRepoName = @"GitHub-Legacy";

static const NSInteger kLogoutAlertTag = 1;

@interface SettingsViewController ()

@property (nonatomic, copy) NSString *loggedInUsername;
@property (nonatomic, assign) BOOL accountRowLoading;

@property (nonatomic, assign) BOOL repoRowLoading;
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

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kDescriptionCellID];

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

    TokenLoginViewController *tokenVC = [[TokenLoginViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    tokenVC.onLoggedIn = ^{
        [weakSelf refreshAccountRow];
    };
    [self.navigationController pushViewController:tokenVC animated:YES];
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
}

#pragma mark - Об экране

- (NSString *)appDisplayName {
    return @"GitHub Legacy";
}

- (NSString *)versionString {
    return @"1.0";
}

- (NSString *)descriptionText {
    return GHL(@"Лёгкий нативный клиент GitHub для iOS 6–10: репозитории, README на нескольких языках, issues, pull request'ы, коммиты и релизы — без Safari и без официального приложения, которое на этих версиях уже не запустить.\n\nmade by kitalev");
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSettingsSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kSettingsSectionAccount) return GHL(@"Аккаунт");
    if (section == kSettingsSectionAppearance) return GHL(@"Внешний вид");
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
    if (section == kSettingsSectionAbout) return 4;
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
            cell.textLabel.textColor = GHTintColor() ?: [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
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

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDescriptionCellID forIndexPath:indexPath];
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
    }
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
    if (indexPath.row == 0) return 44;
    if (indexPath.row == 2) return 44;
    if (indexPath.row == 3) return 30;
    CGFloat width = tableView.bounds.size.width - 40;
    return [self heightForText:[self descriptionText] width:width] + 24;
}

@end
