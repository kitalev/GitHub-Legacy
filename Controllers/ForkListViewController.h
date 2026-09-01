#import <UIKit/UIKit.h>

@interface ForkListViewController : UITableViewController <UIActionSheetDelegate>

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (BOOL)forkListInfoFromURL:(NSURL *)url
                  ownerLogin:(NSString **)ownerLogin
                    repoName:(NSString **)repoName;

@end
