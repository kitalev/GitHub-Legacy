#import <UIKit/UIKit.h>

// Scope bar for iOS 4, where UISegmentedControl cannot be restyled and the
// stock scope bar ignores the app's light background. Mimics the iOS 5/6 look.
@interface GHLegacyScopeBar : UIControl
@property (nonatomic, copy) NSArray *titles;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL dark;
@end
