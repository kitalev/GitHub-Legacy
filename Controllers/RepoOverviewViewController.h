#import <UIKit/UIKit.h>

@interface RepoOverviewViewController : UITableViewController <UIWebViewDelegate>

@property (nonatomic, strong) NSDictionary *repo;

+ (BOOL)repoOverviewInfoFromURL:(NSURL *)url
                      ownerLogin:(NSString **)ownerLogin
                        repoName:(NSString **)repoName;

+ (void)pushRepoOverviewForOwnerLogin:(NSString *)ownerLogin
                              repoName:(NSString *)repoName
                    fromViewController:(UIViewController *)fromViewController;

- (void)refreshReadmeWithCompletion:(void (^)(NSString *html))completion;

@property (nonatomic, assign) BOOL autoOpenFullReadme;
@property (nonatomic, assign) CGPoint autoOpenReadmeScrollOffset;

@end
