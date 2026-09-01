#import <UIKit/UIKit.h>

@interface GHIssueCell : UITableViewCell

+ (CGFloat)heightForIssue:(NSDictionary *)issue width:(CGFloat)width;

- (void)configureWithIssue:(NSDictionary *)issue;

@end
