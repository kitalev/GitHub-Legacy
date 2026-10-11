#import <UIKit/UIKit.h>

@interface GHFileBrowserViewController : UITableViewController

- (id)initWithPath:(NSString *)path;

@property (nonatomic, copy) void (^onFilePicked)(NSString *path);

@end
