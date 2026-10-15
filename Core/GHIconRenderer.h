#import <UIKit/UIKit.h>

@interface GHIconRenderer : NSObject

+ (UIImage *)gearIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)disclosureChevronWithColor:(UIColor *)color size:(CGSize)size;

+ (UIImage *)personIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)busyStatusIconWithSize:(CGFloat)size;
+ (UIImage *)messageStatusIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)starIconWithColor:(UIColor *)color size:(CGFloat)size filled:(BOOL)filled;
+ (UIImage *)compassIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)searchIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)chevronUpIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)filledCircleWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)dotIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)smileyIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)successBadgeWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)devicesIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)keyIconWithColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)linkIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)externalLinkIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)locationIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)organizationIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)repoIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)pinIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)mailIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)personOutlineIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)issueOpenIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)issueClosedIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)issueNotPlannedIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)commentIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)pullRequestIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)pullRequestMergedIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)pullRequestClosedIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)pullRequestDraftIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)tagIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)moreIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)codeIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)commitIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)forkIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)branchIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)lawIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)infoIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)fileZipIconWithColor:(UIColor *)color size:(CGFloat)size;
+ (UIImage *)tileWithIcon:(UIImage *)icon backgroundColor:(UIColor *)color size:(CGFloat)size;

+ (UIImage *)issueLabelBadgeWithText:(NSString *)text
                       backgroundColor:(UIColor *)backgroundColor
                             textColor:(UIColor *)textColor
                             pointSize:(CGFloat)pointSize;

+ (UIColor *)colorFromHexString:(NSString *)hex;

+ (UIColor *)readableTextColorOverColor:(UIColor *)backgroundColor;

@end
