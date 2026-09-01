#import <UIKit/UIKit.h>

@interface IssueListViewController : UITableViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (BOOL)issueListInfoFromURL:(NSURL *)url
                  ownerLogin:(NSString **)ownerLogin
                    repoName:(NSString **)repoName;

+ (BOOL)issueNumberFromURL:(NSURL *)url
                 ownerLogin:(NSString **)ownerLogin
                   repoName:(NSString **)repoName
                     number:(NSInteger *)number;

@end
