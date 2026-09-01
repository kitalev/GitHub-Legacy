#import <UIKit/UIKit.h>

@interface GHAvatarLoader : NSObject

+ (instancetype)sharedLoader;

- (void)loadAvatarWithURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView;

- (void)loadAvatarWithURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView completion:(void (^)(void))completion;

@end
