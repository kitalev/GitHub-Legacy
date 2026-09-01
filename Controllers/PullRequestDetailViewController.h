#import <UIKit/UIKit.h>

@interface PullRequestDetailViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, strong) NSDictionary *pullRequest;
@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (BOOL)pullRequestNumberFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName
                           number:(NSInteger *)number;

+ (void)pushPullRequestNumber:(NSInteger)number
                   ownerLogin:(NSString *)ownerLogin
                     repoName:(NSString *)repoName
          fromViewController:(UIViewController *)fromViewController;

@end
