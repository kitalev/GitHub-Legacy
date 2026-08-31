#import <UIKit/UIKit.h>

@interface RepoFilesViewController : UITableViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

@property (nonatomic, copy) NSString *path;

@end
