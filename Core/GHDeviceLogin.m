#import "GHDeviceLogin.h"
#import "GHJSONSerialization.h"

static NSString * const kGHDeviceLoginBuiltInClientID = @"Ov23liJ5Mma9pneXgbT1";

static NSString * const kGHDeviceLoginClientIDDefaultsKey = @"GHDeviceLoginClientID";
static NSString * const kGHDeviceCodeURL = @"https://github.com/login/device/code";
static NSString * const kGHAccessTokenURL = @"https://github.com/login/oauth/access_token";

@implementation GHDeviceLogin

+ (NSString *)clientID {
    if (kGHDeviceLoginBuiltInClientID.length > 0) return kGHDeviceLoginBuiltInClientID;
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kGHDeviceLoginClientIDDefaultsKey];
    return saved.length > 0 ? saved : nil;
}

+ (BOOL)hasBuiltInClientID {
    return kGHDeviceLoginBuiltInClientID.length > 0;
}

+ (void)setClientID:(NSString *)clientID {
    if (clientID.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:clientID forKey:kGHDeviceLoginClientIDDefaultsKey];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHDeviceLoginClientIDDefaultsKey];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSMutableURLRequest *)formRequestWithURL:(NSString *)urlString bodyParameters:(NSDictionary *)parameters {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in parameters) {
        NSString *value = [parameters[key] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @"";
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    NSString *body = [pairs componentsJoinedByString:@"&"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"GitHubLegacy-iOS" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:15.0];
    return request;
}

+ (void)requestDeviceCodeWithScope:(NSString *)scope
                         completion:(GHDeviceCodeCompletionBlock)completion {
    NSString *clientID = [self clientID];
    if (clientID.length == 0) {
        NSError *error = [NSError errorWithDomain:@"GHDeviceLogin" code:-1
                                          userInfo:@{NSLocalizedDescriptionKey: @"No client ID configured"}];
        if (completion) completion(nil, nil, nil, 0, 0, error);
        return;
    }

    NSMutableURLRequest *request = [self formRequestWithURL:kGHDeviceCodeURL
                                               bodyParameters:@{@"client_id": clientID, @"scope": scope ?: @""}];

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, nil, nil, 0, 0, connectionError);
            return;
        }

        id json = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *dict = [json isKindOfClass:[NSDictionary class]] ? json : nil;

        NSString *deviceCode = [dict[@"device_code"] isKindOfClass:[NSString class]] ? dict[@"device_code"] : nil;
        NSString *userCode = [dict[@"user_code"] isKindOfClass:[NSString class]] ? dict[@"user_code"] : nil;
        NSString *verificationURI = [dict[@"verification_uri"] isKindOfClass:[NSString class]] ? dict[@"verification_uri"] : nil;
        NSInteger interval = [dict[@"interval"] respondsToSelector:@selector(integerValue)] ? [dict[@"interval"] integerValue] : 5;
        NSInteger expiresIn = [dict[@"expires_in"] respondsToSelector:@selector(integerValue)] ? [dict[@"expires_in"] integerValue] : 900;

        if (deviceCode.length == 0 || userCode.length == 0) {
            NSString *message = [dict[@"error_description"] isKindOfClass:[NSString class]] ? dict[@"error_description"] : @"Unexpected response";
            NSError *error = [NSError errorWithDomain:@"GHDeviceLogin" code:-2
                                              userInfo:@{NSLocalizedDescriptionKey: message}];
            if (completion) completion(nil, nil, nil, 0, 0, error);
            return;
        }

        if (completion) completion(deviceCode, userCode, verificationURI, interval, expiresIn, nil);
    }];
}

+ (void)pollAccessTokenWithDeviceCode:(NSString *)deviceCode
                            completion:(GHDevicePollCompletionBlock)completion {
    NSString *clientID = [self clientID];
    if (clientID.length == 0 || deviceCode.length == 0) {
        NSError *error = [NSError errorWithDomain:@"GHDeviceLogin" code:-1
                                          userInfo:@{NSLocalizedDescriptionKey: @"No client ID configured"}];
        if (completion) completion(GHDevicePollResultError, nil, 0, error);
        return;
    }

    NSMutableURLRequest *request = [self formRequestWithURL:kGHAccessTokenURL
                                               bodyParameters:@{
        @"client_id": clientID,
        @"device_code": deviceCode,
        @"grant_type": @"urn:ietf:params:oauth:grant-type:device_code",
    }];

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(GHDevicePollResultError, nil, 0, connectionError);
            return;
        }

        id json = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *dict = [json isKindOfClass:[NSDictionary class]] ? json : nil;

        NSString *accessToken = [dict[@"access_token"] isKindOfClass:[NSString class]] ? dict[@"access_token"] : nil;
        if (accessToken.length > 0) {
            if (completion) completion(GHDevicePollResultSuccess, accessToken, 0, nil);
            return;
        }

        NSString *errorCode = [dict[@"error"] isKindOfClass:[NSString class]] ? dict[@"error"] : nil;
        if ([errorCode isEqualToString:@"authorization_pending"]) {
            if (completion) completion(GHDevicePollResultPending, nil, 0, nil);
        } else if ([errorCode isEqualToString:@"slow_down"]) {
            NSInteger newInterval = [dict[@"interval"] respondsToSelector:@selector(integerValue)] ? [dict[@"interval"] integerValue] : 0;
            if (completion) completion(GHDevicePollResultSlowDown, nil, newInterval, nil);
        } else if ([errorCode isEqualToString:@"expired_token"]) {
            if (completion) completion(GHDevicePollResultExpired, nil, 0, nil);
        } else if ([errorCode isEqualToString:@"access_denied"]) {
            if (completion) completion(GHDevicePollResultDenied, nil, 0, nil);
        } else {
            NSString *message = [dict[@"error_description"] isKindOfClass:[NSString class]] ? dict[@"error_description"] : (errorCode ?: @"Unexpected response");
            NSError *error = [NSError errorWithDomain:@"GHDeviceLogin" code:-3
                                              userInfo:@{NSLocalizedDescriptionKey: message}];
            if (completion) completion(GHDevicePollResultError, nil, 0, error);
        }
    }];
}

@end
