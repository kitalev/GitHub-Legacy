#import <UIKit/UIKit.h>

@interface IssueDetailViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, strong) NSDictionary *issue;
@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

+ (void)pushIssueNumber:(NSInteger)number
              ownerLogin:(NSString *)ownerLogin
                repoName:(NSString *)repoName
      fromViewController:(UIViewController *)fromViewController;

@end
