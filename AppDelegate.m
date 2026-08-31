#import "AppDelegate.h"
#import "RepoSearchViewController.h"
#import "StarredReposViewController.h"
#import "ProfileViewController.h"
#import "ExploreViewController.h"
#import "RepoOverviewViewController.h"
#import "ReadmeViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "GHThemeManager.h"
#import "GHIconRenderer.h"
#import "GHLocalization.h"

NSString * const kGHAppDidEnterBackgroundNotification = @"GHAppDidEnterBackgroundNotification";
NSString * const kGHAppWillEnterForegroundNotification = @"GHAppWillEnterForegroundNotification";
NSString * const kGHOpenReadmeStateKey = @"GHOpenReadmeState";

@interface AppDelegate ()

@property (nonatomic, strong) UITabBarItem *exploreTabItem;
@property (nonatomic, strong) UITabBarItem *searchTabItem;
@property (nonatomic, strong) UITabBarItem *starredTabItem;
@property (nonatomic, strong) UITabBarItem *profileTabItem;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    CGFloat iconSize = 30;
    UIColor *iconColor = [UIColor blackColor];

    ExploreViewController *exploreVC = [[ExploreViewController alloc] init];
    UIImage *exploreIcon = [GHIconRenderer compassIconWithColor:iconColor size:iconSize];
    self.exploreTabItem = [[UITabBarItem alloc] initWithTitle:GHL(@"Обзор") image:exploreIcon tag:0];
    exploreVC.tabBarItem = self.exploreTabItem;
    UINavigationController *exploreNav = [[UINavigationController alloc] initWithRootViewController:exploreVC];

    RepoSearchViewController *searchVC = [[RepoSearchViewController alloc] init];
    UIImage *searchIcon = [GHIconRenderer searchIconWithColor:iconColor size:iconSize];
    self.searchTabItem = [[UITabBarItem alloc] initWithTitle:GHL(@"Поиск") image:searchIcon tag:1];
    searchVC.tabBarItem = self.searchTabItem;
    UINavigationController *searchNav = [[UINavigationController alloc] initWithRootViewController:searchVC];

    StarredReposViewController *starredVC = [[StarredReposViewController alloc] init];
    UIImage *starredIcon = [GHIconRenderer starIconWithColor:iconColor size:iconSize filled:YES];
    self.starredTabItem = [[UITabBarItem alloc] initWithTitle:GHL(@"Избранное") image:starredIcon tag:2];
    starredVC.tabBarItem = self.starredTabItem;
    UINavigationController *starredNav = [[UINavigationController alloc] initWithRootViewController:starredVC];

    ProfileViewController *profileVC = [[ProfileViewController alloc] init];
    UIImage *profileIcon = [GHIconRenderer personIconWithColor:iconColor size:iconSize];
    self.profileTabItem = [[UITabBarItem alloc] initWithTitle:GHL(@"Профиль") image:profileIcon tag:3];
    profileVC.tabBarItem = self.profileTabItem;
    UINavigationController *profileNav = [[UINavigationController alloc] initWithRootViewController:profileVC];

    self.tabBarController = [[UITabBarController alloc] init];
    self.tabBarController.viewControllers = @[exploreNav, searchNav, starredNav, profileNav];

    self.window.rootViewController = self.tabBarController;
    [self.window makeKeyAndVisible];

    [[GHThemeManager sharedManager] applyToWindow:self.window];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(languageDidChange)
                                                  name:kGHLanguageDidChangeNotification
                                                object:nil];

    self.pendingRestoreState = [self savedRestoreState];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (self.pendingRestoreState == nil) return;

    NSDictionary *state = self.pendingRestoreState;
    self.pendingRestoreState = nil;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self restoreState:state];
    });
}

- (NSDictionary *)savedRestoreState {
    NSDictionary *state = [[NSUserDefaults standardUserDefaults] objectForKey:kGHOpenReadmeStateKey];
    if (![state isKindOfClass:[NSDictionary class]]) return nil;

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHOpenReadmeStateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSString *ownerLogin = [state[@"ownerLogin"] isKindOfClass:[NSString class]] ? state[@"ownerLogin"] : nil;
    NSString *repoName = [state[@"repoName"] isKindOfClass:[NSString class]] ? state[@"repoName"] : nil;
    if (ownerLogin.length == 0 || repoName.length == 0) return nil;

    NSTimeInterval savedAt = [state[@"savedAt"] isKindOfClass:[NSNumber class]] ? [state[@"savedAt"] doubleValue] : 0;
    NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - savedAt;
    static const NSTimeInterval kMaxRestoreAge = 30 * 60;
    if (savedAt <= 0 || age < 0 || age > kMaxRestoreAge) return nil;

    return state;
}

- (void)restoreState:(NSDictionary *)state {
    NSString *ownerLogin = state[@"ownerLogin"];
    NSString *repoName = state[@"repoName"];
    if (ownerLogin.length == 0 || repoName.length == 0) return;

    CGFloat scrollY = [state[@"scrollY"] isKindOfClass:[NSNumber class]] ? (CGFloat)[state[@"scrollY"] doubleValue] : 0;

    UINavigationController *nav = (UINavigationController *)self.tabBarController.selectedViewController;
    if (![nav isKindOfClass:[UINavigationController class]]) return;
    if (nav.viewControllers.count > 1) return;

    RepoOverviewViewController *overviewVC = [[RepoOverviewViewController alloc] init];
    overviewVC.repo = @{@"name": repoName,
                        @"owner": @{@"login": ownerLogin},
                        @"full_name": [NSString stringWithFormat:@"%@/%@", ownerLogin, repoName]};
    overviewVC.title = repoName;

    NSString *htmlPath = [state[@"htmlPath"] isKindOfClass:[NSString class]] ? state[@"htmlPath"] : nil;
    NSString *cachedHTML = htmlPath.length > 0
        ? [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:NULL]
        : nil;

    if (cachedHTML.length > 0) {
        ReadmeViewController *readmeVC = [[ReadmeViewController alloc] init];
        readmeVC.html = cachedHTML;
        readmeVC.ownerLogin = ownerLogin;
        readmeVC.repoName = repoName;
        readmeVC.initialScrollOffset = CGPointMake(0, scrollY);

        __weak RepoOverviewViewController *weakOverview = overviewVC;
        readmeVC.refreshHandler = ^(void (^completion)(NSString *html)) {
            [weakOverview refreshReadmeWithCompletion:completion];
        };
        NSString *baseURLString = [state[@"baseURL"] isKindOfClass:[NSString class]] ? state[@"baseURL"] : nil;
        if (baseURLString.length > 0) {
            readmeVC.baseURL = [NSURL URLWithString:baseURLString];
        }
        [nav setViewControllers:[nav.viewControllers arrayByAddingObjectsFromArray:@[overviewVC, readmeVC]]
                       animated:NO];
        return;
    }

    overviewVC.autoOpenFullReadme = YES;
    overviewVC.autoOpenReadmeScrollOffset = CGPointMake(0, scrollY);
    [nav pushViewController:overviewVC animated:NO];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {

    UIApplication *strongApplication = application;
    __block UIBackgroundTaskIdentifier bgTask = UIBackgroundTaskInvalid;
    bgTask = [strongApplication beginBackgroundTaskWithExpirationHandler:^{
        [strongApplication endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }];

    [[NSNotificationCenter defaultCenter] postNotificationName:kGHAppDidEnterBackgroundNotification object:nil];

    [CATransaction flush];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (bgTask != UIBackgroundTaskInvalid) {
            [strongApplication endBackgroundTask:bgTask];
            bgTask = UIBackgroundTaskInvalid;
        }
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application {

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kGHOpenReadmeStateKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:kGHAppWillEnterForegroundNotification object:nil];
}

- (void)languageDidChange {
    self.exploreTabItem.title = GHL(@"Обзор");
    self.searchTabItem.title = GHL(@"Поиск");
    self.starredTabItem.title = GHL(@"Избранное");
    self.profileTabItem.title = GHL(@"Профиль");
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
