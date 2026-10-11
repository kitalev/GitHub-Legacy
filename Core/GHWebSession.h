#import <Foundation/Foundation.h>

@interface GHWebSession : NSObject

+ (NSURL *)baseURL;
+ (NSURL *)signInURL;
+ (NSString *)browserUserAgent;
+ (BOOL)isSignedIn;
+ (BOOL)isSignInPageURL:(NSURL *)url;
+ (void)signOut;

@end
