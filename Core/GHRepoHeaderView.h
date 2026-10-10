#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, GHRepoStarState) {
    GHRepoStarStateHidden,
    GHRepoStarStateChecking,
    GHRepoStarStateStarred,
    GHRepoStarStateNotStarred,
    GHRepoStarStateBusy,
    GHRepoStarStateError
};

@interface GHRepoHeaderView : UIView

@property (nonatomic, copy) void (^onOwnerTapped)(void);
@property (nonatomic, copy) void (^onHomepageTapped)(NSURL *url);
@property (nonatomic, copy) void (^onForksTapped)(void);
@property (nonatomic, copy) void (^onStarButtonTapped)(void);

- (void)configureWithRepo:(NSDictionary *)repo;
- (void)setStarState:(GHRepoStarState)state;
- (CGFloat)heightForWidth:(CGFloat)width;
- (void)applyTheme;

@end
