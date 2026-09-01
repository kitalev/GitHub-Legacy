#import <UIKit/UIKit.h>

@interface GHStarredRepoCell : UITableViewCell

+ (CGFloat)heightForRepo:(NSDictionary *)repo width:(CGFloat)width;

- (void)configureWithRepo:(NSDictionary *)repo;

@end
