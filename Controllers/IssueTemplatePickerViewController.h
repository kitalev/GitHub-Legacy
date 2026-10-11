#import <UIKit/UIKit.h>

@class GHIssueTemplateSet;

@interface IssueTemplatePickerViewController : UITableViewController

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;
@property (nonatomic, strong) GHIssueTemplateSet *templateSet;
@property (nonatomic, copy) void (^onIssueCreated)(NSDictionary *issue);

@end
