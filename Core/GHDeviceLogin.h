#import <Foundation/Foundation.h>

typedef void (^GHDeviceCodeCompletionBlock)(NSString *deviceCode,
                                             NSString *userCode,
                                             NSString *verificationURI,
                                             NSInteger interval,
                                             NSInteger expiresIn,
                                             NSError *error);

typedef NS_ENUM(NSInteger, GHDevicePollResult) {
    GHDevicePollResultPending,
    GHDevicePollResultSlowDown,
    GHDevicePollResultExpired,
    GHDevicePollResultDenied,
    GHDevicePollResultSuccess,
    GHDevicePollResultError
};

typedef void (^GHDevicePollCompletionBlock)(GHDevicePollResult result,
                                             NSString *accessToken,
                                             NSInteger newInterval,
                                             NSError *error);

@interface GHDeviceLogin : NSObject

+ (NSString *)clientID;
+ (BOOL)hasBuiltInClientID;
+ (void)setClientID:(NSString *)clientID;

+ (void)requestDeviceCodeWithScope:(NSString *)scope
                         completion:(GHDeviceCodeCompletionBlock)completion;

+ (void)pollAccessTokenWithDeviceCode:(NSString *)deviceCode
                            completion:(GHDevicePollCompletionBlock)completion;

@end
