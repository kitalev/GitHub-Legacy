#import "WebLoginViewController.h"
#import "GHWebSession.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"

@interface WebLoginViewController () <UIWebViewDelegate>
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
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
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];

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
    [self.spinner startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (!webView.isLoading) [self.spinner stopAnimating];
    [self finishIfSignedInAtURL:webView.request.URL];
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
