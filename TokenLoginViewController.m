#import "TokenLoginViewController.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHAuthManager.h"
#import "GHAPIClient.h"

@interface TokenLoginViewController () <UITextViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UITextView *explanationView;
@property (nonatomic, strong) UITextField *tokenField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation TokenLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = GHL(@"Вход по токену");
    self.view.backgroundColor = GHBackgroundColor();

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
    [self.view addSubview:self.scrollView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];

    self.tokenField = [[UITextField alloc] initWithFrame:CGRectMake(15, 15, self.view.bounds.size.width - 30, 40)];
    self.tokenField.borderStyle = UITextBorderStyleRoundedRect;
    self.tokenField.placeholder = GHL(@"Вставьте токен сюда");
    self.tokenField.secureTextEntry = YES;
    self.tokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tokenField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.tokenField.returnKeyType = UIReturnKeyGo;
    self.tokenField.delegate = (id<UITextFieldDelegate>)self;
    self.tokenField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.tokenField];

    self.loginButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.loginButton.frame = CGRectMake(15, 0, self.view.bounds.size.width - 30, 44);
    [self.loginButton setTitle:GHL(@"Войти") forState:UIControlStateNormal];
    self.loginButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.loginButton addTarget:self action:@selector(loginTapped) forControlEvents:UIControlEventTouchUpInside];
    self.loginButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.loginButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.scrollView addSubview:self.spinner];

    self.explanationView = [[UITextView alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 100)];
    self.explanationView.editable = NO;
    self.explanationView.scrollEnabled = NO;
    self.explanationView.dataDetectorTypes = UIDataDetectorTypeLink;
    self.explanationView.font = [UIFont systemFontOfSize:15];
    self.explanationView.text = [self explanationText];
    self.explanationView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scrollView addSubview:self.explanationView];

    [self applyTheme];
    [self layoutContent];
}

- (NSString *)explanationText {
    return GHL(@"Personal Access Token — это персональный ключ доступа к вашему аккаунту GitHub, который вы создаёте сами на сайте, без входа через встроенный браузер приложения.\n\nСоздать токен можно здесь:\nhttps://github.com/settings/tokens\n\nКак создать токен по шагам:\n\n1. Откройте ссылку выше (или вручную: github.com → Settings → Developer settings → Personal access tokens → Tokens (classic)) и нажмите «Generate new token» → «Generate new token (classic)».\n\n2. В поле «Note» впишите любое понятное название токена — например, название этого телефона или приложения. Оно нужно только вам, чтобы потом узнавать этот токен в списке на github.com.\n\n3. В «Expiration» задайте срок действия — по истечении токен перестанет работать, и потребуется создать новый (по умолчанию стоит «No expiration», то есть без ограничения срока).\n\n4. В «Select scopes» отметьте нужные права. Проще всего отметить галочку «repo» самую первую в списке (Full control of private repositories) — она сразу даёт доступ и на чтение, и на запись ко всем репозиториям, этого достаточно для всех функций приложения, включая добавление в избранное. Если нужен доступ только к публичным репозиториям без приватных, вместо неё можно отметить только «public_repo» (это подпункт внутри «repo»). Остальные галочки не нужны.\n\n5. Нажмите «Generate token» внизу страницы и скопируйте получившийся токен — он показывается только один раз, при следующем открытии страницы вы его уже не увидите.\n\n6. Вернитесь в приложение и вставьте скопированный токен в поле выше.");
}

- (void)applyTheme {
    self.view.backgroundColor = GHBackgroundColor();
    self.explanationView.backgroundColor = GHBackgroundColor();
    self.explanationView.textColor = GHPrimaryTextColor();
    self.tokenField.textColor = GHPrimaryTextColor();
    self.tokenField.backgroundColor = GHCellBackgroundColor();
    self.spinner.activityIndicatorViewStyle = GHSpinnerStyle();
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutContent];
}

- (void)layoutContent {
    CGFloat width = self.view.bounds.size.width - 30;

    self.tokenField.frame = CGRectMake(15, 15, width, 40);

    CGFloat y = CGRectGetMaxY(self.tokenField.frame) + 15;
    self.loginButton.frame = CGRectMake(15, y, width, 44);
    self.spinner.center = CGPointMake(self.loginButton.center.x, CGRectGetMaxY(self.loginButton.frame) + 20);

    y = CGRectGetMaxY(self.loginButton.frame) + 30;
    self.explanationView.frame = CGRectMake(15, y, width, self.explanationView.frame.size.height);
    CGSize fitSize = [self.explanationView sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
    self.explanationView.frame = CGRectMake(15, y, width, fitSize.height);

    CGFloat contentHeight = CGRectGetMaxY(self.explanationView.frame) + 30;
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, contentHeight);
}

- (void)dismissKeyboard {
    [self.tokenField resignFirstResponder];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat keyboardHeight = keyboardFrame.size.height;
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = keyboardHeight;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    [self.scrollView scrollRectToVisible:CGRectInset(self.tokenField.frame, 0, -20) animated:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = 0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self loginTapped];
    return YES;
}

#pragma mark - Вход

- (void)loginTapped {
    [self dismissKeyboard];

    NSString *token = [self.tokenField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (token.length == 0) return;

    [[GHAuthManager sharedManager] setAccessToken:token];
    self.loginButton.enabled = NO;
    [self.spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    [[GHAPIClient sharedClient] currentUserWithCompletion:^(id jsonObject, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;

        BOOL valid = !error && [jsonObject isKindOfClass:[NSDictionary class]] && [jsonObject[@"login"] length] > 0;

        strongSelf.loginButton.enabled = YES;
        [strongSelf.spinner stopAnimating];

        if (!valid) {
            [[GHAuthManager sharedManager] logout];

            NSString *reason = error.localizedDescription.length > 0
                ? error.localizedDescription
                : GHL(@"Не удалось войти — проверьте правильность токена и его срок действия.");
            UIAlertView *errorAlert = [[UIAlertView alloc] initWithTitle:GHL(@"Ошибка входа")
                                                                   message:reason
                                                                  delegate:nil
                                                         cancelButtonTitle:@"OK"
                                                         otherButtonTitles:nil];
            [errorAlert show];
            return;
        }

        if (strongSelf.onLoggedIn) strongSelf.onLoggedIn();
        [strongSelf.navigationController popViewControllerAnimated:YES];
    }];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
