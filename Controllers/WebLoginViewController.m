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
     "r.notices=[];var fn=document.querySelectorAll('.flash');"
     "for(var i=0;i<fn.length;i++){if(/flash-error/.test(fn[i].className))continue;var t=txt(fn[i]);"
     "if(t&&t.indexOf('{{')<0&&shown(fn[i])&&r.notices.indexOf(t)<0)r.notices.push(t);}"
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
     "if(/two-factor|recovery|verified-device|sudo|google/.test(h))r.links.push({href:as[i].href,text:txt(as[i])});}"
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

static NSString * const kGHWebLoginGoogleUserAgent =
    @"Mozilla/5.0 (iPhone; CPU iPhone OS 12_5_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1";

static const NSInteger kGHWebLoginRowIconTag = 1001;
static const NSInteger kGHWebLoginRowTitleTag = 1002;
static const NSInteger kGHWebLoginRowSubtitleTag = 1003;
static const NSInteger kGHWebLoginRowChevronTag = 1004;
static const NSInteger kGHWebLoginRowSeparatorTag = 1005;

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

static UIImage *GHWebLoginRoundedImage(UIColor *fill, UIColor *stroke) {
    CGFloat radius = 12;
    CGSize size = CGSizeMake(radius * 2 + 1, radius * 2 + 1);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5)
                                                    cornerRadius:radius];
    [fill setFill];
    [path fill];
    if (stroke) {
        [stroke setStroke];
        path.lineWidth = 1;
        [path stroke];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius, radius, radius, radius)];
}

static UIImage *GHWebLoginSolidImage(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static UIColor *GHWebLoginErrorColor(void) {
    return [UIColor colorWithRed:0.84 green:0.23 blue:0.23 alpha:1.0];
}

static UITextField *GHWebLoginMakeField(void) {
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleNone;
    field.font = [UIFont systemFontOfSize:17];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    UIImageView *leftIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
    leftIcon.contentMode = UIViewContentModeLeft;
    field.leftView = leftIcon;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}

static UIView *GHWebLoginMakeCard(void) {
    UIView *card = [[UIView alloc] init];
    card.layer.cornerRadius = 12;
    card.layer.borderWidth = 1;
    card.clipsToBounds = YES;
    return card;
}

@interface WebLoginViewController () <UIWebViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) NSArray *progressSegments;
@property (nonatomic, strong) UILabel *stepLabel;
@property (nonatomic, strong) UIView *iconBackground;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIView *digitsCard;
@property (nonatomic, strong) UILabel *digitsLabel;
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *errorBox;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIView *fieldsCard;
@property (nonatomic, strong) UIView *fieldsSeparator;
@property (nonatomic, strong) UITextField *firstField;
@property (nonatomic, strong) UITextField *secondField;
@property (nonatomic, strong) UIButton *primaryButton;
@property (nonatomic, strong) UIButton *secondaryButton;
@property (nonatomic, strong) UILabel *sectionLabel;
@property (nonatomic, strong) UIView *listCard;
@property (nonatomic, strong) NSMutableArray *listRows;
@property (nonatomic, strong) UILabel *footerLabel;
@property (nonatomic, assign) BOOL keyboardVisible;
@property (nonatomic, assign) NSInteger phase;
@property (nonatomic, copy) NSString *codeKind;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSTimeInterval pollStartedAt;
@property (nonatomic, copy) NSString *mobilePollURL;
@property (nonatomic, copy) NSString *mobileToken;
@property (nonatomic, strong) NSURL *retryURL;
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
@property (nonatomic, assign) BOOL startedGoogle;
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

    self.contentView = [[UIView alloc] init];
    [self.scrollView addSubview:self.contentView];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.scrollView addGestureRecognizer:tap];

    NSMutableArray *segments = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; i++) {
        UIView *segment = [[UIView alloc] init];
        segment.layer.cornerRadius = 2;
        [self.contentView addSubview:segment];
        [segments addObject:segment];
    }
    self.progressSegments = segments;

    self.stepLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:12]);
    [self.contentView addSubview:self.stepLabel];

    self.iconBackground = [[UIView alloc] init];
    self.iconBackground.layer.cornerRadius = 40;
    [self.contentView addSubview:self.iconBackground];

    self.iconView = [[UIImageView alloc] init];
    self.iconView.contentMode = UIViewContentModeCenter;
    [self.contentView addSubview:self.iconView];

    self.titleLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:24]);
    [self.contentView addSubview:self.titleLabel];

    self.messageLabel = GHWebLoginMakeLabel([UIFont systemFontOfSize:15]);
    [self.contentView addSubview:self.messageLabel];

    self.digitsCard = GHWebLoginMakeCard();
    [self.contentView addSubview:self.digitsCard];

    UIFont *digitsFont = [UIFont fontWithName:@"Menlo-Bold" size:60] ?: [UIFont boldSystemFontOfSize:60];
    self.digitsLabel = GHWebLoginMakeLabel(digitsFont);
    [self.digitsCard addSubview:self.digitsLabel];

    self.progressSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.progressSpinner.hidesWhenStopped = YES;
    [self.contentView addSubview:self.progressSpinner];

    self.statusLabel = GHWebLoginMakeLabel([UIFont systemFontOfSize:14]);
    [self.contentView addSubview:self.statusLabel];

    self.errorBox = GHWebLoginMakeCard();
    [self.contentView addSubview:self.errorBox];

    self.errorLabel = GHWebLoginMakeLabel([UIFont systemFontOfSize:14]);
    self.errorLabel.textAlignment = NSTextAlignmentLeft;
    [self.errorBox addSubview:self.errorLabel];

    self.fieldsCard = GHWebLoginMakeCard();
    [self.contentView addSubview:self.fieldsCard];

    self.fieldsSeparator = [[UIView alloc] init];
    [self.fieldsCard addSubview:self.fieldsSeparator];

    self.firstField = GHWebLoginMakeField();
    self.firstField.delegate = self;
    [self.fieldsCard addSubview:self.firstField];

    self.secondField = GHWebLoginMakeField();
    self.secondField.delegate = self;
    self.secondField.secureTextEntry = YES;
    self.secondField.placeholder = GHL(@"Пароль");
    self.secondField.returnKeyType = UIReturnKeyGo;
    self.secondField.clearButtonMode = UITextFieldViewModeNever;
    UIButton *revealButton = [UIButton buttonWithType:UIButtonTypeCustom];
    revealButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    revealButton.frame = CGRectMake(0, 0, 84, 40);
    revealButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [revealButton setTitle:GHL(@"Показать") forState:UIControlStateNormal];
    [revealButton addTarget:self action:@selector(togglePasswordVisibility:) forControlEvents:UIControlEventTouchUpInside];
    self.secondField.rightView = revealButton;
    self.secondField.rightViewMode = UITextFieldViewModeAlways;
    [self.fieldsCard addSubview:self.secondField];

    self.primaryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.primaryButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.primaryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.primaryButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.7] forState:UIControlStateHighlighted];
    [self.primaryButton addTarget:self action:@selector(primaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.primaryButton];

    self.secondaryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.secondaryButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.secondaryButton addTarget:self action:@selector(secondaryTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.secondaryButton];

    self.sectionLabel = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:12]);
    self.sectionLabel.textAlignment = NSTextAlignmentLeft;
    [self.contentView addSubview:self.sectionLabel];

    self.listCard = GHWebLoginMakeCard();
    [self.contentView addSubview:self.listCard];
    self.listRows = [NSMutableArray array];

    self.footerLabel = GHWebLoginMakeLabel([UIFont systemFontOfSize:12]);
    [self.contentView addSubview:self.footerLabel];

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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillShow:)
                                                  name:UIKeyboardWillShowNotification
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(keyboardWillHide:)
                                                  name:UIKeyboardWillHideNotification
                                                object:nil];
    [self applyTheme];
    [self showLoadingWithMessage:GHL(@"Подключение к github.com…")];
    [self.webView loadRequest:[NSURLRequest requestWithURL:self.startURL ?: [GHWebSession signInURL]]];
}

#pragma mark - Appearance

- (NSInteger)phaseCount {
    return self.deviceUserCode.length > 0 ? 3 : 2;
}

- (UIColor *)accentColor {
    return self.step == GHWebLoginStepRetry ? GHWebLoginErrorColor() : GHTintColor();
}

- (UIImage *)iconForKind:(NSString *)kind color:(UIColor *)color size:(CGFloat)size {
    if ([kind isEqualToString:@"sms"]) return [GHIconRenderer commentIconWithColor:color size:size];
    if ([kind isEqualToString:@"email"]) return [GHIconRenderer mailIconWithColor:color size:size];
    if ([kind isEqualToString:@"recovery"] || [kind isEqualToString:@"password"]) return [GHIconRenderer keyIconWithColor:color size:size];
    if ([kind isEqualToString:@"repo"]) return [GHIconRenderer repoIconWithColor:color size:size];
    if ([kind isEqualToString:@"person"]) return [GHIconRenderer personIconWithColor:color size:size];
    return [GHIconRenderer devicesIconWithColor:color size:size];
}

- (UIImage *)stepIcon {
    UIColor *color = [self accentColor];
    switch (self.step) {
        case GHWebLoginStepPassword:
        case GHWebLoginStepChooseMethod:
            return [GHIconRenderer keyIconWithColor:color size:36];
        case GHWebLoginStepCode:
            return [self iconForKind:self.codeKind color:color size:36];
        case GHWebLoginStepMobile:
            return [GHIconRenderer devicesIconWithColor:color size:36];
        case GHWebLoginStepAuthorize:
            return [GHIconRenderer linkIconWithColor:color size:36];
        case GHWebLoginStepRetry:
            return [GHIconRenderer infoIconWithColor:color size:36];
        default:
            return self.phase >= 3 ? [GHIconRenderer linkIconWithColor:color size:36]
                 : self.phase == 2 ? [GHIconRenderer keyIconWithColor:color size:36]
                                   : [GHIconRenderer personIconWithColor:color size:36];
    }
}

- (void)applyTheme {
    UIColor *accent = [self accentColor];
    self.view.backgroundColor = GHBackgroundColor();
    self.scrollView.backgroundColor = GHBackgroundColor();
    for (NSUInteger i = 0; i < self.progressSegments.count; i++) {
        BOOL active = (NSInteger)i < self.phase;
        [self.progressSegments[i] setBackgroundColor:active ? GHTintColor() : GHSeparatorColor()];
    }
    self.stepLabel.textColor = GHTintColor();
    self.iconBackground.backgroundColor = [accent colorWithAlphaComponent:0.14];
    self.iconView.image = [self stepIcon];
    self.titleLabel.textColor = GHPrimaryTextColor();
    self.messageLabel.textColor = GHSecondaryTextColor();
    self.digitsCard.backgroundColor = [GHTintColor() colorWithAlphaComponent:0.1];
    self.digitsCard.layer.borderColor = [GHTintColor() colorWithAlphaComponent:0.35].CGColor;
    self.digitsLabel.textColor = GHTintColor();
    self.statusLabel.textColor = GHSecondaryTextColor();
    self.errorLabel.textColor = GHWebLoginErrorColor();
    self.errorBox.backgroundColor = [GHWebLoginErrorColor() colorWithAlphaComponent:0.1];
    self.errorBox.layer.borderColor = [GHWebLoginErrorColor() colorWithAlphaComponent:0.4].CGColor;
    self.fieldsCard.backgroundColor = GHCellBackgroundColor();
    self.fieldsCard.layer.borderColor = GHSeparatorColor().CGColor;
    self.fieldsSeparator.backgroundColor = GHSeparatorColor();
    self.firstField.textColor = GHPrimaryTextColor();
    self.secondField.textColor = GHPrimaryTextColor();
    [(UIImageView *)self.firstField.leftView setImage:[self iconForKind:self.step == GHWebLoginStepCode ? self.codeKind : @"person"
                                                                  color:GHSecondaryTextColor() size:18]];
    [(UIImageView *)self.secondField.leftView setImage:[GHIconRenderer keyIconWithColor:GHSecondaryTextColor() size:18]];
    [(UIButton *)self.secondField.rightView setTitleColor:GHTintColor() forState:UIControlStateNormal];
    [self.primaryButton setBackgroundImage:GHWebLoginRoundedImage(accent, nil) forState:UIControlStateNormal];
    [self.primaryButton setBackgroundImage:GHWebLoginRoundedImage([accent colorWithAlphaComponent:0.75], nil)
                                  forState:UIControlStateHighlighted];
    [self.secondaryButton setTitleColor:GHTintColor() forState:UIControlStateNormal];
    [self.secondaryButton setTitleColor:[GHTintColor() colorWithAlphaComponent:0.5] forState:UIControlStateHighlighted];
    self.sectionLabel.textColor = GHSecondaryTextColor();
    self.listCard.backgroundColor = GHCellBackgroundColor();
    self.listCard.layer.borderColor = GHSeparatorColor().CGColor;
    for (UIButton *row in self.listRows) [self styleRow:row];
    self.footerLabel.textColor = GHSecondaryTextColor();
    self.progressSpinner.activityIndicatorViewStyle = GHSpinnerStyle();
}

- (UIButton *)makeRowWithItem:(NSDictionary *)item index:(NSUInteger)index tappable:(BOOL)tappable {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.tag = (NSInteger)index;
    row.userInteractionEnabled = tappable;
    if (tappable) [row addTarget:self action:@selector(methodTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *icon = [[UIImageView alloc] init];
    icon.tag = kGHWebLoginRowIconTag;
    icon.contentMode = UIViewContentModeCenter;
    [row addSubview:icon];

    UILabel *title = GHWebLoginMakeLabel([UIFont boldSystemFontOfSize:16]);
    title.tag = kGHWebLoginRowTitleTag;
    title.textAlignment = NSTextAlignmentLeft;
    title.numberOfLines = 1;
    title.adjustsFontSizeToFitWidth = YES;
    title.text = item[@"title"];
    [row addSubview:title];

    UILabel *subtitle = GHWebLoginMakeLabel([UIFont systemFontOfSize:13]);
    subtitle.tag = kGHWebLoginRowSubtitleTag;
    subtitle.textAlignment = NSTextAlignmentLeft;
    subtitle.text = item[@"subtitle"];
    [row addSubview:subtitle];

    UIImageView *chevron = [[UIImageView alloc] init];
    chevron.tag = kGHWebLoginRowChevronTag;
    chevron.contentMode = UIViewContentModeCenter;
    chevron.hidden = !tappable;
    [row addSubview:chevron];

    UIView *separator = [[UIView alloc] init];
    separator.tag = kGHWebLoginRowSeparatorTag;
    separator.hidden = index == 0;
    [row addSubview:separator];

    [self styleRow:row];
    return row;
}

- (void)styleRow:(UIButton *)row {
    NSDictionary *item = row.tag < (NSInteger)self.rowItems.count ? self.rowItems[row.tag] : nil;
    [(UIImageView *)[row viewWithTag:kGHWebLoginRowIconTag] setImage:[self iconForKind:item[@"kind"] color:GHTintColor() size:22]];
    [(UILabel *)[row viewWithTag:kGHWebLoginRowTitleTag] setTextColor:GHPrimaryTextColor()];
    [(UILabel *)[row viewWithTag:kGHWebLoginRowSubtitleTag] setTextColor:GHSecondaryTextColor()];
    [(UIImageView *)[row viewWithTag:kGHWebLoginRowChevronTag] setImage:[GHIconRenderer disclosureChevronWithColor:GHSecondaryTextColor()
                                                                                                             size:CGSizeMake(9, 14)]];
    [[row viewWithTag:kGHWebLoginRowSeparatorTag] setBackgroundColor:GHSeparatorColor()];
    [row setBackgroundImage:GHWebLoginSolidImage([GHTintColor() colorWithAlphaComponent:0.12]) forState:UIControlStateHighlighted];
}

- (NSArray *)rowItems {
    return self.step == GHWebLoginStepAuthorize ? [self permissionItems] : self.methods;
}

- (NSArray *)permissionItems {
    return @[@{@"kind": @"repo", @"title": GHL(@"Репозитории"), @"subtitle": GHL(@"Чтение и запись, включая приватные")},
             @{@"kind": @"person", @"title": GHL(@"Подписки на пользователей"), @"subtitle": GHL(@"Подписываться на людей и отписываться")}];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

- (void)cancelTapped {
    [self.webView stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)secondaryTapped {
    [self.webView stopLoading];
    NSArray *stack = self.navigationController.viewControllers;
    if (self.presentingViewController && stack.count > 0 && stack[0] == self) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)togglePasswordVisibility:(UIButton *)button {
    BOOL wasEditing = self.secondField.isFirstResponder;
    if (wasEditing) [self.secondField resignFirstResponder];
    self.secondField.secureTextEntry = !self.secondField.secureTextEntry;
    [button setTitle:self.secondField.secureTextEntry ? GHL(@"Показать") : GHL(@"Скрыть") forState:UIControlStateNormal];
    if (wasEditing) [self.secondField becomeFirstResponder];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    CGRect keyboardFrame = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrame));
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = overlap;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    self.keyboardVisible = YES;
    [self layoutContent];
    [self scrollInputsIntoView];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    UIEdgeInsets insets = self.scrollView.contentInset;
    insets.bottom = 0;
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
    self.keyboardVisible = NO;
    [UIView animateWithDuration:0.25 animations:^{
        [self layoutContent];
    }];
}

- (void)scrollInputsIntoView {
    if (self.fieldsCard.hidden) return;
    CGRect target = self.fieldsCard.frame;
    if (!self.primaryButton.hidden) target = CGRectUnion(target, self.primaryButton.frame);
    target = [self.contentView convertRect:target toView:self.scrollView];
    [self.scrollView scrollRectToVisible:CGRectInset(target, 0, -12) animated:YES];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self scrollInputsIntoView];
}

#pragma mark - Layout

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
    if (label.hidden || label.text.length == 0) return 0;
    return ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (void)layoutContent {
    CGFloat width = MIN(self.view.bounds.size.width - 32, 420);
    CGFloat left = floor((self.view.bounds.size.width - width) / 2.0);
    CGFloat y = 20;

    NSInteger phaseCount = [self phaseCount];
    BOOL showProgress = self.phase > 0;
    CGFloat segmentGap = 6;
    CGFloat segmentWidth = floor((width - segmentGap * (phaseCount - 1)) / phaseCount);
    for (NSUInteger i = 0; i < self.progressSegments.count; i++) {
        UIView *segment = self.progressSegments[i];
        segment.hidden = !showProgress || (NSInteger)i >= phaseCount;
        segment.frame = CGRectMake(left + i * (segmentWidth + segmentGap), y, segmentWidth, 4);
    }
    if (showProgress) {
        y += 4 + 10;
        self.stepLabel.text = [[NSString stringWithFormat:GHL(@"Шаг %ld из %ld"), (long)MIN(self.phase, phaseCount), (long)phaseCount] uppercaseString];
        self.stepLabel.hidden = NO;
        self.stepLabel.frame = CGRectMake(left, y, width, 16);
        y += 16 + 22;
    } else {
        self.stepLabel.hidden = YES;
        y += 16;
    }

    self.iconBackground.frame = CGRectMake(left + floor((width - 80) / 2.0), y, 80, 80);
    self.iconView.frame = self.iconBackground.frame;
    y += 80 + 18;

    CGFloat titleHeight = [self heightForLabel:self.titleLabel width:width];
    self.titleLabel.frame = CGRectMake(left, y, width, titleHeight);
    y += titleHeight + (titleHeight > 0 ? 8 : 0);

    CGFloat messageHeight = [self heightForLabel:self.messageLabel width:width - 16];
    self.messageLabel.frame = CGRectMake(left + 8, y, width - 16, messageHeight);
    y += messageHeight + (messageHeight > 0 ? 22 : 0);

    if (!self.digitsCard.hidden) {
        CGFloat cardWidth = MIN(width, 220);
        self.digitsCard.frame = CGRectMake(left + floor((width - cardWidth) / 2.0), y, cardWidth, 100);
        self.digitsLabel.frame = self.digitsCard.bounds;
        y += 100 + 18;
    }

    if (self.progressSpinner.isAnimating) {
        CGFloat statusWidth = MIN(ceil([self.statusLabel sizeThatFits:CGSizeMake(width - 40, CGFLOAT_MAX)].width), width - 40);
        CGFloat statusHeight = MAX([self heightForLabel:self.statusLabel width:statusWidth], 20);
        if (self.step == GHWebLoginStepLoading) {
            self.progressSpinner.frame = CGRectMake(left + floor((width - 20) / 2.0), y, 20, 20);
            y += 20 + 12;
            self.statusLabel.frame = CGRectMake(left, y, width, statusHeight);
        } else {
            CGFloat rowWidth = 20 + 8 + statusWidth;
            CGFloat rowLeft = left + floor((width - rowWidth) / 2.0);
            self.progressSpinner.frame = CGRectMake(rowLeft, y + floor((statusHeight - 20) / 2.0), 20, 20);
            self.statusLabel.frame = CGRectMake(rowLeft + 28, y, statusWidth, statusHeight);
            self.statusLabel.textAlignment = NSTextAlignmentLeft;
        }
        if (self.step == GHWebLoginStepLoading) self.statusLabel.textAlignment = NSTextAlignmentCenter;
        self.statusLabel.hidden = self.statusLabel.text.length == 0;
        y += statusHeight + 22;
    } else {
        self.statusLabel.hidden = YES;
    }

    self.errorBox.hidden = self.errorLabel.text.length == 0;
    if (!self.errorBox.hidden) {
        CGFloat errorHeight = [self heightForLabel:self.errorLabel width:width - 28];
        self.errorBox.frame = CGRectMake(left, y, width, errorHeight + 24);
        self.errorLabel.frame = CGRectMake(14, 12, width - 28, errorHeight);
        y += errorHeight + 24 + 16;
    }

    NSUInteger fieldCount = (self.firstField.hidden ? 0 : 1) + (self.secondField.hidden ? 0 : 1);
    self.fieldsCard.hidden = fieldCount == 0;
    if (fieldCount > 0) {
        CGFloat fieldHeight = self.step == GHWebLoginStepCode ? 58 : 50;
        CGFloat fieldY = 0;
        if (!self.firstField.hidden) {
            self.firstField.frame = CGRectMake(14, fieldY, width - 28, fieldHeight);
            fieldY += fieldHeight;
        }
        self.fieldsSeparator.hidden = fieldCount < 2;
        self.fieldsSeparator.frame = CGRectMake(46, fieldY, width - 46, 1);
        if (!self.secondField.hidden) {
            fieldY += fieldCount > 1 ? 1 : 0;
            self.secondField.frame = CGRectMake(14, fieldY, width - 28, fieldHeight);
            fieldY += fieldHeight;
        }
        self.fieldsCard.frame = CGRectMake(left, y, width, fieldY);
        y += fieldY + 18;
    }

    if (!self.primaryButton.hidden) {
        self.primaryButton.frame = CGRectMake(left, y, width, 50);
        y += 50 + 8;
    }
    if (!self.secondaryButton.hidden) {
        self.secondaryButton.frame = CGRectMake(left, y, width, 40);
        y += 40;
    }
    if (!self.primaryButton.hidden || !self.secondaryButton.hidden) y += 18;

    self.sectionLabel.hidden = self.sectionLabel.text.length == 0 || self.listRows.count == 0;
    if (!self.sectionLabel.hidden) {
        self.sectionLabel.frame = CGRectMake(left + 14, y, width - 28, 16);
        y += 16 + 8;
    }

    self.listCard.hidden = self.listRows.count == 0;
    if (!self.listCard.hidden) {
        CGFloat rowY = 0;
        for (UIButton *row in self.listRows) {
            UILabel *subtitle = (UILabel *)[row viewWithTag:kGHWebLoginRowSubtitleTag];
            CGFloat textWidth = width - 52 - 34;
            CGFloat subtitleHeight = [self heightForLabel:subtitle width:textWidth];
            CGFloat rowHeight = MAX(54, 12 + 20 + (subtitleHeight > 0 ? 2 + subtitleHeight : 0) + 12);
            row.frame = CGRectMake(0, rowY, width, rowHeight);
            [row viewWithTag:kGHWebLoginRowIconTag].frame = CGRectMake(14, 0, 26, rowHeight);
            CGFloat textTop = floor((rowHeight - 20 - (subtitleHeight > 0 ? 2 + subtitleHeight : 0)) / 2.0);
            [row viewWithTag:kGHWebLoginRowTitleTag].frame = CGRectMake(52, textTop, textWidth, 20);
            subtitle.frame = CGRectMake(52, textTop + 22, textWidth, subtitleHeight);
            [row viewWithTag:kGHWebLoginRowChevronTag].frame = CGRectMake(width - 30, 0, 16, rowHeight);
            [row viewWithTag:kGHWebLoginRowSeparatorTag].frame = CGRectMake(52, 0, width - 52, 1);
            rowY += rowHeight;
        }
        self.listCard.frame = CGRectMake(left, y, width, rowY);
        y += rowY + 18;
    }

    CGFloat footerHeight = [self heightForLabel:self.footerLabel width:width - 20];
    self.footerLabel.frame = CGRectMake(left + 10, y, width - 20, footerHeight);
    y += footerHeight + (footerHeight > 0 ? 12 : 0);

    CGFloat contentHeight = y + 12;
    CGFloat visibleHeight = self.scrollView.bounds.size.height;
    CGFloat top = self.keyboardVisible ? 0 : MAX(0, floor((visibleHeight - contentHeight) / 2.0) - 20);
    self.contentView.frame = CGRectMake(0, top, self.view.bounds.size.width, contentHeight);
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, top + contentHeight);
}

#pragma mark - Steps

- (void)showLoadingWithMessage:(NSString *)message {
    [self presentStep:GHWebLoginStepLoading title:nil message:nil error:nil
           firstField:nil secondField:NO primary:nil methods:nil];
    self.statusLabel.text = message;
    [self layoutContent];
}

- (NSInteger)phaseForStep:(GHWebLoginStep)step {
    switch (step) {
        case GHWebLoginStepCredentials:
            return 1;
        case GHWebLoginStepPassword:
        case GHWebLoginStepCode:
        case GHWebLoginStepChooseMethod:
        case GHWebLoginStepMobile:
            return 2;
        case GHWebLoginStepAuthorize:
            return 3;
        default:
            return self.phase;
    }
}

- (NSString *)footerForStep:(GHWebLoginStep)step {
    switch (step) {
        case GHWebLoginStepCredentials:
            return GHL(@"Пароль передаётся только на github.com и не сохраняется в приложении.");
        case GHWebLoginStepAuthorize:
            return GHL(@"Доступ можно отозвать на github.com в Settings → Applications.");
        case GHWebLoginStepMobile:
            return GHL(@"Число нужно, чтобы убедиться, что входите именно вы.");
        default:
            return nil;
    }
}

- (void)presentStep:(GHWebLoginStep)step
              title:(NSString *)title
            message:(NSString *)message
              error:(NSString *)error
         firstField:(NSString *)firstPlaceholder
        secondField:(BOOL)showSecondField
            primary:(NSString *)primaryTitle
            methods:(NSArray *)methods {
    BOOL stepChanged = self.step != step;
    BOOL sameInput = firstPlaceholder != nil && self.lastInputStep == step;
    if (firstPlaceholder != nil || showSecondField) self.lastInputStep = step;
    self.step = step;
    self.phase = [self phaseForStep:step];
    if (step != GHWebLoginStepMobile) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
    }
    if (step != GHWebLoginStepRetry) self.retryURL = nil;
    self.webView.hidden = step != GHWebLoginStepPage;
    self.scrollView.hidden = step == GHWebLoginStepPage;

    if (stepChanged) {
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionFade;
        transition.duration = 0.2;
        [self.contentView.layer addAnimation:transition forKey:@"step"];
    }

    self.titleLabel.text = title;
    self.messageLabel.text = message;
    self.errorLabel.text = error;
    self.digitsCard.hidden = YES;
    self.statusLabel.text = nil;

    BOOL codeStep = step == GHWebLoginStepCode;
    self.firstField.hidden = firstPlaceholder == nil;
    self.firstField.placeholder = firstPlaceholder;
    self.firstField.font = codeStep ? ([UIFont fontWithName:@"Menlo-Bold" size:22] ?: [UIFont boldSystemFontOfSize:22])
                                    : [UIFont systemFontOfSize:17];
    self.firstField.textAlignment = codeStep ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    self.firstField.leftViewMode = codeStep ? UITextFieldViewModeNever : UITextFieldViewModeAlways;
    self.firstField.clearButtonMode = codeStep ? UITextFieldViewModeNever : UITextFieldViewModeWhileEditing;
    if (!codeStep) self.firstField.keyboardType = UIKeyboardTypeEmailAddress;
    if (!sameInput) self.firstField.text = @"";
    self.secondField.hidden = !showSecondField;
    self.secondField.text = @"";
    self.secondField.secureTextEntry = YES;
    [(UIButton *)self.secondField.rightView setTitle:GHL(@"Показать") forState:UIControlStateNormal];
    self.firstField.returnKeyType = showSecondField ? UIReturnKeyNext : UIReturnKeyGo;

    self.primaryButton.hidden = primaryTitle == nil;
    [self.primaryButton setTitle:primaryTitle forState:UIControlStateNormal];
    self.secondaryButton.hidden = step != GHWebLoginStepAuthorize;
    [self.secondaryButton setTitle:GHL(@"Отмена") forState:UIControlStateNormal];

    if (step == GHWebLoginStepLoading || step == GHWebLoginStepMobile) {
        [self.progressSpinner startAnimating];
    } else {
        [self.progressSpinner stopAnimating];
    }
    if (step == GHWebLoginStepLoading) [self dismissKeyboard];

    self.methods = methods;
    for (UIButton *row in self.listRows) [row removeFromSuperview];
    [self.listRows removeAllObjects];
    BOOL tappable = step != GHWebLoginStepAuthorize;
    NSArray *items = [self rowItems];
    for (NSUInteger i = 0; i < items.count; i++) {
        UIButton *row = [self makeRowWithItem:items[i] index:i tappable:tappable];
        [self.listCard addSubview:row];
        [self.listRows addObject:row];
    }
    if (step == GHWebLoginStepAuthorize) {
        self.sectionLabel.text = [GHL(@"Приложение сможет") uppercaseString];
    } else if (step == GHWebLoginStepChooseMethod) {
        self.sectionLabel.text = nil;
    } else {
        self.sectionLabel.text = [GHL(@"Другие способы") uppercaseString];
    }
    self.footerLabel.text = [self footerForStep:step];

    [self applyTheme];
    [self layoutContent];
    if (!self.firstField.hidden && self.firstField.text.length > 0 && showSecondField) {
        [self.secondField becomeFirstResponder];
    } else if (!self.firstField.hidden) {
        [self.firstField becomeFirstResponder];
    } else if (showSecondField) {
        [self.secondField becomeFirstResponder];
    } else {
        [self dismissKeyboard];
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
    if ([kind isEqualToString:@"app"]) return GHL(@"Приложение-аутентификатор");
    if ([kind isEqualToString:@"sms"]) return GHL(@"Код из SMS");
    if ([kind isEqualToString:@"email"]) return GHL(@"Код на почту");
    if ([kind isEqualToString:@"recovery"]) return GHL(@"Код восстановления");
    if ([kind isEqualToString:@"password"]) return GHL(@"Пароль");
    return nil;
}

- (NSString *)subtitleForMethodKind:(NSString *)kind {
    if ([kind isEqualToString:@"app"]) return GHL(@"Шестизначный код из Google Authenticator, 1Password и т. п.");
    if ([kind isEqualToString:@"sms"]) return GHL(@"Код придёт на привязанный номер телефона");
    if ([kind isEqualToString:@"email"]) return GHL(@"GitHub отправит код на почту аккаунта");
    if ([kind isEqualToString:@"recovery"]) return GHL(@"Одноразовый код из сохранённого списка");
    if ([kind isEqualToString:@"password"]) return GHL(@"Пароль от аккаунта GitHub");
    return nil;
}

- (NSMutableDictionary *)methodWithKind:(NSString *)kind {
    NSMutableDictionary *method = [NSMutableDictionary dictionary];
    method[@"kind"] = kind;
    method[@"title"] = [self titleForMethodKind:kind];
    NSString *subtitle = [self subtitleForMethodKind:kind];
    if (subtitle) method[@"subtitle"] = subtitle;
    return method;
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
            if ([self titleForMethodKind:kind] == nil || [kinds containsObject:kind]) continue;
            [kinds addObject:kind];
            NSMutableDictionary *method = [self methodWithKind:kind];
            method[@"codeForm"] = form[@"index"];
            method[@"input"] = codeName;
            method[@"button"] = @([self submitButtonIndexOfForm:form preferring:nil]);
            if ([kind isEqualToString:@"email"] && emailInitiateURL.length > 0 && emailInitiateToken.length > 0) {
                method[@"initiateURL"] = emailInitiateURL;
                method[@"initiateToken"] = emailInitiateToken;
            }
            [methods addObject:method];
        } else if (passwordInput) {
            if ([kinds containsObject:@"password"]) continue;
            [kinds addObject:@"password"];
            NSMutableDictionary *method = [self methodWithKind:@"password"];
            method[@"passwordForm"] = form[@"index"];
            method[@"input"] = GHWebLoginString(passwordInput[@"name"]);
            method[@"button"] = @([self submitButtonIndexOfForm:form preferring:nil]);
            [methods addObject:method];
        }
    }

    for (NSDictionary *link in page[@"links"]) {
        NSString *href = GHWebLoginString(link[@"href"]);
        NSString *kind = [self methodKindForString:GHWebLoginString(link[@"text"])] ?: [self methodKindForString:href];
        if ([self titleForMethodKind:kind] == nil || [kinds containsObject:kind]) continue;
        [kinds addObject:kind];
        NSMutableDictionary *method = [self methodWithKind:kind];
        method[@"href"] = href;
        [methods addObject:method];
    }
    for (NSDictionary *form in page[@"forms"]) {
        NSString *action = GHWebLoginString(form[@"action"]);
        if ([form[@"inputs"] count] > 0 || ![self isChallengeString:action]) continue;
        for (NSDictionary *button in form[@"buttons"]) {
            NSString *kind = [self methodKindForString:[NSString stringWithFormat:@"%@ %@", action, GHWebLoginString(button[@"text"])]];
            if ([self titleForMethodKind:kind] == nil || [kinds containsObject:kind]) continue;
            [kinds addObject:kind];
            NSMutableDictionary *method = [self methodWithKind:kind];
            method[@"form"] = form[@"index"];
            method[@"button"] = button[@"index"];
            [methods addObject:method];
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
    NSString *placeholder = @"000000";
    if ([kind isEqualToString:@"app"]) message = GHL(@"Откройте приложение-аутентификатор и введите шестизначный код для GitHub.");
    if ([kind isEqualToString:@"sms"]) message = GHL(@"Введите код из SMS, которое отправил GitHub.");
    if ([kind isEqualToString:@"email"]) {
        message = GHL(@"Введите код из письма, которое отправил GitHub.");
        placeholder = @"00000000";
    }
    if ([kind isEqualToString:@"recovery"]) {
        message = GHL(@"Введите один из сохранённых кодов восстановления. Каждый код работает только один раз.");
        placeholder = @"xxxxx-xxxxx";
    }
    self.codeKind = kind;
    self.firstField.keyboardType = [kind isEqualToString:@"recovery"] ? UIKeyboardTypeASCIICapable : UIKeyboardTypeNumberPad;
    [self presentStep:GHWebLoginStepCode
                title:[self titleForMethodKind:kind] ?: GHL(@"Двухфакторная проверка")
              message:message
                error:error
           firstField:placeholder
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

    if (self.prefersGoogle && [self handleGoogleInPage:page]) return;

    NSString *mobilePollURL = GHWebLoginString(page[@"mobilePollURL"]);
    NSString *mobileToken = GHWebLoginString(page[@"mobileToken"]);
    if (mobilePollURL.length > 0 && mobileToken.length > 0) {
        self.mobilePollURL = mobilePollURL;
        self.mobileToken = mobileToken;
        NSString *digits = GHWebLoginString(page[@"mobileDigits"]);
        [self presentStep:GHWebLoginStepMobile
                    title:GHL(@"Подтвердите вход")
                  message:digits.length > 0 ? GHL(@"Откройте GitHub Mobile на телефоне, введите это число и нажмите «Approve».")
                                            : GHL(@"Откройте GitHub Mobile на телефоне и подтвердите запрос на вход.")
                    error:error
               firstField:nil
              secondField:NO
                  primary:nil
                  methods:[self methodsFromPage:page excludingKind:@"mobile"]];
        self.digitsLabel.text = digits;
        self.digitsCard.hidden = digits.length == 0;
        self.statusLabel.text = GHL(@"Ожидаем подтверждения…");
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
            NSArray *notices = [page[@"notices"] isKindOfClass:[NSArray class]] ? page[@"notices"] : @[];
            [self presentStep:GHWebLoginStepCredentials
                        title:GHL(@"Вход в GitHub")
                      message:GHL(@"Войдите в аккаунт, чтобы подключить его к приложению.")
                        error:error ?: (notices.count > 0 ? [notices componentsJoinedByString:@"\n"] : nil)
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
                      methods:[self methodsFromPage:page excludingKind:@"password"]];
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
                  message:GHL(@"Подтвердите, что это устройство можно подключить к вашему аккаунту GitHub.")
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
            NSMutableDictionary *method = [self methodWithKind:entry[0]];
            method[@"href"] = [[[NSURL URLWithString:entry[1] relativeToURL:[GHWebSession baseURL]] absoluteURL] absoluteString];
            [fallback addObject:method];
        }
        methods = fallback;
    }
    if (methods.count > 0) {
        [self presentStep:GHWebLoginStepChooseMethod
                    title:GHL(@"Подтвердите вход")
                  message:GHL(@"Выберите, как подтвердить, что это вы.")
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

- (BOOL)isGoogleURL:(NSURL *)url {
    NSString *host = [url.host lowercaseString];
    return [host isEqualToString:@"google.com"] || [host hasSuffix:@".google.com"]
        || [host isEqualToString:@"gstatic.com"] || [host hasSuffix:@".gstatic.com"];
}

- (BOOL)handleGoogleInPage:(NSDictionary *)page {
    NSString *host = [GHWebLoginString(page[@"host"]) lowercaseString];
    if (![host isEqualToString:@"github.com"]) {
        [self showPage];
        return YES;
    }

    BOOL loginPage = [self formInPage:page matching:^BOOL(NSDictionary *form) {
        return [self inputOfForm:form type:@"password"] != nil && [self inputOfForm:form type:@"text"] != nil;
    }] != nil;
    if (!loginPage) return NO;
    if (self.startedGoogle) {
        [self showPage];
        return YES;
    }

    for (NSDictionary *form in page[@"forms"]) {
        NSString *action = [GHWebLoginString(form[@"action"]) lowercaseString];
        for (NSDictionary *button in form[@"buttons"]) {
            NSString *text = [GHWebLoginString(button[@"text"]) lowercaseString];
            if ([action rangeOfString:@"google"].location == NSNotFound && [text rangeOfString:@"google"].location == NSNotFound) continue;
            self.startedGoogle = YES;
            self.formIndex = [form[@"index"] integerValue];
            self.buttonIndex = [button[@"index"] integerValue];
            [self submitFormWithValues:nil loadingMessage:GHL(@"Переход к Google…")];
            return YES;
        }
    }
    for (NSDictionary *link in page[@"links"]) {
        NSString *href = GHWebLoginString(link[@"href"]);
        if ([[href lowercaseString] rangeOfString:@"google"].location == NSNotFound) continue;
        self.startedGoogle = YES;
        [self showLoadingWithMessage:GHL(@"Переход к Google…")];
        [self.webView loadRequest:[NSURLRequest requestWithURL:[[NSURL URLWithString:href relativeToURL:[GHWebSession baseURL]] absoluteURL]]];
        return YES;
    }

    [self showPage];
    return YES;
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
                title:GHL(@"Вход не подтверждён")
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
    if (self.prefersGoogle && [self isGoogleURL:request.URL]
        && ![[request valueForHTTPHeaderField:@"User-Agent"] isEqualToString:kGHWebLoginGoogleUserAgent]) {
        NSMutableURLRequest *spoofed = [request mutableCopy];
        [spoofed setValue:kGHWebLoginGoogleUserAgent forHTTPHeaderField:@"User-Agent"];
        [webView loadRequest:spoofed];
        return NO;
    }
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
