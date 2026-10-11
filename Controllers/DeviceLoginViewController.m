#import "DeviceLoginViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHAuthManager.h"
#import "GHAPIClient.h"
#import "GHDeviceLogin.h"
#import "GHIconRenderer.h"
#import "GHLoginSuccessView.h"
#import "WebLoginViewController.h"

static NSString * const kGHDeviceLoginScope = @"repo user:follow";

static UIColor *GHDeviceLoginErrorColor(void) {
    return [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
}

static UILabel *GHDeviceLoginMakeLabel(UIFont *font, NSTextAlignment alignment) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textAlignment = alignment;
    label.numberOfLines = 0;
    return label;
}

@interface DeviceLoginViewController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;

@property (nonatomic, strong) UILabel *clientIDExplanationLabel;
@property (nonatomic, strong) UITextField *clientIDField;
@property (nonatomic, strong) UIButton *clientIDContinueButton;

@property (nonatomic, strong) UIImageView *headerIconView;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UIView *codeCard;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *expiryLabel;
@property (nonatomic, strong) UIButton *codeCopyButton;
@property (nonatomic, strong) UIButton *refreshCodeButton;
@property (nonatomic, strong) UIView *stepsCard;
@property (nonatomic, strong) UILabel *stepsLabel;
@property (nonatomic, strong) UIButton *openHereButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retryButton;

@property (nonatomic, strong) GHLoginSuccessView *successView;

@property (nonatomic, copy) NSString *deviceCode;
@property (nonatomic, strong) NSURL *verificationURL;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) NSTimer *countdownTimer;
@property (nonatomic, assign) NSTimeInterval expiresAt;
@property (nonatomic, assign) BOOL waitingForCode;
@property (nonatomic, assign) BOOL statusIsError;
@end

@implementation DeviceLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = GHL(@"Вход через github.com");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.clientIDExplanationLabel = GHDeviceLoginMakeLabel([UIFont systemFontOfSize:14], NSTextAlignmentLeft);
    self.clientIDExplanationLabel.text = GHL(@"Для входа через github.com/login/device нужен Client ID OAuth-приложения с включённым Device Flow.\n\nСоздать: github.com → Settings → Developer settings → OAuth Apps → New OAuth App → включите «Enable Device Flow». Client Secret не нужен.\n\nВпишите Client ID ниже — он сохранится на этом устройстве.");
    [self.scrollView addSubview:self.clientIDExplanationLabel];

    self.clientIDField = [[UITextField alloc] init];
    self.clientIDField.borderStyle = UITextBorderStyleRoundedRect;
    self.clientIDField.placeholder = @"Client ID";
    self.clientIDField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.clientIDField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.clientIDField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.clientIDField.returnKeyType = UIReturnKeyGo;
    self.clientIDField.delegate = self;
    [self.scrollView addSubview:self.clientIDField];

    self.clientIDContinueButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.clientIDContinueButton setTitle:GHL(@"Продолжить") forState:UIControlStateNormal];
    self.clientIDContinueButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.clientIDContinueButton addTarget:self action:@selector(clientIDContinueTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.clientIDContinueButton];

    self.headerIconView = [[UIImageView alloc] init];
    self.headerIconView.contentMode = UIViewContentModeCenter;
    [self.scrollView addSubview:self.headerIconView];

    self.headerTitleLabel = GHDeviceLoginMakeLabel([UIFont boldSystemFontOfSize:19], NSTextAlignmentCenter);
    self.headerTitleLabel.text = GHL(@"Введите код на github.com");
    [self.scrollView addSubview:self.headerTitleLabel];

    self.codeCard = [[UIView alloc] init];
    self.codeCard.layer.cornerRadius = 12.0;
    self.codeCard.layer.borderWidth = 1.0;
    [self.scrollView addSubview:self.codeCard];

    UIFont *codeFont = [UIFont fontWithName:@"Menlo-Bold" size:34] ?: [UIFont fontWithName:@"Courier-Bold" size:36] ?: [UIFont boldSystemFontOfSize:34];
    self.codeLabel = GHDeviceLoginMakeLabel(codeFont, NSTextAlignmentCenter);
    self.codeLabel.numberOfLines = 1;
    self.codeLabel.adjustsFontSizeToFitWidth = YES;
    if ([self.codeLabel respondsToSelector:@selector(setMinimumScaleFactor:)]) {
        self.codeLabel.minimumScaleFactor = 0.6;
    } else {
        self.codeLabel.minimumFontSize = codeFont.pointSize * 0.6;
    }
    [self.codeCard addSubview:self.codeLabel];

    self.expiryLabel = GHDeviceLoginMakeLabel([UIFont systemFontOfSize:13], NSTextAlignmentCenter);
    self.expiryLabel.numberOfLines = 1;
    [self.codeCard addSubview:self.expiryLabel];

    self.codeCopyButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.codeCopyButton setTitle:GHL(@"Скопировать") forState:UIControlStateNormal];
    self.codeCopyButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.codeCopyButton addTarget:self action:@selector(codeCopyTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.codeCopyButton];

    self.refreshCodeButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.refreshCodeButton setTitle:GHL(@"Новый код") forState:UIControlStateNormal];
    self.refreshCodeButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.refreshCodeButton addTarget:self action:@selector(refreshCodeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.refreshCodeButton];

    self.stepsCard = [[UIView alloc] init];
    self.stepsCard.layer.cornerRadius = 12.0;
    self.stepsCard.layer.borderWidth = 1.0;
    [self.scrollView addSubview:self.stepsCard];

    self.stepsLabel = GHDeviceLoginMakeLabel([UIFont systemFontOfSize:15], NSTextAlignmentLeft);
    self.stepsLabel.text = GHL(@"1. Нажмите «Открыть github.com здесь» — код скопируется сам. Или откройте github.com/login/device на другом устройстве\n2. Войдите в аккаунт и вставьте код\n3. Нажмите «Authorize» — этот экран обновится сам");
    [self.stepsCard addSubview:self.stepsLabel];

    self.openHereButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [self.openHereButton setTitle:GHL(@"Открыть github.com здесь") forState:UIControlStateNormal];
    self.openHereButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.openHereButton addTarget:self action:@selector(openHereTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.openHereButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.scrollView addSubview:self.spinner];

    self.statusLabel = GHDeviceLoginMakeLabel([UIFont systemFontOfSize:14], NSTextAlignmentCenter);
    [self.scrollView addSubview:self.statusLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.scrollView addSubview:self.retryButton];

    [self buildSuccessView];
    [self applyTheme];
    [self showClientIDStepAllowingAutoStart:YES];
}

- (void)buildSuccessView {
    self.successView = [[GHLoginSuccessView alloc] initWithFrame:self.view.bounds];
    self.successView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.successView.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.successView.onDone = ^{
        [weakSelf successDoneTapped];
    };
    [self.view addSubview:self.successView];
}

- (void)applyTheme {
    self.view.backgroundColor = GHBackgroundColor();
    [self.successView applyTheme];

    self.clientIDExplanationLabel.textColor = GHSecondaryTextColor();
    self.headerIconView.image = [GHIconRenderer devicesIconWithColor:GHTintColor() size:56];
    self.headerTitleLabel.textColor = GHPrimaryTextColor();

    self.codeCard.backgroundColor = GHCellBackgroundColor();
    self.codeCard.layer.borderColor = GHSeparatorColor().CGColor;
    self.codeLabel.textColor = GHPrimaryTextColor();
    self.expiryLabel.textColor = GHSecondaryTextColor();

    self.stepsCard.backgroundColor = GHCellBackgroundColor();
    self.stepsCard.layer.borderColor = GHSeparatorColor().CGColor;
    self.stepsLabel.textColor = GHPrimaryTextColor();

    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
    self.statusLabel.textColor = self.statusIsError ? GHDeviceLoginErrorColor() : GHSecondaryTextColor();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController]) {
        [self stopTimers];
    }
}

- (void)stopTimers {
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
}

#pragma mark - Layout

- (CGFloat)contentWidth {
    return MIN(self.view.bounds.size.width - 30, 460);
}

- (CGFloat)contentLeft {
    return floor((self.view.bounds.size.width - [self contentWidth]) / 2.0);
}

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.text.length == 0) return 0;
    return ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (void)layoutContent {
    CGFloat width = [self contentWidth];
    CGFloat left = [self contentLeft];
    CGFloat y = 20;

    if (!self.clientIDField.hidden) {
        CGFloat h = [self heightForLabel:self.clientIDExplanationLabel width:width];
        self.clientIDExplanationLabel.frame = CGRectMake(left, y, width, h);
        y += h + 14;

        self.clientIDField.frame = CGRectMake(left, y, width, 40);
        y += 40 + 15;

        self.clientIDContinueButton.frame = CGRectMake(left, y, width, 44);
        y += 44 + 20;

        self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);
        return;
    }

    self.headerIconView.frame = CGRectMake(left, y, width, 60);
    y += 60 + 8;

    CGFloat titleHeight = [self heightForLabel:self.headerTitleLabel width:width];
    self.headerTitleLabel.frame = CGRectMake(left, y, width, titleHeight);
    y += titleHeight + 18;

    CGFloat expiryHeight = self.expiryLabel.text.length > 0 ? 18 : 0;
    CGFloat cardHeight = 20 + 48 + (expiryHeight > 0 ? 4 + expiryHeight : 0) + 16;
    self.codeCard.frame = CGRectMake(left, y, width, cardHeight);
    self.codeLabel.frame = CGRectMake(12, 20, width - 24, 48);
    self.expiryLabel.frame = CGRectMake(12, 20 + 48 + 4, width - 24, expiryHeight);
    y += cardHeight + 12;

    CGFloat buttonWidth = floor((width - 10) / 2.0);
    self.codeCopyButton.frame = CGRectMake(left, y, buttonWidth, 40);
    self.refreshCodeButton.frame = CGRectMake(left + width - buttonWidth, y, buttonWidth, 40);
    y += 40 + 18;

    CGFloat stepsHeight = [self heightForLabel:self.stepsLabel width:width - 28];
    self.stepsCard.frame = CGRectMake(left, y, width, stepsHeight + 28);
    self.stepsLabel.frame = CGRectMake(14, 14, width - 28, stepsHeight);
    y += stepsHeight + 28 + 12;

    self.openHereButton.frame = CGRectMake(left, y, width, 44);
    y += 44 + 20;

    CGFloat statusHeight = [self heightForLabel:self.statusLabel width:width - 30];
    if (self.spinner.isAnimating && self.retryButton.hidden) {
        CGSize statusSize = [self.statusLabel sizeThatFits:CGSizeMake(width - 30, CGFLOAT_MAX)];
        CGFloat rowWidth = 20 + 8 + MIN(statusSize.width, width - 30);
        CGFloat rowLeft = left + floor((width - rowWidth) / 2.0);
        self.spinner.frame = CGRectMake(rowLeft, y + floor((MAX(statusHeight, 20) - 20) / 2.0), 20, 20);
        self.statusLabel.frame = CGRectMake(rowLeft + 28, y, MIN(statusSize.width, width - 30), MAX(statusHeight, 20));
        y += MAX(statusHeight, 20) + 16;
    } else {
        self.statusLabel.frame = CGRectMake(left, y, width, statusHeight);
        y += statusHeight + (statusHeight > 0 ? 14 : 0);
    }

    if (!self.retryButton.hidden) {
        self.retryButton.frame = CGRectMake(left, y, width, 44);
        y += 44 + 20;
    }

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

#pragma mark - Client ID step

- (void)setFlowViewsHidden:(BOOL)hidden {
    self.headerIconView.hidden = hidden;
    self.headerTitleLabel.hidden = hidden;
    self.codeCard.hidden = hidden;
    self.codeCopyButton.hidden = hidden;
    self.refreshCodeButton.hidden = hidden;
    self.stepsCard.hidden = hidden;
    self.openHereButton.hidden = hidden;
    self.statusLabel.hidden = hidden;
}

- (void)showClientIDStepAllowingAutoStart:(BOOL)allowAutoStart {
    [self stopTimers];
    NSString *existing = [GHDeviceLogin clientID];

    self.clientIDField.hidden = NO;
    self.clientIDExplanationLabel.hidden = NO;
    self.clientIDContinueButton.hidden = NO;
    self.clientIDField.text = existing ?: @"";

    [self setFlowViewsHidden:YES];
    [self.spinner stopAnimating];
    self.retryButton.hidden = YES;

    if (allowAutoStart && existing.length > 0) {
        [self startFlow];
        return;
    }

    [self layoutContent];
}

- (void)clientIDContinueTapped {
    NSString *clientID = [self.clientIDField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clientID.length == 0) return;
    [self.clientIDField resignFirstResponder];
    [GHDeviceLogin setClientID:clientID];
    [self startFlow];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self clientIDContinueTapped];
    return YES;
}

#pragma mark - Device flow

- (void)setStatus:(NSString *)status isError:(BOOL)isError {
    self.statusIsError = isError;
    self.statusLabel.text = status;
    self.statusLabel.textColor = isError ? GHDeviceLoginErrorColor() : GHSecondaryTextColor();
}

- (void)startFlow {
    [self stopTimers];

    self.clientIDField.hidden = YES;
    self.clientIDExplanationLabel.hidden = YES;
    self.clientIDContinueButton.hidden = YES;
    [self setFlowViewsHidden:NO];
    self.retryButton.hidden = YES;

    self.deviceCode = nil;
    self.waitingForCode = YES;
    self.codeLabel.text = @"····-····";
    self.codeLabel.alpha = 0.35;
    self.expiryLabel.text = @"";
    self.codeCopyButton.enabled = NO;
    self.openHereButton.enabled = NO;
    self.refreshCodeButton.enabled = NO;
    [self.codeCopyButton setTitle:GHL(@"Скопировать") forState:UIControlStateNormal];
    [self setStatus:GHL(@"Получение кода…") isError:NO];
    [self.spinner startAnimating];
    [self layoutContent];

    __weak typeof(self) weakSelf = self;
    [GHDeviceLogin requestDeviceCodeWithScope:kGHDeviceLoginScope
                                    completion:^(NSString *deviceCode, NSString *userCode, NSString *verificationURI,
                                                 NSInteger interval, NSInteger expiresIn, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.waitingForCode = NO;
        strongSelf.refreshCodeButton.enabled = YES;

        if (error || deviceCode.length == 0) {
            strongSelf.codeLabel.text = @"····-····";
            [strongSelf showError:error.localizedDescription.length > 0 ? error.localizedDescription
                                                                         : GHL(@"Не удалось получить код. Проверьте Client ID.")
                    offerClientIDReset:![GHDeviceLogin hasBuiltInClientID]];
            return;
        }

        strongSelf.deviceCode = deviceCode;
        strongSelf.codeLabel.text = userCode;
        strongSelf.codeLabel.alpha = 1.0;
        strongSelf.codeCopyButton.enabled = YES;
        strongSelf.verificationURL = (verificationURI.length > 0 ? [NSURL URLWithString:verificationURI] : nil)
            ?: [NSURL URLWithString:@"https://github.com/login/device"];
        strongSelf.openHereButton.enabled = YES;
        NSInteger lifetime = expiresIn;
        if (lifetime % 60 >= 55) lifetime += 60 - lifetime % 60;
        strongSelf.expiresAt = [NSDate timeIntervalSinceReferenceDate] + lifetime;
        [strongSelf setStatus:GHL(@"Ожидание подтверждения…") isError:NO];
        [strongSelf updateExpiryLabel];
        strongSelf.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                       target:strongSelf
                                                                     selector:@selector(updateExpiryLabel)
                                                                     userInfo:nil
                                                                      repeats:YES];
        [strongSelf layoutContent];
        [strongSelf schedulePollWithInterval:MAX(interval, 5)];
    }];
}

- (void)updateExpiryLabel {
    NSTimeInterval remaining = self.expiresAt - [NSDate timeIntervalSinceReferenceDate];
    if (remaining <= 0) {
        [self showError:GHL(@"Код истёк. Получите новый.") offerClientIDReset:NO];
        return;
    }
    NSInteger total = (NSInteger)ceil(remaining);
    self.expiryLabel.text = [NSString stringWithFormat:GHL(@"Код действует ещё %ld:%02ld"), (long)(total / 60), (long)(total % 60)];
}

- (void)schedulePollWithInterval:(NSInteger)interval {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                        target:self
                                                      selector:@selector(pollTick)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (void)pollTick {
    self.pollTimer = nil;
    if (self.deviceCode.length == 0) return;

    NSString *polledCode = self.deviceCode;
    __weak typeof(self) weakSelf = self;
    [GHDeviceLogin pollAccessTokenWithDeviceCode:polledCode
                                       completion:^(GHDevicePollResult result, NSString *accessToken, NSInteger newInterval, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf.deviceCode isEqualToString:polledCode]) return;

        switch (result) {
            case GHDevicePollResultPending:
                [strongSelf schedulePollWithInterval:5];
                break;
            case GHDevicePollResultSlowDown:
                [strongSelf schedulePollWithInterval:MAX(newInterval, 10)];
                break;
            case GHDevicePollResultExpired:
                [strongSelf showError:GHL(@"Код истёк. Получите новый.") offerClientIDReset:NO];
                break;
            case GHDevicePollResultDenied:
                [strongSelf showError:GHL(@"Вход отклонён.") offerClientIDReset:NO];
                break;
            case GHDevicePollResultError:
                [strongSelf showError:error.localizedDescription.length > 0 ? error.localizedDescription
                                                                             : GHL(@"Что-то пошло не так.")
                        offerClientIDReset:NO];
                break;
            case GHDevicePollResultSuccess:
                [strongSelf finishWithAccessToken:accessToken];
                break;
        }
    }];
}

- (void)openHereTapped {
    if (self.deviceCode.length == 0 || self.verificationURL == nil) return;
    [UIPasteboard generalPasteboard].string = self.codeLabel.text;
    WebLoginViewController *webVC = [[WebLoginViewController alloc] init];
    webVC.startURL = self.verificationURL;
    [self.navigationController pushViewController:webVC animated:YES];
}

- (void)finishWithAccessToken:(NSString *)accessToken {
    [self stopTimers];
    self.deviceCode = nil;
    if (self.navigationController.topViewController != self) {
        [self.navigationController popToViewController:self animated:YES];
    }

    [[GHAuthManager sharedManager] setAccessToken:accessToken];
    [self setStatus:GHL(@"Готово, входим…") isError:NO];
    [self layoutContent];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        BOOL valid = !error && [jsonObject isKindOfClass:[NSDictionary class]] && [jsonObject[@"login"] length] > 0;
        if (!valid) {
            [[GHAuthManager sharedManager] logout];
            [strongSelf showError:GHL(@"Не удалось войти после подтверждения. Попробуйте ещё раз.") offerClientIDReset:NO];
            return;
        }

        NSString *login = jsonObject[@"login"];
        [GHAuthManager sharedManager].currentUserLogin = login;
        NSString *avatarURL = [jsonObject[@"avatar_url"] isKindOfClass:[NSString class]] ? jsonObject[@"avatar_url"] : nil;

        if (strongSelf.onLoggedIn) strongSelf.onLoggedIn();
        [strongSelf showSuccessForLogin:login avatarURL:avatarURL];
    }];
}

- (void)showSuccessForLogin:(NSString *)login avatarURL:(NSString *)avatarURL {
    [self.spinner stopAnimating];
    [self.view endEditing:YES];
    [self.navigationItem setHidesBackButton:YES animated:YES];
    [self.successView presentForLogin:login avatarURL:avatarURL];
}

- (void)successDoneTapped {
    NSArray *stack = self.navigationController.viewControllers;
    NSUInteger index = [stack indexOfObject:self];
    if (index != NSNotFound && index >= 2) {
        [self.navigationController popToViewController:stack[index - 2] animated:YES];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)showError:(NSString *)message offerClientIDReset:(BOOL)offerClientIDReset {
    [self stopTimers];
    [self.spinner stopAnimating];
    self.deviceCode = nil;
    self.codeLabel.alpha = 0.35;
    self.codeCopyButton.enabled = NO;
    self.openHereButton.enabled = NO;
    self.refreshCodeButton.enabled = YES;
    self.expiryLabel.text = @"";

    self.retryButton.hidden = !offerClientIDReset;
    [self.retryButton setTitle:GHL(@"Изменить Client ID") forState:UIControlStateNormal];
    [self setStatus:message isError:YES];
    [self layoutContent];
}

- (void)retryTapped {
    [self showClientIDStepAllowingAutoStart:NO];
}

- (void)refreshCodeTapped {
    if (self.waitingForCode) return;
    [self startFlow];
}

- (void)codeCopyTapped {
    if (self.deviceCode.length == 0 || self.codeLabel.text.length == 0) return;
    [UIPasteboard generalPasteboard].string = self.codeLabel.text;
    [self.codeCopyButton setTitle:GHL(@"Скопировано") forState:UIControlStateNormal];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.codeCopyButton setTitle:GHL(@"Скопировать") forState:UIControlStateNormal];
    });
}

- (void)dealloc {
    [self stopTimers];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
