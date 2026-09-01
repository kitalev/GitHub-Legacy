#import <UIKit/UIKit.h>

@interface RepoDetailViewController : UITableViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (BOOL)releaseListInfoFromURL:(NSURL *)url
                     ownerLogin:(NSString **)ownerLogin
                       repoName:(NSString **)repoName;

@end
