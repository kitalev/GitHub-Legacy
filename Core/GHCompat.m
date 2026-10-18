
#import "GHCompat.h"
#import "GHLegacyRefreshControl.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>

BOOL GHPullToRefreshAvailable(void) {
    static BOOL available;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        available = (NSClassFromString(@"UIRefreshControl") != Nil);
    });
    return available;
}

NSDateFormatter *GHISODateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
    return formatter;
}

NSDateFormatter *GHMediumShortDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    });
    return formatter;
}

NSDateFormatter *GHMediumDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    });
    return formatter;
}

static NSString *GHStringConstant(const char *symbolName) {
    NSString * const *ref = (NSString * const *)dlsym(RTLD_DEFAULT, symbolName);
    return ref ? *ref : nil;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

NSString *GHFontAttributeName(void) {
    static NSString *name = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        name = GHStringConstant("NSFontAttributeName") ?: GHStringConstant("UITextAttributeFont") ?: @"UITextAttributeFont";
    });
    return name;
}

NSString *GHForegroundColorAttributeName(void) {
    static NSString *name = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        name = GHStringConstant("NSForegroundColorAttributeName") ?: GHStringConstant("UITextAttributeTextColor") ?: @"UITextAttributeTextColor";
    });
    return name;
}

#pragma clang diagnostic pop

#pragma mark - Emoji

NSString *GHEmojiForDisplay(NSString *emoji) {
    if (emoji.length == 0) return emoji;

    if (GHPullToRefreshAvailable()) return emoji;

    NSMutableString *stripped = [emoji mutableCopy];
    [stripped replaceOccurrencesOfString:@"\uFE0F"
                              withString:@""
                                 options:0
                                   range:NSMakeRange(0, stripped.length)];
    [stripped replaceOccurrencesOfString:@"\uFE0E"
                              withString:@""
                                 options:0
                                   range:NSMakeRange(0, stripped.length)];
    return stripped;
}

#pragma mark - UITableView cell registration

static const void *kGHRegisteredCellClassesKey = &kGHRegisteredCellClassesKey;

@implementation UITableView (GHCompat)

- (NSMutableDictionary *)gh_registeredCellClasses {
    NSMutableDictionary *table = objc_getAssociatedObject(self, kGHRegisteredCellClassesKey);
    if (table == nil) {
        table = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, kGHRegisteredCellClassesKey, table,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return table;
}

- (void)gh_registerCellClass:(Class)cellClass forCellReuseIdentifier:(NSString *)identifier {
    if (cellClass == Nil || identifier.length == 0) return;

    if ([self respondsToSelector:@selector(registerClass:forCellReuseIdentifier:)]) {
        [self registerClass:cellClass forCellReuseIdentifier:identifier];
        return;
    }

    [[self gh_registeredCellClasses] setObject:cellClass forKey:identifier];
}

- (id)gh_dequeueCellWithIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath {
    if ([self respondsToSelector:@selector(dequeueReusableCellWithIdentifier:forIndexPath:)]) {
        return [self dequeueReusableCellWithIdentifier:identifier forIndexPath:indexPath];
    }

    UITableViewCell *cell = [self dequeueReusableCellWithIdentifier:identifier];
    if (cell != nil) return cell;

    Class cellClass = [[self gh_registeredCellClasses] objectForKey:identifier];
    if (cellClass == Nil) cellClass = [UITableViewCell class];

    return [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault
                            reuseIdentifier:identifier];
}

@end

#pragma mark - UIButton attributed titles

@implementation UIButton (GHCompat)

- (void)gh_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    if ([self respondsToSelector:@selector(setAttributedTitle:forState:)]) {
        [self setAttributedTitle:title forState:state];
        return;
    }

    [self setTitle:title.string forState:state];

    if (title.length == 0) return;
    UIColor *color = [title attribute:GHForegroundColorAttributeName()
                              atIndex:0
                       effectiveRange:NULL];
    if ([color isKindOfClass:[UIColor class]]) {
        [self setTitleColor:color forState:state];
    }
}

@end

#pragma mark - Legacy pull-to-refresh storage

static const void *kGHLegacyRefreshControlKey = &kGHLegacyRefreshControlKey;

@implementation UITableViewController (GHLegacyRefreshControlStorage)

- (GHLegacyRefreshControl *)gh_legacyRefreshControl {
    return objc_getAssociatedObject(self, kGHLegacyRefreshControlKey);
}

- (void)setGh_legacyRefreshControl:(GHLegacyRefreshControl *)control {
    objc_setAssociatedObject(self, kGHLegacyRefreshControlKey, control, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)gh_forwardScrollViewDidScroll {
    [[self gh_legacyRefreshControl] gh_scrollViewDidScroll];
}

- (void)gh_forwardScrollViewDidEndDragging {
    [[self gh_legacyRefreshControl] gh_scrollViewDidEndDragging];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self gh_forwardScrollViewDidScroll];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [self gh_forwardScrollViewDidEndDragging];
}

@end
