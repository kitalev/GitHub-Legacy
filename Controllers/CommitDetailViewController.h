#import <UIKit/UIKit.h>

@interface CommitDetailViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;
@property (nonatomic, copy) NSString *sha;

+ (BOOL)commitInfoFromURL:(NSURL *)url
                ownerLogin:(NSString **)ownerLogin
                  repoName:(NSString **)repoName
                       sha:(NSString **)sha;

@end
