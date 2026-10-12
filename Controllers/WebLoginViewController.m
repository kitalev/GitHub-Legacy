#import "WebLoginViewController.h"
#import "GHWebSession.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

@interface WebLoginViewController () <UIWebViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIBarButtonItem *spinnerItem;
@property (nonatomic, strong) UIBarButtonItem *confirmItem;
@property (nonatomic, assign) BOOL finished;
@end

@implementation WebLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.title.length == 0) self.title = GHL(@"Вход на github.com");
    self.view.backgroundColor = GHBackgroundColor();

    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    self.webView.scalesPageToFit = YES;
    [self.view addSubview:self.webView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:GHSpinnerStyle()];
    self.spinner.hidesWhenStopped = YES;
    self.spinnerItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    self.confirmItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Другой способ")
                                                        style:UIBarButtonItemStyleBordered
                                                       target:self
                                                       action:@selector(otherTwoFactorMethodTapped)];
    self.navigationItem.rightBarButtonItem = self.spinnerItem;

    NSArray *stack = self.navigationController.viewControllers;
    if (self.presentingViewController && stack.count > 0 && stack[0] == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Отмена")
                                                                                 style:UIBarButtonItemStyleBordered
                                                                                target:self
                                                                                action:@selector(cancelTapped)];
    }

    [self.webView loadRequest:[NSURLRequest requestWithURL:self.startURL ?: [GHWebSession signInURL]]];
}

- (void)cancelTapped {
    [self.webView stopLoading];
    [self dismissViewControllerAnimated:YES completion:nil];
}

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
    if (self.navigationItem.rightBarButtonItem != self.spinnerItem) self.navigationItem.rightBarButtonItem = self.spinnerItem;
    [self.spinner startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (!webView.isLoading) [self.spinner stopAnimating];
    if ([self finishIfSignedInAtURL:webView.request.URL]) return;
    [self updateConfirmItem];
    [self enableAuthorizeButtonsIfNeeded];
    [self fillDeviceUserCodeIfNeeded];
}

- (void)enableAuthorizeButtonsIfNeeded {
    NSURL *url = self.webView.request.URL;
    if (![[url.host lowercaseString] isEqualToString:@"github.com"]) return;
    if (![url.path hasPrefix:@"/login/device"] && ![url.path hasPrefix:@"/login/oauth"]) return;
    [self.webView stringByEvaluatingJavaScriptFromString:
        @"(function(){"
         "var bs=document.querySelectorAll('form button[disabled],form input[type=submit][disabled]');"
         "for(var i=0;i<bs.length;i++){bs[i].removeAttribute('disabled');bs[i].disabled=false;}"
         "})()"];
}

- (BOOL)isTwoFactorPage {
    NSURL *url = self.webView.request.URL;
    return [[url.host lowercaseString] isEqualToString:@"github.com"] && [url.path hasPrefix:@"/sessions/two-factor"];
}

- (void)updateConfirmItem {
    UIBarButtonItem *item = [self isTwoFactorPage] ? self.confirmItem : self.spinnerItem;
    if (self.navigationItem.rightBarButtonItem != item) [self.navigationItem setRightBarButtonItem:item animated:YES];
}

- (NSArray *)twoFactorMethods {
    return @[@[GHL(@"Код из приложения-аутентификатора"), @"/sessions/two-factor/app"],
             @[GHL(@"Код из SMS"), @"/sessions/two-factor/sms"],
             @[GHL(@"Код восстановления"), @"/sessions/recovery"]];
}

- (void)otherTwoFactorMethodTapped {
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
                                                       delegate:self
                                              cancelButtonTitle:nil
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:nil];
    for (NSArray *method in [self twoFactorMethods]) [sheet addButtonWithTitle:method[0]];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:GHL(@"Отмена")];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet showFromBarButtonItem:self.confirmItem animated:YES];
    } else {
        [sheet showInView:self.view];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSArray *methods = [self twoFactorMethods];
    if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0 || buttonIndex >= (NSInteger)methods.count) return;
    NSURL *url = [[NSURL URLWithString:methods[buttonIndex][1] relativeToURL:[GHWebSession baseURL]] absoluteURL];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)fillDeviceUserCodeIfNeeded {
    NSURL *url = self.webView.request.URL;
    if (self.deviceUserCode.length == 0 || ![[url.host lowercaseString] isEqualToString:@"github.com"]) return;
    if (![url.path isEqualToString:@"/login/device"]) return;

    NSData *codeJSON = [NSJSONSerialization dataWithJSONObject:@[self.deviceUserCode] options:0 error:nil];
    NSString *codeArray = [[NSString alloc] initWithData:codeJSON encoding:NSUTF8StringEncoding];
    if (codeArray.length == 0) return;
    NSString *script = [NSString stringWithFormat:
        @"(function(c){"
         "var f=document.querySelector('form[action*=\"/login/device\"]');if(!f)return;"
         "var ins=[].filter.call(f.querySelectorAll('input'),function(i){var t=(i.type||'text').toLowerCase();"
         "return (t=='text'||t=='tel')&&!i.disabled&&i.offsetParent!==null;});"
         "if(!ins.length)return;"
         "function set(i,v){i.focus();i.value=v;['input','change','keyup'].forEach(function(n){"
         "var e=document.createEvent('HTMLEvents');e.initEvent(n,true,true);i.dispatchEvent(e);});}"
         "if(ins.length==1){set(ins[0],c);return;}"
         "var s=c.replace(/-/g,'');ins.forEach(function(i,k){if(k<s.length)set(i,s.charAt(k));});"
         "})(%@[0]);", codeArray];
    [self.webView stringByEvaluatingJavaScriptFromString:script];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (!webView.isLoading) [self.spinner stopAnimating];
    if (self.finished) return;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    if ([error.domain isEqualToString:@"WebKitErrorDomain"] && error.code == 102) return;
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:GHL(@"Не удалось открыть github.com")
                                                     message:error.localizedDescription
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil];
    [alert show];
}

- (void)dealloc {
    self.webView.delegate = nil;
    [self.webView stopLoading];
}

@end
