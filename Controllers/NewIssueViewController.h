#import <UIKit/UIKit.h>

@class GHIssueTemplate;

@interface NewIssueViewController : UIViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;
@property (nonatomic, strong) GHIssueTemplate *issueTemplate;
@property (nonatomic, copy) void (^onIssueCreated)(NSDictionary *issue);

+ (void)receiveIncomingFileAtPath:(NSString *)path;

@end
