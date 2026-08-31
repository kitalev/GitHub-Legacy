#import <UIKit/UIKit.h>

@interface GHIconRenderer : NSObject

+ (UIImage *)gearIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)disclosureChevronWithColor:(UIColor *)color size:(CGSize)size;

+ (UIImage *)personIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)starIconWithColor:(UIColor *)color size:(CGFloat)size filled:(BOOL)filled;
+ (UIImage *)compassIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)searchIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)chevronUpIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)filledCircleWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)dotIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)smileyIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)issueLabelBadgeWithText:(NSString *)text
                       backgroundColor:(UIColor *)backgroundColor
                             textColor:(UIColor *)textColor
                             pointSize:(CGFloat)pointSize;

+ (UIColor *)colorFromHexString:(NSString *)hex;

+ (UIColor *)readableTextColorOverColor:(UIColor *)backgroundColor;

@end
