#import <UIKit/UIKit.h>

@interface GHPullRequestCell : UITableViewCell

+ (CGFloat)heightForPullRequest:(NSDictionary *)pullRequest width:(CGFloat)width;

- (void)configureWithPullRequest:(NSDictionary *)pullRequest isMerged:(BOOL)isMerged;

@end
