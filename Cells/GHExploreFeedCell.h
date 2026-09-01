#import <UIKit/UIKit.h>

@interface GHExploreFeedCell : UITableViewCell

+ (CGFloat)heightForEntryWithRepo:(NSDictionary *)repo release:(NSDictionary *)release width:(CGFloat)width;

- (void)configureWithRepo:(NSDictionary *)repo release:(NSDictionary *)release relativeDate:(NSString *)relativeDate;

@end
