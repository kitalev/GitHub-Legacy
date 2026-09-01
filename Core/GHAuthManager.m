#import "GHAuthManager.h"

static NSString * const kGHTokenDefaultsKey = @"GHAccessToken";

@interface GHAuthManager ()
@property (nonatomic, copy) NSString *cachedToken;
@end

@implementation GHAuthManager

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
    [[NSUserDefaults standardUserDefaults] setObject:token forKey:kGHTokenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)logout {
    self.cachedToken = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHTokenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
