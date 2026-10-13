#import "TokenLoginViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHAuthManager.h"
#import "GHAPIClient.h"
#import "GHIconRenderer.h"
#import "GHLoginSuccessView.h"

static NSString * const kGHTokenSettingsURL = @"https://github.com/settings/tokens";

static UIColor *GHTokenLoginErrorColor(void) {
    return [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
}

static UILabel *GHTokenLoginMakeLabel(UIFont *font, NSTextAlignment alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}

@interface TokenLoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;

@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerSubtitleLabel;

@property (nonatomic, strong) UIView *fieldCard;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UIButton *pasteButton;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;

@property (nonatomic, strong) UILabel *stepsTitleLabel;
@property (nonatomic, strong) UIView *stepsCard;
@property (nonatomic, strong) UILabel *stepsLabel;
@property (nonatomic, strong) UIButton *openSettingsButton;

@property (nonatomic, strong) GHLoginSuccessView *successView;
@property (nonatomic, assign) BOOL statusIsError;
@end

@implementation TokenLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = GHL(@"Вход по токену");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillShow:)
                                                  name:UIKeyboardWillShowNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillHide:)
                                                  name:UIKeyboardWillHideNotification
                                                object:nil];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];

    self.headerIconView = [[UIImageView alloc] init];
    self.headerIconView.contentMode = UIViewContentModeCenter;
    [self.scrollView addSubview:self.headerIconView];

    self.headerTitleLabel = GHTokenLoginMakeLabel([UIFont boldSystemFontOfSize:19], NSTextAlignmentCenter);
    self.headerTitleLabel.text = @"Personal Access Token";
    [self.scrollView addSubview:self.headerTitleLabel];

    self.headerSubtitleLabel = GHTokenLoginMakeLabel([UIFont systemFontOfSize:14], NSTextAlignmentCenter);
    self.headerSubtitleLabel.text = GHL(@"Ключ доступа, который вы создаёте сами на github.com");
    [self.scrollView addSubview:self.headerSubtitleLabel];

    self.fieldCard = [[UIView alloc] init];
    self.fieldCard.layer.cornerRadius = 12.0;
    self.fieldCard.layer.borderWidth = 1.0;
    [self.scrollView addSubview:self.fieldCard];

    self.tokenField = [[UITextField alloc] init];
    self.tokenField.borderStyle = UITextBorderStyleNone;
    self.tokenField.backgroundColor = [UIColor clearColor];
    self.tokenField.font = [UIFont systemFontOfSize:16];
    self.tokenField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    self.tokenField.placeholder = @"ghp_…";
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.tokenField.returnKeyType = UIReturnKeyGo;
    self.tokenField.delegate = self;
    [self.tokenField addTarget:self action:@selector(tokenChanged) forControlEvents:UIControlEventEditingChanged];
    [self.fieldCard addSubview:self.tokenField];

    self.pasteButton = GHMakeButton(GHButtonStyleSecondary);
    [self.pasteButton setTitle:GHL(@"Вставить") forState:UIControlStateNormal];
    self.pasteButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.pasteButton addTarget:self action:@selector(pasteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.fieldCard addSubview:self.pasteButton];

    self.loginButton = GHMakeButton(GHButtonStylePrimary);
    [self.loginButton setTitle:GHL(@"Войти") forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.loginButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.scrollView addSubview:self.spinner];

    self.statusLabel = GHTokenLoginMakeLabel([UIFont systemFontOfSize:14], NSTextAlignmentCenter);
    [self.scrollView addSubview:self.statusLabel];

    self.stepsTitleLabel = GHTokenLoginMakeLabel([UIFont boldSystemFontOfSize:17], NSTextAlignmentLeft);
    self.stepsTitleLabel.text = GHL(@"Как получить токен");
    [self.scrollView addSubview:self.stepsTitleLabel];

    self.stepsCard = [[UIView alloc] init];
    self.stepsCard.layer.cornerRadius = 12.0;
    self.stepsCard.layer.borderWidth = 1.0;
    [self.scrollView addSubview:self.stepsCard];

    self.stepsLabel = GHTokenLoginMakeLabel([UIFont systemFontOfSize:15], NSTextAlignmentLeft);
    self.stepsLabel.text = GHL(@"1. Откройте github.com/settings/tokens — удобнее с компьютера\n2. Generate new token → Generate new token (classic)\n3. Note — любое название, например «iPhone 4S»\n4. Expiration — срок действия; по истечении нужен новый токен\n5. Scopes — отметьте «repo» и «user:follow». Если приватные репозитории не нужны, вместо «repo» хватит «public_repo»\n6. Generate token — скопируйте токен и вставьте выше. GitHub покажет его только один раз");
    [self.stepsCard addSubview:self.stepsLabel];

    self.openSettingsButton = GHMakeButton(GHButtonStyleSecondary);
    [self.openSettingsButton setTitle:GHL(@"Открыть github.com/settings/tokens") forState:UIControlStateNormal];
    self.openSettingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.openSettingsButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    [self.openSettingsButton addTarget:self action:@selector(openSettingsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.openSettingsButton];

    self.successView = [[GHLoginSuccessView alloc] initWithFrame:self.view.bounds];
    self.successView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.successView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.successView.onDone = ^{
        [weakSelf successDoneTapped];
    };
    [self.view addSubview:self.successView];

    [self applyTheme];
    [self tokenChanged];
}

- (void)applyTheme {
    self.view.backgroundColor = GHBackgroundColor();

    self.headerIconView.image = [GHIconRenderer keyIconWithColor:GHTintColor() size:56];
    self.headerTitleLabel.textColor = GHPrimaryTextColor();
    self.headerSubtitleLabel.textColor = GHSecondaryTextColor();

    self.fieldCard.backgroundColor = GHCellBackgroundColor();
    self.fieldCard.layer.borderColor = GHSeparatorColor().CGColor;
    self.tokenField.textColor = GHPrimaryTextColor();
    GHStyleButton(self.pasteButton, GHButtonStyleSecondary);
    GHStyleButton(self.loginButton, GHButtonStylePrimary);
    GHStyleButton(self.openSettingsButton, GHButtonStyleSecondary);

    self.stepsTitleLabel.textColor = GHPrimaryTextColor();
    self.stepsCard.backgroundColor = GHCellBackgroundColor();
    self.stepsCard.layer.borderColor = GHSeparatorColor().CGColor;
    self.stepsLabel.textColor = GHPrimaryTextColor();

    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.statusLabel.textColor = self.statusIsError ? GHTokenLoginErrorColor() : GHSecondaryTextColor();

    [self.successView applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.text.length == 0) return 0;
    return ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (void)layoutContent {
    CGFloat width = MIN(self.view.bounds.size.width - 30, 460);
    CGFloat left = floor((self.view.bounds.size.width - width) / 2.0);
    CGFloat y = 20;

    self.headerIconView.frame = CGRectMake(left, y, width, 60);
    y += 60 + 8;

    CGFloat titleHeight = [self heightForLabel:self.headerTitleLabel width:width];
    self.headerTitleLabel.frame = CGRectMake(left, y, width, titleHeight);
    y += titleHeight + 4;

    CGFloat subtitleHeight = [self heightForLabel:self.headerSubtitleLabel width:width];
    self.headerSubtitleLabel.frame = CGRectMake(left, y, width, subtitleHeight);
    y += subtitleHeight + 18;

    self.fieldCard.frame = CGRectMake(left, y, width, 50);
    CGFloat pasteWidth = 86;
    self.pasteButton.frame = CGRectMake(width - pasteWidth - 7, 8, pasteWidth, 34);
    self.tokenField.frame = CGRectMake(12, 5, width - pasteWidth - 7 - 12 - 8, 40);
    y += 50 + 12;

    self.loginButton.frame = CGRectMake(left, y, width, 44);
    y += 44 + 14;

    CGFloat statusHeight = [self heightForLabel:self.statusLabel width:width - 30];
    if (self.spinner.isAnimating) {
        CGSize statusSize = [self.statusLabel sizeThatFits:CGSizeMake(width - 30, CGFLOAT_MAX)];
        CGFloat labelWidth = MIN(statusSize.width, width - 30);
        CGFloat rowHeight = MAX(statusHeight, 20);
        CGFloat rowLeft = left + floor((width - (20 + 8 + labelWidth)) / 2.0);
        self.spinner.frame = CGRectMake(rowLeft, y + floor((rowHeight - 20) / 2.0), 20, 20);
        self.statusLabel.frame = CGRectMake(rowLeft + 28, y, labelWidth, rowHeight);
        y += rowHeight + 18;
    } else {
        self.statusLabel.frame = CGRectMake(left, y, width, statusHeight);
        y += statusHeight + (statusHeight > 0 ? 18 : 6);
    }

    self.stepsTitleLabel.frame = CGRectMake(left + 4, y, width - 4, 22);
    y += 22 + 8;

    CGFloat stepsHeight = [self heightForLabel:self.stepsLabel width:width - 28];
    self.stepsCard.frame = CGRectMake(left, y, width, stepsHeight + 28);
    self.stepsLabel.frame = CGRectMake(14, 14, width - 28, stepsHeight);
    y += stepsHeight + 28 + 12;

    self.openSettingsButton.frame = CGRectMake(left, y, width, 40);
    y += 40 + 24;

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

#pragma mark - Status

- (void)setStatus:(NSString *)status isError:(BOOL)isError {
    self.statusIsError = isError;
    self.statusLabel.text = status;
    self.statusLabel.textColor = isError ? GHTokenLoginErrorColor() : GHSecondaryTextColor();
    [self layoutContent];
}

- (void)tokenChanged {
    NSString *token = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.loginButton.enabled = token.length > 0 && !self.spinner.isAnimating;
    if (self.statusIsError) [self setStatus:nil isError:NO];
}

#pragma mark - Actions

- (void)pasteTapped {
    NSString *pasted = [[UIPasteboard generalPasteboard].string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (pasted.length == 0) {
        [self setStatus:GHL(@"В буфере обмена ничего нет.") isError:YES];
        return;
    }
    self.tokenField.text = pasted;
    [self tokenChanged];
}

- (void)openSettingsTapped {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kGHTokenSettingsURL]];
}

- (void)dismissKeyboard {
    [self.tokenField resignFirstResponder];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect converted = [self.view convertRect:keyboardFrame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(converted));
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = overlap;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    [self.scrollView scrollRectToVisible:CGRectInset(self.loginButton.frame, 0, -20) animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = 0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self loginTapped];
    return YES;
}

- (void)loginTapped {
    [self dismissKeyboard];

    NSString *token = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (token.length == 0 || self.spinner.isAnimating) return;

    [[GHAuthManager sharedManager] setAccessToken:token];
    self.loginButton.enabled = NO;
    self.pasteButton.enabled = NO;
    [self.spinner startAnimating];
    [self setStatus:GHL(@"Проверка токена…") isError:NO];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        [strongSelf.spinner stopAnimating];
        strongSelf.pasteButton.enabled = YES;

        BOOL valid = !error && [jsonObject isKindOfClass:[NSDictionary class]] && [jsonObject[@"login"] length] > 0;
        if (!valid) {
            [[GHAuthManager sharedManager] logout];
            NSString *reason = error.localizedDescription.length > 0
                ? error.localizedDescription
                : GHL(@"Не удалось войти — проверьте правильность токена и его срок действия.");
            [strongSelf setStatus:reason isError:YES];
            [strongSelf tokenChanged];
            return;
        }

        NSString *login = jsonObject[@"login"];
        [GHAuthManager sharedManager].currentUserLogin = login;
        NSString *avatarURL = [jsonObject[@"avatar_url"] isKindOfClass:[NSString class]] ? jsonObject[@"avatar_url"] : nil;

        [strongSelf setStatus:nil isError:NO];
        if (strongSelf.onLoggedIn) strongSelf.onLoggedIn();

        [strongSelf.view endEditing:YES];
        [strongSelf.navigationItem setHidesBackButton:YES animated:YES];
        [strongSelf.successView presentForLogin:login avatarURL:avatarURL];
    }];
}

- (void)successDoneTapped {
    NSArray *stack = self.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:self];
    if (index != NSNotFound && index >= 2) {
        [self.navigationController popToViewController:[stack objectAtIndex:index - 2] animated:YES];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
