#import "WebLoginViewController.h"
#import "GHWebSession.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

@interface WebLoginViewController () <UIWebViewDelegate>
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
    self.confirmItem = [[UIBarButtonItem alloc] initWithTitle:GHL(@"Подтвердил")
                                                        style:UIBarButtonItemStyleDone
                                                       target:self
                                                       action:@selector(confirmTwoFactorTapped)];
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
    [self installDetailsSupport];
    [self updateConfirmItem];
    [self fillDeviceUserCodeIfNeeded];
}

- (BOOL)isTwoFactorPage {
    NSURL *url = self.webView.request.URL;
    return [[url.host lowercaseString] isEqualToString:@"github.com"] && [url.path hasPrefix:@"/sessions/two-factor"];
}

- (void)updateConfirmItem {
    UIBarButtonItem *item = [self isTwoFactorPage] ? self.confirmItem : self.spinnerItem;
    if (self.navigationItem.rightBarButtonItem != item) [self.navigationItem setRightBarButtonItem:item animated:YES];
}

- (void)confirmTwoFactorTapped {
    NSString *result = [self.webView stringByEvaluatingJavaScriptFromString:
        @"(function(){"
         "var fs=document.querySelectorAll('form[action*=\"two-factor\"]');"
         "var f=null;for(var i=0;i<fs.length;i++){if((fs[i].getAttribute('action')||'').indexOf('mobile')>=0){f=fs[i];break;}}"
         "if(!f&&fs.length)f=fs[0];"
         "if(!f)return 'none';f.submit();return 'ok';"
         "})()"];
    if (![result isEqualToString:@"ok"]) [self.webView reload];
}

- (void)installDetailsSupport {
    [self.webView stringByEvaluatingJavaScriptFromString:
        @"(function(){"
         "if(window.__ghLegacyDetails||!document.head)return;window.__ghLegacyDetails=1;"
         "var st=document.createElement('style');"
         "st.textContent='details:not([open])>*:not(summary){display:none!important}details[open]>*{display:block}';"
         "document.head.appendChild(st);"
         "document.addEventListener('click',function(e){"
         "var t=e.target;while(t&&t.tagName!='SUMMARY')t=t.parentNode;if(!t)return;"
         "var d=t.parentNode;if(!d||d.tagName!='DETAILS')return;"
         "e.preventDefault();e.stopPropagation();"
         "if(d.hasAttribute('open'))d.removeAttribute('open');else d.setAttribute('open','');"
         "},true);"
         "})()"];
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
