#import <UIKit/UIKit.h>

FOUNDATION_EXTERN UIColor *GHColorForLanguage(NSString *language);

@interface GHStarredRepoCell : UITableViewCell

+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width;

- (void)configureWithRepo:(NSDictionary *)repo;

@end
