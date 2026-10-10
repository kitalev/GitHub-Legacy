#import <UIKit/UIKit.h>

@interface GHPinnedReposCell : UITableViewCell

@property (nonatomic, copy) void (^onRepoSelected)(NSDictionary *repo);

+ (CGFloat)cellHeight;

- (void)configureWithRepos:(NSArray *)repos;
- (void)applyTheme;

@end
