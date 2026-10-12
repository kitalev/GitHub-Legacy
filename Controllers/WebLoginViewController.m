#import "WebLoginViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHWebSession.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import "GHIconRenderer.h"

typedef NS_ENUM(NSInteger, GHWebLoginStep) {
    GHWebLoginStepLoading,
    GHWebLoginStepCredentials,
    GHWebLoginStepPassword,
    GHWebLoginStepCode,
    GHWebLoginStepChooseMethod,
    GHWebLoginStepAuthorize,
    GHWebLoginStepMobile,
    GHWebLoginStepRetry,
    GHWebLoginStepPage
};

static NSString * const kGHWebLoginAnalyzeScript =
    @"(function(){"
     "function txt(e){return (e.innerText||e.textContent||'').replace(/\\s+/g,' ').replace(/^\\s+|\\s+$/g,'');}"
     "function shown(e){if(!e||e.type=='hidden')return false;var s=window.getComputedStyle(e);"
     "return s.display!='none'&&s.visibility!='hidden'&&(e.offsetWidth>0||e.offsetHeight>0);}"
     "var r={host:location.host,path:location.pathname,forms:[],links:[],errors:[],text:document.body?txt(document.body).substring(0,600):''};"
     "var so=document.querySelector('sudo-credential-options');var et=document.getElementById('sudo-credential-options-totp-email-csrf');"
     "if(so&&et){r.emailInitiateURL=so.getAttribute('totp-email-initiate-url')||'';r.emailInitiateToken=et.value||'';}"
     "var mp=document.getElementById('github-mobile-authenticate-prompt');var mf=document.getElementById('github-mobile-authenticate-form');"
     "if(mp&&mf&&location.pathname.indexOf('/sessions/two-factor')==0){var mt=mf.querySelector('.js-data-url-csrf');var md=mp.querySelector('.mobile-authentication-digits');"
     "r.mobilePollURL=mp.getAttribute('data-poll-url')||'';r.mobileToken=mt?mt.value:'';r.mobileDigits=md?txt(md):'';}"
     "var fl=document.querySelectorAll('.flash-error');"
     "for(var i=0;i<fl.length;i++){var t=txt(fl[i]);if(t&&t.indexOf('{{')<0&&shown(fl[i])&&r.errors.indexOf(t)<0)r.errors.push(t);}"
     "for(var i=0;i<document.forms.length;i++){var f=document.forms[i];"
     "var o={index:i,action:f.getAttribute('action')||'',inputs:[],buttons:[]};"
     "for(var j=0;j<f.elements.length;j++){var e=f.elements[j];var tag=e.tagName.toLowerCase();"
     "var ty=(e.getAttribute('type')||(tag=='button'?'submit':'text')).toLowerCase();"
     "if((tag=='button'||tag=='input')&&ty=='submit'){o.buttons.push({index:j,name:e.name||'',value:e.value||'',text:txt(e)||e.value||'',visible:shown(e)});}"
     "else if(tag=='input'&&(ty=='text'||ty=='password'||ty=='email'||ty=='tel'||ty=='number')){"
     "o.inputs.push({name:e.name||'',type:ty,value:e.value||'',auto:e.getAttribute('autocomplete')||'',visible:shown(e)});}}"
     "r.forms.push(o);}"
     "var as=document.querySelectorAll('a[href]');"
     "for(var i=0;i<as.length;i++){var h=as[i].getAttribute('href')||'';"
     "if(/two-factor|recovery|verified-device|sudo/.test(h))r.links.push({href:as[i].href,text:txt(as[i])});}"
     "return JSON.stringify(r);"
     "})()";

static NSString * const kGHWebLoginSubmitScript =
    @"(function(fi,vals,bi){var f=document.forms[fi];if(!f)return 'none';"
     "for(var k in vals){var e=f.elements[k];if(e&&!e.tagName&&e.length)e=e[0];if(e){e.disabled=false;e.value=vals[k];}}"
     "var b=bi>=0?f.elements[bi]:null;"
     "if(b&&b.name){var h=document.createElement('input');h.type='hidden';h.name=b.name;h.value=b.value;f.appendChild(h);}"
     "f.submit();return 'ok';"
     "})(%ld,%@,%ld)";

static NSString * const kGHWebLoginDeviceCodeScript =
    @"(function(fi,c,bi){var f=document.forms[fi];if(!f)return 'none';var ins=[];"
     "for(var j=0;j<f.elements.length;j++){var e=f.elements[j];var t=(e.getAttribute('type')||'text').toLowerCase();"
     "if(e.tagName.toLowerCase()=='input'&&(t=='text'||t=='tel')&&e.offsetParent!==null)ins.push(e);}"
     "var s=c.replace(/-/g,'');"
     "if(ins.length==1)ins[0].value=c;else for(var j=0;j<ins.length&&j<s.length;j++)ins[j].value=s.charAt(j);"
     "var hs=f.querySelectorAll('input[type=hidden]');"
     "for(var j=0;j<hs.length;j++){if(/user.?code/i.test(hs[j].name))hs[j].value=c;}"
     "var b=bi>=0?f.elements[bi]:null;"
     "if(b&&b.name){var h=document.createElement('input');h.type='hidden';h.name=b.name;h.value=b.value;f.appendChild(h);}"
     "f.submit();return 'ok';"
     "})(%ld,%@[0],%ld)";

static NSString *GHWebLoginJSON(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static NSString *GHWebLoginString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static UILabel *GHWebLoginMakeLabel(UIFont *font) {
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    return label;
}

static UITextField *GHWebLoginMakeField(void) {
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont systemFontOfSize:17];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    return field;
}

@interface WebLoginViewController () <UIWebViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UILabel *digitsLabel;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSTimeInterval pollStartedAt;
@property (nonatomic, copy) NSString *mobilePollURL;
@property (nonatomic, copy) NSString *mobileToken;
@property (nonatomic, strong) NSURL *retryURL;
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *secondField;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner;
@property (nonatomic, strong) NSMutableArray *methodButtons;
@property (nonatomic, copy) NSArray *methods;
@property (nonatomic, assign) GHWebLoginStep step;
@property (nonatomic, assign) GHWebLoginStep lastInputStep;
@property (nonatomic, assign) NSInteger formIndex;
@property (nonatomic, assign) NSInteger buttonIndex;
@property (nonatomic, copy) NSString *firstFieldName;
@property (nonatomic, copy) NSString *secondFieldName;
@property (nonatomic, assign) BOOL submittedDeviceCode;
@property (nonatomic, strong) NSMutableSet *autoSubmittedActions;
@property (nonatomic, assign) BOOL finished;
@end

@implementation WebLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.title.length == 0) self.title = GHL(@"Вход в GitHub");

    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.scalesPageToFit = YES;
    self.webView.hidden = YES;
    [self.view addSubview:self.webView];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.contentMode = UIViewContentModeCenter;
    [self.scrollView addSubview:self.iconView];

    self.titleLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:21]);
    [self.scrollView addSubview:self.titleLabel];

    self.messageLabel = GHWebLoginMakeLabel([UIFont systemFontOfSize:15]);
    [self.scrollView addSubview:self.messageLabel];

    self.errorLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:14]);
    [self.scrollView addSubview:self.errorLabel];

    self.digitsLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:56]);
    self.digitsLabel.hidden = YES;
    [self.scrollView addSubview:self.digitsLabel];

    self.firstField = GHWebLoginMakeField();
    self.firstField.delegate = self;
    [self.scrollView addSubview:self.firstField];

    self.secondField = GHWebLoginMakeField();
    self.secondField.delegate = self;
    self.secondField.secureTextEntry = YES;
    self.secondField.placeholder = GHL(@"Пароль");
    self.secondField.returnKeyType = UIReturnKeyGo;
    [self.scrollView addSubview:self.secondField];

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.primaryButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:self.primaryButton];

    self.progressSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.progressSpinner.hidesWhenStopped = YES;
    [self.scrollView addSubview:self.progressSpinner];

    self.methodButtons = [NSMutableArray array];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.spinner.hidesWhenStopped = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

    NSArray *stack = self.navigationController.viewControllers;
    if (self.presentingViewController && stack.count > 0 && stack[0] == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Отмена")
                                                                                 style:UIBarButtonItemStyleBordered
                                                                                target:self
                                                                                action:@selector(cancelTapped)];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyTheme)
                                                  name:kGHThemeDidChangeNotification
                                                object:nil];
    [self applyTheme];
    [self showLoadingWithMessage:GHL(@"Подключение к github.com…")];
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.startURL ?: [GHWebSession signInURL]]];
}

- (void)applyTheme {
    self.view.backgroundColor = GHBackgroundColor();
    self.scrollView.backgroundColor = GHBackgroundColor();
    self.iconView.image = [GHIconRenderer personIconWithColor:GHTintColor() size:56];
    self.titleLabel.textColor = GHPrimaryTextColor();
    self.digitsLabel.textColor = GHPrimaryTextColor();
    self.messageLabel.textColor = GHSecondaryTextColor();
    self.errorLabel.textColor = [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
    self.progressSpinner.activityIndicatorViewStyle = GHSpinnerStyle();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)cancelTapped {
    [self.webView stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - Layout

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.hidden || label.text.length == 0) return 0;
    return ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (void)layoutContent {
    CGFloat width = MIN(self.view.bounds.size.width - 30, 420);
    CGFloat left = floor((self.view.bounds.size.width - width) / 2.0);
    CGFloat y = 24;

    self.iconView.frame = CGRectMake(left, y, width, 60);
    y += 60 + 10;

    CGFloat titleHeight = [self heightForLabel:self.titleLabel width:width];
    self.titleLabel.frame = CGRectMake(left, y, width, titleHeight);
    y += titleHeight + (titleHeight > 0 ? 8 : 0);

    CGFloat messageHeight = [self heightForLabel:self.messageLabel width:width];
    self.messageLabel.frame = CGRectMake(left, y, width, messageHeight);
    y += messageHeight + (messageHeight > 0 ? 16 : 0);

    CGFloat digitsHeight = [self heightForLabel:self.digitsLabel width:width];
    self.digitsLabel.frame = CGRectMake(left, y, width, digitsHeight);
    y += digitsHeight + (digitsHeight > 0 ? 16 : 0);

    if (self.progressSpinner.isAnimating) {
        self.progressSpinner.frame = CGRectMake(left + floor((width - 20) / 2.0), y, 20, 20);
        y += 20 + 16;
    }

    CGFloat errorHeight = [self heightForLabel:self.errorLabel width:width];
    self.errorLabel.frame = CGRectMake(left, y, width, errorHeight);
    y += errorHeight + (errorHeight > 0 ? 14 : 0);

    if (!self.firstField.hidden) {
        self.firstField.frame = CGRectMake(left, y, width, 44);
        y += 44 + 10;
    }
    if (!self.secondField.hidden) {
        self.secondField.frame = CGRectMake(left, y, width, 44);
        y += 44 + 10;
    }
    if (!self.primaryButton.hidden) {
        y += 6;
        self.primaryButton.frame = CGRectMake(left, y, width, 46);
        y += 46 + 18;
    }
    for (UIButton *button in self.methodButtons) {
        button.frame = CGRectMake(left, y, width, 42);
        y += 42 + 8;
    }

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y + 20);
}

#pragma mark - Steps

- (void)showLoadingWithMessage:(NSString *)message {
    [self presentStep:GHWebLoginStepLoading title:nil message:message error:nil
           firstField:nil secondField:NO primary:nil methods:nil];
    [self saveUnrecognizedPage];
}

- (void)saveDiagnostic:(NSString *)contents named:(NSString *)name {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *path = [documents stringByAppendingPathComponent:[@"GitHubLegacy-login-" stringByAppendingString:name]];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)saveUnrecognizedPage {
    NSString *html = [self.webView stringByEvaluatingJavaScriptFromString:@"document.documentElement.outerHTML"];
    if (html.length == 0) return;
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *pagePath = self.webView.request.URL.path.length > 1 ? self.webView.request.URL.path : @"/root";
    NSString *name = [[pagePath substringFromIndex:1] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSString *path = [documents stringByAppendingPathComponent:[NSString stringWithFormat:@"GitHubLegacy-login-%@.html", name]];
    NSString *contents = [NSString stringWithFormat:@"<!-- %@ -->\n%@", self.webView.request.URL.absoluteString ?: @"", html];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (void)presentStep:(GHWebLoginStep)step
              title:(NSString *)title
            message:(NSString *)message
              error:(NSString *)error
         firstField:(NSString *)firstPlaceholder
        secondField:(BOOL)showSecondField
            primary:(NSString *)primaryTitle
            methods:(NSArray *)methods {
    BOOL sameInput = firstPlaceholder != nil && self.lastInputStep == step;
    if (firstPlaceholder != nil || showSecondField) self.lastInputStep = step;
    self.step = step;
    if (step != GHWebLoginStepMobile) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
        self.digitsLabel.hidden = YES;
    }
    if (step != GHWebLoginStepRetry) self.retryURL = nil;
    self.webView.hidden = step != GHWebLoginStepPage;
    self.scrollView.hidden = step == GHWebLoginStepPage;

    self.titleLabel.text = title;
    self.messageLabel.text = message;
    self.errorLabel.text = error;
    self.errorLabel.hidden = error.length == 0;

    self.firstField.hidden = firstPlaceholder == nil;
    self.firstField.placeholder = firstPlaceholder;
    if (!sameInput) self.firstField.text = @"";
    self.secondField.hidden = !showSecondField;
    self.secondField.text = @"";
    self.firstField.returnKeyType = showSecondField ? UIReturnKeyNext : UIReturnKeyGo;

    self.primaryButton.hidden = primaryTitle == nil;
    [self.primaryButton setTitle:primaryTitle forState:UIControlStateNormal];

    if (step == GHWebLoginStepLoading) {
        [self.progressSpinner startAnimating];
        [self dismissKeyboard];
    } else {
        [self.progressSpinner stopAnimating];
    }

    for (UIButton *button in self.methodButtons) [button removeFromSuperview];
    [self.methodButtons removeAllObjects];
    self.methods = methods;
    for (NSUInteger i = 0; i < methods.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        button.titleLabel.font = [UIFont systemFontOfSize:16];
        button.tag = (NSInteger)i;
        [button setTitle:methods[i][@"title"] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(methodTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scrollView addSubview:button];
        [self.methodButtons addObject:button];
    }

    [self layoutContent];
    if (!self.firstField.hidden && self.firstField.text.length > 0 && showSecondField) {
        [self.secondField becomeFirstResponder];
    } else if (!self.firstField.hidden) {
        [self.firstField becomeFirstResponder];
    } else if (showSecondField) {
        [self.secondField becomeFirstResponder];
    }
}

#pragma mark - Page analysis

- (NSString *)methodKindForString:(NSString *)string {
    NSString *value = [string lowercaseString];
    if ([value rangeOfString:@"mobile"].location != NSNotFound) return @"mobile";
    if ([value rangeOfString:@"webauthn"].location != NSNotFound || [value rangeOfString:@"passkey"].location != NSNotFound
        || [value rangeOfString:@"security key"].location != NSNotFound) return @"webauthn";
    if ([value rangeOfString:@"recovery"].location != NSNotFound || [value rangeOfString:@"recover_prompt"].location != NSNotFound) return @"recovery";
    if ([value rangeOfString:@"sms"].location != NSNotFound || [value rangeOfString:@"text message"].location != NSNotFound) return @"sms";
    if ([value rangeOfString:@"email"].location != NSNotFound || [value rangeOfString:@"verified-device"].location != NSNotFound) return @"email";
    if ([value rangeOfString:@"two-factor/app"].location != NSNotFound || [value rangeOfString:@"authenticator"].location != NSNotFound
        || [value rangeOfString:@"app_otp"].location != NSNotFound || [value rangeOfString:@"totp"].location != NSNotFound) return @"app";
    return nil;
}

- (NSString *)titleForMethodKind:(NSString *)kind {
    if ([kind isEqualToString:@"app"]) return GHL(@"Код из приложения-аутентификатора");
    if ([kind isEqualToString:@"sms"]) return GHL(@"Код из SMS");
    if ([kind isEqualToString:@"email"]) return GHL(@"Код на почту");
    if ([kind isEqualToString:@"recovery"]) return GHL(@"Код восстановления");
    return nil;
}

- (BOOL)isChallengeString:(NSString *)string {
    for (NSString *marker in @[@"two-factor", @"sudo", @"otp", @"recovery", @"verified-device"]) {
        if ([string rangeOfString:marker].location != NSNotFound) return YES;
    }
    return NO;
}

- (NSArray *)methodsFromPage:(NSDictionary *)page excludingKind:(NSString *)currentKind {
    NSMutableArray *methods = [NSMutableArray array];
    NSMutableSet *kinds = [NSMutableSet set];
    if (currentKind) [kinds addObject:currentKind];

    NSString *emailInitiateURL = GHWebLoginString(page[@"emailInitiateURL"]);
    NSString *emailInitiateToken = GHWebLoginString(page[@"emailInitiateToken"]);
    for (NSDictionary *form in page[@"forms"]) {
        NSString *action = GHWebLoginString(form[@"action"]);
        NSDictionary *codeInput = [self inputOfForm:form type:@"text" visibleOnly:NO];
        NSDictionary *passwordInput = [self inputOfForm:form type:@"password" visibleOnly:NO];
        NSString *codeName = GHWebLoginString(codeInput[@"name"]);
        if (![self isChallengeString:action] && ![self isChallengeString:codeName]) continue;
        if (codeInput) {
            NSString *kind = [self methodKindForString:codeName] ?: [self methodKindForString:action] ?: @"app";
            NSString *title = [self titleForMethodKind:kind];
            if (title == nil || [kinds containsObject:kind]) continue;
            [kinds addObject:kind];
            NSMutableDictionary *method = [@{@"title": title, @"codeForm": form[@"index"], @"input": codeName,
                                             @"button": @([self submitButtonIndexOfForm:form preferring:nil]), @"kind": kind} mutableCopy];
            if ([kind isEqualToString:@"email"] && emailInitiateURL.length > 0 && emailInitiateToken.length > 0) {
                method[@"initiateURL"] = emailInitiateURL;
                method[@"initiateToken"] = emailInitiateToken;
            }
            [methods addObject:method];
        } else if (passwordInput) {
            if ([kinds containsObject:@"password"]) continue;
            [kinds addObject:@"password"];
            [methods addObject:@{@"title": GHL(@"Пароль"), @"passwordForm": form[@"index"], @"input": GHWebLoginString(passwordInput[@"name"]),
                                 @"button": @([self submitButtonIndexOfForm:form preferring:nil])}];
        }
    }

    for (NSDictionary *link in page[@"links"]) {
        NSString *href = GHWebLoginString(link[@"href"]);
        NSString *kind = [self methodKindForString:GHWebLoginString(link[@"text"])] ?: [self methodKindForString:href];
        NSString *title = [self titleForMethodKind:kind];
        if (title == nil || [kinds containsObject:kind]) continue;
        [kinds addObject:kind];
        [methods addObject:@{@"title": title, @"href": href}];
    }
    for (NSDictionary *form in page[@"forms"]) {
        NSString *action = GHWebLoginString(form[@"action"]);
        if ([form[@"inputs"] count] > 0 || ![self isChallengeString:action]) continue;
        for (NSDictionary *button in form[@"buttons"]) {
            NSString *kind = [self methodKindForString:[NSString stringWithFormat:@"%@ %@", action, GHWebLoginString(button[@"text"])]];
            NSString *title = [self titleForMethodKind:kind];
            if (title == nil || [kinds containsObject:kind]) continue;
            [kinds addObject:kind];
            [methods addObject:@{@"title": title, @"form": form[@"index"], @"button": button[@"index"]}];
        }
    }
    return methods;
}

- (NSDictionary *)formInPage:(NSDictionary *)page matching:(BOOL (^)(NSDictionary *form))predicate {
    for (NSDictionary *form in page[@"forms"]) {
        if (predicate(form)) return form;
    }
    return nil;
}

- (NSDictionary *)inputOfForm:(NSDictionary *)form type:(NSString *)type visibleOnly:(BOOL)visibleOnly {
    for (NSDictionary *input in form[@"inputs"]) {
        if (visibleOnly && ![input[@"visible"] boolValue]) continue;
        BOOL isPassword = [input[@"type"] isEqualToString:@"password"];
        if ([type isEqualToString:@"password"] == isPassword) return input;
    }
    return nil;
}

- (NSDictionary *)inputOfForm:(NSDictionary *)form type:(NSString *)type {
    return [self inputOfForm:form type:type visibleOnly:YES];
}

- (NSUInteger)visibleInputCountOfForm:(NSDictionary *)form {
    NSUInteger count = 0;
    for (NSDictionary *input in form[@"inputs"]) {
        if ([input[@"visible"] boolValue]) count++;
    }
    return count;
}

- (NSInteger)submitButtonIndexOfForm:(NSDictionary *)form preferring:(NSString *)preferredValue {
    NSArray *buttons = form[@"buttons"];
    for (NSDictionary *button in buttons) {
        if (preferredValue && [GHWebLoginString(button[@"value"]) isEqualToString:preferredValue]) return [button[@"index"] integerValue];
    }
    return buttons.count > 0 ? [buttons[0][@"index"] integerValue] : -1;
}

- (void)presentCodeStepForKind:(NSString *)kind error:(NSString *)error methods:(NSArray *)methods {
    NSString *message = GHL(@"Введите код подтверждения.");
    if ([kind isEqualToString:@"app"]) message = GHL(@"Введите шестизначный код из приложения-аутентификатора.");
    if ([kind isEqualToString:@"sms"]) message = GHL(@"Введите код из SMS.");
    if ([kind isEqualToString:@"email"]) message = GHL(@"Введите код из письма, которое отправил GitHub.");
    if ([kind isEqualToString:@"recovery"]) message = GHL(@"Введите один из кодов восстановления.");
    self.firstField.keyboardType = [kind isEqualToString:@"recovery"] ? UIKeyboardTypeASCIICapable : UIKeyboardTypeNumberPad;
    [self presentStep:GHWebLoginStepCode
                title:GHL(@"Двухфакторная проверка")
              message:message
                error:error
           firstField:GHL(@"Код")
          secondField:NO
              primary:GHL(@"Подтвердить")
              methods:methods];
}

- (void)analyzePage {
    NSString *json = [self.webView stringByEvaluatingJavaScriptFromString:kGHWebLoginAnalyzeScript];
    NSDictionary *page = json.length > 0 ? [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    if (![page isKindOfClass:[NSDictionary class]]) {
        [self showPage];
        return;
    }

    NSString *path = GHWebLoginString(page[@"path"]);
    NSArray *errors = [page[@"errors"] isKindOfClass:[NSArray class]] ? page[@"errors"] : @[];
    NSString *error = errors.count > 0 ? [errors componentsJoinedByString:@"\n"] : nil;
    BOOL deviceMode = self.deviceUserCode.length > 0;

    NSString *mobilePollURL = GHWebLoginString(page[@"mobilePollURL"]);
    NSString *mobileToken = GHWebLoginString(page[@"mobileToken"]);
    if (mobilePollURL.length > 0 && mobileToken.length > 0) {
        self.mobilePollURL = mobilePollURL;
        self.mobileToken = mobileToken;
        NSString *digits = GHWebLoginString(page[@"mobileDigits"]);
        [self presentStep:GHWebLoginStepMobile
                    title:GHL(@"Подтвердите вход в GitHub Mobile")
                  message:digits.length > 0 ? GHL(@"GitHub отправил запрос на вход в приложение GitHub Mobile. Введите там это число и нажмите «Approve»:")
                                            : GHL(@"GitHub отправил запрос на вход в приложение GitHub Mobile. Подтвердите его на телефоне.")
                    error:error
               firstField:nil
              secondField:NO
                  primary:nil
                  methods:[self methodsFromPage:page excludingKind:@"mobile"]];
        self.digitsLabel.text = digits;
        self.digitsLabel.hidden = digits.length == 0;
        [self.progressSpinner startAnimating];
        [self layoutContent];
        [self startMobilePolling];
        return;
    }

    NSDictionary *passwordForm = [self formInPage:page matching:^BOOL(NSDictionary *form) {
        return [self inputOfForm:form type:@"password"] != nil;
    }];
    if (passwordForm) {
        NSDictionary *loginInput = [self inputOfForm:passwordForm type:@"text"];
        self.formIndex = [passwordForm[@"index"] integerValue];
        self.buttonIndex = [self submitButtonIndexOfForm:passwordForm preferring:nil];
        self.firstFieldName = loginInput ? GHWebLoginString(loginInput[@"name"]) : nil;
        self.secondFieldName = GHWebLoginString([self inputOfForm:passwordForm type:@"password"][@"name"]);
        if (loginInput) {
            [self presentStep:GHWebLoginStepCredentials
                        title:GHL(@"Вход в GitHub")
                      message:GHL(@"Логин и пароль отправляются напрямую на github.com.")
                        error:error
                   firstField:GHL(@"Имя пользователя или email")
                  secondField:YES
                      primary:GHL(@"Войти")
                      methods:nil];
        } else {
            [self presentStep:GHWebLoginStepPassword
                        title:GHL(@"Подтвердите пароль")
                      message:GHL(@"GitHub просит ещё раз ввести пароль, чтобы подтвердить доступ.")
                        error:error
                   firstField:nil
                  secondField:YES
                      primary:GHL(@"Подтвердить")
                      methods:[self methodsFromPage:page excludingKind:nil]];
        }
        return;
    }

    if (deviceMode && [path hasPrefix:@"/login/device"]) {
        NSDictionary *codeForm = [self formInPage:page matching:^BOOL(NSDictionary *form) {
            return [GHWebLoginString(form[@"action"]) rangeOfString:@"/login/device"].location != NSNotFound && [self visibleInputCountOfForm:form] > 0;
        }];
        if (codeForm) {
            self.formIndex = [codeForm[@"index"] integerValue];
            self.buttonIndex = [self submitButtonIndexOfForm:codeForm preferring:nil];
            if (!self.submittedDeviceCode && error == nil) {
                [self submitDeviceCode];
                return;
            }
            [self presentStep:GHWebLoginStepRetry
                        title:GHL(@"Код устройства не принят")
                      message:[NSString stringWithFormat:GHL(@"Код %@ не подошёл. Вернитесь назад и получите новый код или попробуйте ещё раз."), self.deviceUserCode]
                        error:error
                   firstField:nil
                  secondField:NO
                      primary:GHL(@"Попробовать ещё раз")
                      methods:nil];
            return;
        }
    }

    NSDictionary *authorizeForm = [self formInPage:page matching:^BOOL(NSDictionary *form) {
        NSString *action = GHWebLoginString(form[@"action"]);
        if ([action rangeOfString:@"/login/"].location == NSNotFound) return NO;
        for (NSDictionary *button in form[@"buttons"]) {
            if ([GHWebLoginString(button[@"name"]) isEqualToString:@"authorize"]) return YES;
        }
        return NO;
    }];
    if (authorizeForm) {
        self.formIndex = [authorizeForm[@"index"] integerValue];
        self.buttonIndex = [self submitButtonIndexOfForm:authorizeForm preferring:@"1"];
        [self presentStep:GHWebLoginStepAuthorize
                    title:GHL(@"Разрешить доступ")
                  message:GHL(@"Приложение получит доступ к вашему аккаунту GitHub: репозиториям, задачам и подпискам.")
                    error:error
               firstField:nil
              secondField:NO
                  primary:GHL(@"Разрешить")
                  methods:nil];
        return;
    }

    NSString *currentKind = [self methodKindForString:path];
    NSDictionary *codeForm = [self formInPage:page matching:^BOOL(NSDictionary *form) {
        NSDictionary *input = [self inputOfForm:form type:@"text"];
        NSString *target = [NSString stringWithFormat:@"%@ %@ %@", GHWebLoginString(form[@"action"]), path, GHWebLoginString(input[@"name"])];
        if (input == nil || [target rangeOfString:@"search"].location != NSNotFound) return NO;
        return [self isChallengeString:target];
    }];
    if (codeForm) {
        self.formIndex = [codeForm[@"index"] integerValue];
        self.buttonIndex = [self submitButtonIndexOfForm:codeForm preferring:nil];
        self.firstFieldName = GHWebLoginString([self inputOfForm:codeForm type:@"text"][@"name"]);
        self.secondFieldName = nil;
        NSString *codeKind = currentKind
            ?: [self methodKindForString:[NSString stringWithFormat:@"%@ %@", GHWebLoginString(codeForm[@"action"]), self.firstFieldName]]
            ?: @"app";
        [self presentCodeStepForKind:codeKind error:error methods:[self methodsFromPage:page excludingKind:codeKind]];
        return;
    }

    NSArray *methods = [self methodsFromPage:page excludingKind:currentKind];
    if (methods.count == 0 && [path hasPrefix:@"/sessions/two-factor"]) {
        NSMutableArray *fallback = [NSMutableArray array];
        for (NSArray *entry in @[@[@"app", @"/sessions/two-factor/app"], @[@"recovery", @"/sessions/recovery"]]) {
            if ([entry[0] isEqualToString:currentKind]) continue;
            NSString *href = [[[NSURL URLWithString:entry[1] relativeToURL:[GHWebSession baseURL]] absoluteURL] absoluteString];
            [fallback addObject:@{@"title": [self titleForMethodKind:entry[0]], @"href": href}];
        }
        methods = fallback;
    }
    if (methods.count > 0) {
        [self saveUnrecognizedPage];
        [self presentStep:GHWebLoginStepChooseMethod
                    title:GHL(@"Двухфакторная проверка")
                  message:GHL(@"Подтверждение через GitHub Mobile здесь не работает. Выберите другой способ.")
                    error:error
               firstField:nil
              secondField:NO
                  primary:nil
                  methods:methods];
        return;
    }

    if (deviceMode && [path hasPrefix:@"/login/device"]) {
        NSString *text = [GHWebLoginString(page[@"text"]) lowercaseString];
        BOOL success = [path rangeOfString:@"success"].location != NSNotFound
            || [text rangeOfString:@"congratulations"].location != NSNotFound
            || [text rangeOfString:@"all set"].location != NSNotFound;
        if (success) {
            [self showLoadingWithMessage:GHL(@"Устройство подтверждено. Завершаем вход…")];
            return;
        }
        if ([self autoSubmitContinueFormInPage:page]) return;
    }
    if (self.autoSubmittedActions == nil) self.autoSubmittedActions = [NSMutableSet set];
    if (deviceMode && [GHWebSession isSignedIn] && ![path hasPrefix:@"/login/device"] && ![self.autoSubmittedActions containsObject:path]) {
        [self.autoSubmittedActions addObject:path];
        [self showLoadingWithMessage:GHL(@"Подтверждаем устройство…")];
        [self.webView loadRequest:[NSURLRequest requestWithURL:self.startURL]];
        return;
    }

    [self showPage];
}

- (BOOL)autoSubmitContinueFormInPage:(NSDictionary *)page {
    if (self.autoSubmittedActions == nil) self.autoSubmittedActions = [NSMutableSet set];
    for (NSDictionary *form in page[@"forms"]) {
        NSString *action = GHWebLoginString(form[@"action"]);
        if ([action rangeOfString:@"/login/device"].location == NSNotFound || [self visibleInputCountOfForm:form] > 0) continue;
        if ([self.autoSubmittedActions containsObject:action]) continue;
        for (NSDictionary *button in form[@"buttons"]) {
            if (![button[@"visible"] boolValue]) continue;
            NSString *label = [[NSString stringWithFormat:@"%@ %@", GHWebLoginString(button[@"text"]), GHWebLoginString(button[@"value"])] lowercaseString];
            if ([label rangeOfString:@"different"].location != NSNotFound || [label rangeOfString:@"another"].location != NSNotFound
                || [label rangeOfString:@"cancel"].location != NSNotFound || [label rangeOfString:@"sign out"].location != NSNotFound) continue;
            [self.autoSubmittedActions addObject:action];
            self.formIndex = [form[@"index"] integerValue];
            self.buttonIndex = [button[@"index"] integerValue];
            [self submitFormWithValues:nil loadingMessage:GHL(@"Подтверждаем устройство…")];
            return YES;
        }
    }
    return NO;
}

- (void)showPage {
    [self presentStep:GHWebLoginStepPage title:nil message:nil error:nil
           firstField:nil secondField:NO primary:nil methods:nil];
}

#pragma mark - Actions

- (void)submitFormWithValues:(NSDictionary *)values loadingMessage:(NSString *)message {
    NSString *script = [NSString stringWithFormat:kGHWebLoginSubmitScript,
                        (long)self.formIndex, GHWebLoginJSON(values ?: @{}) ?: @"{}", (long)self.buttonIndex];
    [self showLoadingWithMessage:message];
    if (![[self.webView stringByEvaluatingJavaScriptFromString:script] isEqualToString:@"ok"]) [self.webView reload];
}

- (void)submitDeviceCode {
    self.submittedDeviceCode = YES;
    NSString *script = [NSString stringWithFormat:kGHWebLoginDeviceCodeScript,
                        (long)self.formIndex, GHWebLoginJSON(@[self.deviceUserCode]), (long)self.buttonIndex];
    [self showLoadingWithMessage:GHL(@"Подтверждаем устройство…")];
    if (![[self.webView stringByEvaluatingJavaScriptFromString:script] isEqualToString:@"ok"]) [self showPage];
}

- (void)primaryTapped {
    NSString *first = [self.firstField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *second = self.secondField.text ?: @"";

    switch (self.step) {
        case GHWebLoginStepCredentials:
            if (first.length == 0 || second.length == 0) return;
            [self submitFormWithValues:@{self.firstFieldName ?: @"login": first, self.secondFieldName ?: @"password": second}
                        loadingMessage:GHL(@"Вход…")];
            break;
        case GHWebLoginStepPassword:
            if (second.length == 0) return;
            [self submitFormWithValues:@{self.secondFieldName ?: @"password": second} loadingMessage:GHL(@"Проверка пароля…")];
            break;
        case GHWebLoginStepCode:
            if (first.length == 0) return;
            [self submitFormWithValues:@{self.firstFieldName ?: @"otp": first} loadingMessage:GHL(@"Проверка кода…")];
            break;
        case GHWebLoginStepAuthorize:
            [self submitFormWithValues:nil loadingMessage:GHL(@"Подтверждаем устройство…")];
            break;
        case GHWebLoginStepRetry:
        {
            NSURL *url = self.retryURL ?: self.startURL ?: [GHWebSession signInURL];
            self.submittedDeviceCode = NO;
            [self showLoadingWithMessage:GHL(@"Подключение к github.com…")];
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
            break;
        default:
            break;
    }
}

- (void)methodTapped:(UIButton *)button {
    if (button.tag < 0 || button.tag >= (NSInteger)self.methods.count) return;
    NSDictionary *method = self.methods[button.tag];
    if (method[@"codeForm"] || method[@"passwordForm"]) {
        BOOL password = method[@"passwordForm"] != nil;
        self.formIndex = [(password ? method[@"passwordForm"] : method[@"codeForm"]) integerValue];
        self.buttonIndex = [method[@"button"] integerValue];
        NSMutableArray *others = [self.methods mutableCopy];
        [others removeObject:method];
        if (password) {
            self.firstFieldName = nil;
            self.secondFieldName = method[@"input"];
            [self presentStep:GHWebLoginStepPassword
                        title:GHL(@"Подтвердите пароль")
                      message:GHL(@"GitHub просит ещё раз ввести пароль, чтобы подтвердить доступ.")
                        error:nil
                   firstField:nil
                  secondField:YES
                      primary:GHL(@"Подтвердить")
                      methods:others];
        } else {
            self.firstFieldName = method[@"input"];
            self.secondFieldName = nil;
            NSString *error = method[@"initiateURL"] ? [self requestEmailCodeWithURL:method[@"initiateURL"] token:method[@"initiateToken"]] : nil;
            [self presentCodeStepForKind:method[@"kind"] error:error methods:others];
        }
        return;
    }
    NSString *href = method[@"href"];
    if (href.length > 0) {
        NSURL *url = [[NSURL URLWithString:href relativeToURL:[GHWebSession baseURL]] absoluteURL];
        [self showLoadingWithMessage:GHL(@"Загрузка…")];
        [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        return;
    }
    self.formIndex = [method[@"form"] integerValue];
    self.buttonIndex = [method[@"button"] integerValue];
    [self submitFormWithValues:nil loadingMessage:GHL(@"Загрузка…")];
}

- (void)startMobilePolling {
    [self.pollTimer invalidate];
    self.pollStartedAt = [NSDate timeIntervalSinceReferenceDate];
    [self.webView stringByEvaluatingJavaScriptFromString:@"window.__ghMobilePoll=null;window.__ghMobilePollBusy=0;"];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(mobilePollTick)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)failMobileWithMessage:(NSString *)message {
    [self presentStep:GHWebLoginStepRetry
                title:GHL(@"Вход через GitHub Mobile не подтверждён")
              message:message
                error:nil
           firstField:nil
          secondField:NO
              primary:GHL(@"Отправить запрос ещё раз")
              methods:nil];
    self.retryURL = [[NSURL URLWithString:@"/sessions/two-factor/mobile" relativeToURL:[GHWebSession baseURL]] absoluteURL];
}

- (void)mobilePollTick {
    if (self.step != GHWebLoginStepMobile) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
        return;
    }
    if ([NSDate timeIntervalSinceReferenceDate] - self.pollStartedAt > 300) {
        [self failMobileWithMessage:GHL(@"Время на подтверждение истекло.")];
        return;
    }

    NSString *script = [NSString stringWithFormat:
        @"(function(u,t){var r=window.__ghMobilePoll;window.__ghMobilePoll=null;"
         "if(!window.__ghMobilePollBusy){window.__ghMobilePollBusy=1;var x=new XMLHttpRequest();x.open('POST',u,true);"
         "x.setRequestHeader('Content-Type','application/x-www-form-urlencoded');"
         "x.setRequestHeader('X-Requested-With','XMLHttpRequest');"
         "x.setRequestHeader('GitHub-Verified-Fetch','true');"
         "x.setRequestHeader('Accept','application/json');"
         "x.onreadystatechange=function(){if(x.readyState==4){window.__ghMobilePollBusy=0;window.__ghMobilePoll=x.status+' '+x.responseText;}};"
         "x.send('authenticity_token='+encodeURIComponent(t));}"
         "return r||'';})(%@[0],%@[0])", GHWebLoginJSON(@[self.mobilePollURL]), GHWebLoginJSON(@[self.mobileToken])];
    NSString *result = [self.webView stringByEvaluatingJavaScriptFromString:script];
    if (result.length == 0) return;

    NSRange space = [result rangeOfString:@" "];
    NSInteger httpStatus = [(space.location != NSNotFound ? [result substringToIndex:space.location] : result) integerValue];
    NSString *body = space.location != NSNotFound ? [result substringFromIndex:space.location + 1] : @"";
    id json = body.length > 0 ? [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    NSString *status = [([json isKindOfClass:[NSDictionary class]] ? GHWebLoginString(json[@"status"]) : body) lowercaseString];

    if ([status rangeOfString:@"active"].location == NSNotFound) [self saveDiagnostic:result named:@"mobile-poll.txt"];

    if ([status rangeOfString:@"approved"].location != NSNotFound && [status rangeOfString:@"not_approved"].location == NSNotFound) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
        [self showLoadingWithMessage:GHL(@"Вход…")];
        NSString *redirect = nil;
        if ([json isKindOfClass:[NSDictionary class]]) {
            for (NSString *key in @[@"redirect_url", @"redirect_to", @"redirect", @"location", @"url"]) {
                if (GHWebLoginString(json[key]).length > 0) {
                    redirect = json[key];
                    break;
                }
            }
        }
        NSURL *next = nil;
        if (redirect.length > 0) {
            next = [[NSURL URLWithString:redirect relativeToURL:[GHWebSession baseURL]] absoluteURL];
        } else if ([GHWebSession isSignedIn]) {
            next = self.startURL ?: [GHWebSession baseURL];
        }
        if (next) {
            [self.webView loadRequest:[NSURLRequest requestWithURL:next]];
            return;
        }
        NSString *submitted = [self.webView stringByEvaluatingJavaScriptFromString:
            @"(function(){var f=document.getElementById('github-mobile-authenticate-form');if(!f)return '';f.submit();return 'ok';})()"];
        if (![submitted isEqualToString:@"ok"]) [self.webView reload];
        return;
    }
    if ([status rangeOfString:@"rejected"].location != NSNotFound) {
        [self failMobileWithMessage:GHL(@"Запрос на вход отклонён в GitHub Mobile.")];
        return;
    }
    if ([status rangeOfString:@"expired"].location != NSNotFound || [status rangeOfString:@"not_found"].location != NSNotFound
        || httpStatus >= 400) {
        [self failMobileWithMessage:GHL(@"Время на подтверждение истекло.")];
    }
}

- (NSString *)requestEmailCodeWithURL:(NSString *)url token:(NSString *)token {
    NSString *script = [NSString stringWithFormat:
        @"(function(u,t){try{var x=new XMLHttpRequest();x.open('POST',u,false);"
         "x.setRequestHeader('Content-Type','application/x-www-form-urlencoded');"
         "x.setRequestHeader('X-Requested-With','XMLHttpRequest');"
         "x.setRequestHeader('GitHub-Verified-Fetch','true');"
         "x.setRequestHeader('Accept','application/json');"
         "x.send('authenticity_token='+encodeURIComponent(t));return String(x.status);}catch(e){return '0';}"
         "})(%@[0],%@[0])", GHWebLoginJSON(@[url]), GHWebLoginJSON(@[token])];
    NSInteger status = [[self.webView stringByEvaluatingJavaScriptFromString:script] integerValue];
    if (status >= 200 && status < 300) return nil;
    return [NSString stringWithFormat:GHL(@"GitHub не отправил письмо с кодом (HTTP %ld)."), (long)status];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.firstField && !self.secondField.hidden) {
        [self.secondField becomeFirstResponder];
    } else {
        [self primaryTapped];
    }
    return NO;
}

#pragma mark - Completion

- (BOOL)finishIfSignedInAtURL:(NSURL *)url {
    if (self.finished || !self.finishesOnSignIn) return self.finished;
    if (![GHWebSession isSignedIn] || url == nil || [GHWebSession isSignInPageURL:url]) return NO;
    self.finished = YES;
    [self.webView stopLoading];
    [self.spinner stopAnimating];
    if (self.onSignedIn) self.onSignedIn();
    return YES;
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView
    shouldStartLoadWithRequest:(NSURLRequest *)request
                navigationType:(UIWebViewNavigationType)navigationType {
    if (self.finished) return NO;
    if (request.URL == nil || ![request.mainDocumentURL isEqual:request.URL]) return YES;
    return ![self finishIfSignedInAtURL:request.URL];
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    [self.spinner startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (webView.isLoading) return;
    [self.spinner stopAnimating];
    if ([self finishIfSignedInAtURL:webView.request.URL]) return;
    [self analyzePage];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (!webView.isLoading) [self.spinner stopAnimating];
    if (self.finished) return;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
    [self presentStep:GHWebLoginStepRetry
                title:GHL(@"Не удалось открыть github.com")
              message:error.localizedDescription
                error:nil
           firstField:nil
          secondField:NO
              primary:GHL(@"Попробовать ещё раз")
              methods:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ([self isMovingFromParentViewController] || [self isBeingDismissed] || self.navigationController.isBeingDismissed) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.pollTimer invalidate];
    self.webView.delegate = nil;
    [self.webView stopLoading];
}

@end
