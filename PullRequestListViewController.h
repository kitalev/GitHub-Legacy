#import <UIKit/UIKit.h>

@interface PullRequestListViewController : UITableViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (BOOL)pullRequestListInfoFromURL:(NSURL *)url
                        ownerLogin:(NSString **)ownerLogin
                          repoName:(NSString **)repoName;

@end
