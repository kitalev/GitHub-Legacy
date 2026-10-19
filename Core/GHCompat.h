
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXTERN BOOL GHPullToRefreshAvailable(void);

FOUNDATION_EXTERN NSDateFormatter *GHISODateFormatter(void);
FOUNDATION_EXTERN NSDateFormatter *GHMediumShortDateFormatter(void);
FOUNDATION_EXTERN NSDateFormatter *GHMediumDateFormatter(void);

FOUNDATION_EXTERN NSDate *GHDateFromISO8601String(NSString *isoString);
FOUNDATION_EXTERN CGSize GHCachedTextSize(NSString *text, UIFont *font, CGSize constraint, NSLineBreakMode lineBreakMode);

FOUNDATION_EXTERN UIImage *GHDecodedImageWithData(NSData *data);
FOUNDATION_EXTERN void GHDecodeImageDataAsync(NSData *data, void (^completion)(UIImage *image));

FOUNDATION_EXTERN NSString *GHFontAttributeName(void);
FOUNDATION_EXTERN NSString *GHForegroundColorAttributeName(void);

FOUNDATION_EXTERN NSString *GHEmojiForDisplay(NSString *emoji);

@interface UITableView (GHCompat)
- (void)gh_registerCellClass:(Class)cellClass forCellReuseIdentifier:(NSString *)identifier;
- (id)gh_dequeueCellWithIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath;
@end

@interface UIButton (GHCompat)
- (void)gh_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state;
@end

@class GHLegacyRefreshControl;

@interface UITableViewController (GHLegacyRefreshControlStorage)
@property (nonatomic, strong) GHLegacyRefreshControl *gh_legacyRefreshControl;

- (void)gh_forwardScrollViewDidScroll;
- (void)gh_forwardScrollViewDidEndDragging;
@end
