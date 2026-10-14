#import <UIKit/UIKit.h>

@interface GHFileBrowserViewController : UITableViewController

- (id)initWithPath:(NSString *)path;

+ (NSArray *)fileManagerLinksForFolder:(NSString *)folder;
+ (NSString *)defaultPickFolder;
+ (BOOL)canBrowseFileSystem;

@property (nonatomic, copy) void (^onFilePicked)(NSString *path);

@end
