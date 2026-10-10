#import <UIKit/UIKit.h>

@class GHProfileHeaderView;

@interface GHProfileBaseViewController : UITableViewController

@property (nonatomic, strong) NSDictionary *userInfo;
@property (nonatomic, strong) NSMutableArray *repos;
@property (nonatomic, strong) NSMutableArray *pinnedRepos;
@property (nonatomic, assign) NSInteger starredCount;
@property (nonatomic, assign) BOOL starredCountLoaded;
@property (nonatomic, assign) NSInteger organizationsCount;
@property (nonatomic, assign) BOOL organizationsCountLoaded;
@property (nonatomic, assign) BOOL reposLoaded;
@property (nonatomic, assign) BOOL headerLoading;

@property (nonatomic, strong) GHProfileHeaderView *headerView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

- (NSString *)profileLogin;
- (NSString *)starredViewedLogin;
- (BOOL)showsProfileContent;
- (void)reload;
- (void)applyTheme;
- (void)handleLanguageDidChange;
- (void)refreshHeader;
- (void)endRefreshing;
- (void)resetProfileData;

- (NSString *)pinnedItemsSelection;
- (void)fetchPinnedReposWithQuery:(NSString *)query rootKey:(NSString *)rootKey;
- (void)fetchOrganizationsForLogin:(NSString *)login;
- (void)handleStarredResponse:(id)jsonObject error:(NSError *)error;
- (void)handleReposResponse:(id)jsonObject error:(NSError *)error;

@end
