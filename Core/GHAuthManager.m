#import "GHAuthManager.h"
#import "GHWebSession.h"

static NSString * const kGHTokenDefaultsKey = @"GHAccessToken";
static NSString * const kGHCurrentUserLoginDefaultsKey = @"GHCurrentUserLogin";

@interface GHAuthManager ()
@property (nonatomic, copy) NSString *cachedToken;
@end

@implementation GHAuthManager

@synthesize currentUserLogin = _currentUserLogin;

+ (instancetype)sharedManager {
    static GHAuthManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHAuthManager alloc] init];
    });
    return instance;
}

- (NSString *)accessToken {
    if (!_cachedToken) {
        _cachedToken = [[NSUserDefaults standardUserDefaults] stringForKey:kGHTokenDefaultsKey];
    }
    return _cachedToken;
}

- (BOOL)isAuthenticated {
    return self.accessToken.length > 0;
}

- (void)setAccessToken:(NSString *)token {
    self.cachedToken = token;
    self.currentUserLogin = nil;
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:kGHTokenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)currentUserLogin {
    if (!_currentUserLogin) {
        _currentUserLogin = [[NSUserDefaults standardUserDefaults] stringForKey:kGHCurrentUserLoginDefaultsKey];
    }
    return _currentUserLogin;
}

- (void)setCurrentUserLogin:(NSString *)currentUserLogin {
    _currentUserLogin = [currentUserLogin copy];
    if (currentUserLogin.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:currentUserLogin forKey:kGHCurrentUserLoginDefaultsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHCurrentUserLoginDefaultsKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)logout {
    self.cachedToken = nil;
    self.currentUserLogin = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHTokenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [GHWebSession signOut];
}

@end
