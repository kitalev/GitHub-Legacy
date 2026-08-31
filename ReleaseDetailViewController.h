#import <UIKit/UIKit.h>

@interface ReleaseDetailViewController : UITableViewController <UIWebViewDelegate, UIAlertViewDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) NSDictionary *releaseInfo;
@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

@end
