
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kGHHandedOffURLKey;

static BOOL GHIsGitHubURL(NSURL *url) {
    if (url == nil) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return NO;

    NSString *host = url.host.lowercaseString;
    if (![host isEqualToString:@"github.com"] && ![host isEqualToString:@"www.github.com"]) return NO;

    NSString *path = url.path.lowercaseString;
    NSArray *webOnlyPrefixes = [NSArray arrayWithObjects:@"/login", @"/logout", @"/session", @"/sessions", @"/settings",
                                @"/join", @"/signup", @"/password_reset", @"/apps", @"/marketplace", nil];
    for (NSString *prefix in webOnlyPrefixes) {
        if ([path isEqualToString:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) return NO;
    }

    return YES;
}

static NSString * const kGHSafariRedirectPrefsPath = @"/var/mobile/Library/Preferences/com.githublegacy.safariredirect.plist";
static NSString * const kGHSafariRedirectEnabledKey = @"Enabled";

static BOOL GHRedirectEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kGHSafariRedirectPrefsPath];
    id value = [prefs objectForKey:kGHSafariRedirectEnabledKey];
    if (value == nil) return YES;
    return [value boolValue];
}

static void GHHandOffToApp(NSURL *url) {
    static NSString *lastURLString = nil;
    static CFAbsoluteTime lastTime = 0;
    NSString *urlString = url.absoluteString;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ([lastURLString isEqualToString:urlString] && now - lastTime < 3.0) return;
    lastURLString = [urlString copy];
    lastTime = now;

    NSString *encoded = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *appURL = [NSURL URLWithString:[NSString stringWithFormat:@"githublegacy://open?url=%@", encoded]];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = [UIApplication sharedApplication];
        SEL modernOpen = NSSelectorFromString(@"openURL:options:completionHandler:");
        if ([application respondsToSelector:modernOpen]) {
            typedef void (*GHOpenURLFunction)(id, SEL, NSURL *, NSDictionary *, id);
            ((GHOpenURLFunction)[application methodForSelector:modernOpen])(application, modernOpen, appURL, @{}, nil);
        } else {
            [application openURL:appURL];
        }
    });
}

static void GHMarkHandedOff(id tabDocument, NSURL *url) {
    objc_setAssociatedObject(tabDocument, &kGHHandedOffURLKey, [url absoluteString], OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static BOOL GHIsMainFrame(id webView, id frame) {
    if (webView == nil || frame == nil) return YES;
    if (![webView respondsToSelector:@selector(mainFrame)]) return YES;
    id mainFrame = [webView performSelector:@selector(mainFrame)];
    return mainFrame == frame;
}

static BOOL GHFrameInfoIsMainFrame(id frameInfo) {
    if (frameInfo == nil) return YES;
    if (![frameInfo respondsToSelector:@selector(isMainFrame)]) return YES;
    typedef BOOL (*GHBoolGetter)(id, SEL);
    GHBoolGetter getter = (GHBoolGetter)[frameInfo methodForSelector:@selector(isMainFrame)];
    return getter(frameInfo, @selector(isMainFrame));
}

static BOOL gGHKeyboardVisible = NO;

static void GHStartObservingKeyboard(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIKeyboardWillShowNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) { gGHKeyboardVisible = YES; }];
    [center addObserverForName:UIKeyboardWillHideNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *note) { gGHKeyboardVisible = NO; }];
}

static BOOL GHUsesModernNavigationDelegate(void) {
    NSString *version = [[UIDevice currentDevice] systemVersion];
    return [version compare:@"9.0" options:NSNumericSearch] != NSOrderedAscending;
}

%group GHRedirectHooksLegacy

%hook TabDocument

- (void)webView:(id)webView
    decidePolicyForNavigationAction:(id)actionInformation
                            request:(id)request
                              frame:(id)frame
                   decisionListener:(id)decisionListener {
    NSURL *url = [request respondsToSelector:@selector(URL)] ? [request URL] : nil;

    if (GHIsGitHubURL(url) && GHIsMainFrame(webView, frame) && !gGHKeyboardVisible && GHRedirectEnabled()) {
        if ([decisionListener respondsToSelector:@selector(ignore)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [decisionListener performSelector:@selector(ignore)];
#pragma clang diagnostic pop
        }
        GHMarkHandedOff(self, url);
        GHHandOffToApp(url);
    }

    %orig;
}

%end

%end

%group GHRedirectHooksLoadURL

%hook TabDocument

- (void)loadURL:(id)url userDriven:(BOOL)userDriven {
    if (GHIsGitHubURL(url) && !gGHKeyboardVisible && GHRedirectEnabled()) {
        GHMarkHandedOff(self, url);
        GHHandOffToApp(url);
        return;
    }
    %orig;
}

%end

%end

%group GHRedirectHooksModern

%hook TabDocument

- (void)webView:(id)webView
    decidePolicyForNavigationAction:(id)actionInformation
                     decisionHandler:(void (^)(NSInteger))decisionHandler {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id request = [actionInformation respondsToSelector:@selector(request)]
        ? [actionInformation performSelector:@selector(request)] : nil;
    NSURL *url = [request respondsToSelector:@selector(URL)] ? [request URL] : nil;
    id targetFrame = [actionInformation respondsToSelector:@selector(targetFrame)]
        ? [actionInformation performSelector:@selector(targetFrame)] : nil;
#pragma clang diagnostic pop
    BOOL isGitHub = GHIsGitHubURL(url);
    BOOL isMain = GHFrameInfoIsMainFrame(targetFrame);
    BOOL enabled = GHRedirectEnabled();
    id selfAsID = self;
    BOOL keyboardVisible = gGHKeyboardVisible;

    if (isGitHub && isMain && !keyboardVisible && enabled) {
        GHMarkHandedOff(selfAsID, url);
        GHHandOffToApp(url);
        decisionHandler(0);
        return;
    }

    %orig;
}

%end

%end

%group GHRedirectHooksPreferences

%hook TabDocument

- (void)webView:(id)webView
    decidePolicyForNavigationAction:(id)actionInformation
                         preferences:(id)preferences
                     decisionHandler:(void (^)(NSInteger, id))decisionHandler {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id request = [actionInformation respondsToSelector:@selector(request)]
        ? [actionInformation performSelector:@selector(request)] : nil;
    NSURL *url = [request respondsToSelector:@selector(URL)] ? [request URL] : nil;
    id targetFrame = [actionInformation respondsToSelector:@selector(targetFrame)]
        ? [actionInformation performSelector:@selector(targetFrame)] : nil;
#pragma clang diagnostic pop
    id selfAsID = self;
    if (GHIsGitHubURL(url) && GHFrameInfoIsMainFrame(targetFrame) && !gGHKeyboardVisible && GHRedirectEnabled()) {
        GHMarkHandedOff(selfAsID, url);
        GHHandOffToApp(url);
        decisionHandler(0, preferences);
        return;
    }

    %orig;
}

%end

%end

%group GHRedirectHooksProvisional

%hook TabDocument

- (void)webView:(id)webView didStartProvisionalNavigation:(id)navigation {
    %orig;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id url = [webView respondsToSelector:@selector(URL)] ? [webView performSelector:@selector(URL)] : nil;
#pragma clang diagnostic pop
    if (![url isKindOfClass:[NSURL class]] || !GHIsGitHubURL(url) || gGHKeyboardVisible || !GHRedirectEnabled()) return;
    id selfAsID = self;
    GHMarkHandedOff(selfAsID, url);
    if ([webView respondsToSelector:@selector(stopLoading)]) [webView stopLoading];
    if ([webView respondsToSelector:@selector(canGoBack)] && [webView respondsToSelector:@selector(goBack)]) {
        typedef BOOL (*GHBoolGetter)(id, SEL);
        if (((GHBoolGetter)[webView methodForSelector:@selector(canGoBack)])(webView, @selector(canGoBack))) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [webView performSelector:@selector(goBack)];
#pragma clang diagnostic pop
        }
    }
    GHHandOffToApp(url);
}

%end

%end

%group GHRedirectHooksActivation

%hook TabDocument

- (void)becameActive {
    %orig;

    id selfAsID = self;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id currentURL = [selfAsID respondsToSelector:@selector(URL)]
        ? [selfAsID performSelector:@selector(URL)] : nil;
#pragma clang diagnostic pop

    if (![currentURL isKindOfClass:[NSURL class]]) return;
    if (!GHIsGitHubURL(currentURL) || !GHRedirectEnabled()) return;

    NSString *urlString = [currentURL absoluteString];
    NSString *alreadyHandedOff = objc_getAssociatedObject(selfAsID, &kGHHandedOffURLKey);
    if ([alreadyHandedOff isEqualToString:urlString]) return;

    objc_setAssociatedObject(selfAsID, &kGHHandedOffURLKey, urlString, OBJC_ASSOCIATION_COPY_NONATOMIC);
    GHHandOffToApp(currentURL);
}

%end

%end

%ctor {
    GHStartObservingKeyboard();
    Class tabDocumentClass = objc_getClass("TabDocument");
    if (tabDocumentClass == Nil) return;

    if (GHUsesModernNavigationDelegate()) {
        if (class_getInstanceMethod(tabDocumentClass, @selector(webView:decidePolicyForNavigationAction:decisionHandler:)) != NULL) {
            %init(GHRedirectHooksModern);
        }
    } else {
        if (class_getInstanceMethod(tabDocumentClass, @selector(webView:decidePolicyForNavigationAction:request:frame:decisionListener:)) != NULL) {
            %init(GHRedirectHooksLegacy);
        }
        if (class_getInstanceMethod(tabDocumentClass, @selector(loadURL:userDriven:)) != NULL) {
            %init(GHRedirectHooksLoadURL);
        }
    }

    if (class_getInstanceMethod(tabDocumentClass, @selector(webView:decidePolicyForNavigationAction:preferences:decisionHandler:)) != NULL) {
        %init(GHRedirectHooksPreferences);
    }
    if (GHUsesModernNavigationDelegate()
        && class_getInstanceMethod(tabDocumentClass, @selector(webView:didStartProvisionalNavigation:)) != NULL) {
        %init(GHRedirectHooksProvisional);
    }
    if (class_getInstanceMethod(tabDocumentClass, @selector(becameActive)) != NULL) {
        %init(GHRedirectHooksActivation);
    }
}
