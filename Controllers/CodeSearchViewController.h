#import <UIKit/UIKit.h>

@interface CodeSearchViewController : UITableViewController <UISearchBarDelegate>

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

@end
