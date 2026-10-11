#import "GHWebSession.h"

static NSString * const kGHWebBaseURL = @"https://github.com";

@implementation GHWebSession

+ (NSURL *)baseURL {
    return [NSURL URLWithString:kGHWebBaseURL];
}

+ (NSURL *)signInURL {
    return [NSURL URLWithString:[kGHWebBaseURL stringByAppendingString:@"/login"]];
}

+ (NSString *)browserUserAgent {
    return @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
}

+ (BOOL)isSignedIn {
    BOOL hasSession = NO;
    BOOL loggedIn = NO;
    NSDate *now = [NSDate date];
    for (NSHTTPCookie *cookie in [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[self baseURL]]) {
        if (cookie.expiresDate && [cookie.expiresDate compare:now] != NSOrderedDescending) continue;
        if ([cookie.name isEqualToString:@"user_session"] && cookie.value.length > 0) hasSession = YES;
        if ([cookie.name isEqualToString:@"logged_in"] && [cookie.value isEqualToString:@"yes"]) loggedIn = YES;
    }
    return hasSession && loggedIn;
}

+ (BOOL)isSignInPageURL:(NSURL *)url {
    if (![[url.host lowercaseString] isEqualToString:@"github.com"]) return NO;
    NSString *path = url.path.length > 0 ? url.path : @"/";
    for (NSString *prefix in @[@"/login", @"/session", @"/sessions", @"/signup", @"/password_reset"]) {
        if ([path isEqualToString:prefix] || [path hasPrefix:[prefix stringByAppendingString:@"/"]]) return YES;
    }
    return NO;
}

+ (void)signOut {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [storage.cookies copy]) {
        NSString *domain = [cookie.domain lowercaseString];
        if ([domain isEqualToString:@"github.com"] || [domain hasSuffix:@".github.com"]) {
            [storage deleteCookie:cookie];
        }
    }
}

@end
