
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

static BOOL GHParseDigits(const char *text, int count, int *value) {
    int result = 0;
    for (int i = 0; i < count; i++) {
        if (text[i] < '0' || text[i] > '9') return NO;
        result = result * 10 + (text[i] - '0');
    }
    *value = result;
    return YES;
}

NSDate *GHDateFromISO8601String(NSString *isoString) {
    if (![isoString isKindOfClass:[NSString class]] || isoString.length != 20) return nil;
    char text[21];
    if (![isoString getCString:text maxLength:sizeof(text) encoding:NSASCIIStringEncoding]) return nil;
    if (text[4] != '-' || text[7] != '-' || text[10] != 'T' || text[13] != ':' || text[16] != ':' || text[19] != 'Z') return nil;

    int year, month, day, hour, minute, second;
    if (!GHParseDigits(text, 4, &year) || !GHParseDigits(text + 5, 2, &month) || !GHParseDigits(text + 8, 2, &day) ||
        !GHParseDigits(text + 11, 2, &hour) || !GHParseDigits(text + 14, 2, &minute) || !GHParseDigits(text + 17, 2, &second)) {
        return nil;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) return nil;

    struct tm components;
    memset(&components, 0, sizeof(components));
    components.tm_year = year - 1900;
    components.tm_mon = month - 1;
    components.tm_mday = day;
    components.tm_hour = hour;
    components.tm_min = minute;
    components.tm_sec = second;
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timegm(&components)];
}

CGSize GHCachedTextSize(NSString *text, UIFont *font, CGSize constraint, NSLineBreakMode lineBreakMode) {
    if (text == nil || font == nil) return CGSizeZero;

    static NSCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 1500;
    });

    NSString *key = [NSString stringWithFormat:@"%@|%.1f|%.1f|%.1f|%ld|%@",
                     font.fontName, font.pointSize, constraint.width, constraint.height, (long)lineBreakMode, text];
    NSValue *cached = [cache objectForKey:key];
    if (cached) return [cached CGSizeValue];

    CGSize size = [text sizeWithFont:font constrainedToSize:constraint lineBreakMode:lineBreakMode];
    [cache setObject:[NSValue valueWithCGSize:size] forKey:key];
    return size;
}

UIImage *GHDecodedImageWithData(NSData *data) {
    if (data.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:data];
    CGImageRef cgImage = image.CGImage;
    if (cgImage == NULL) return image;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0 || width * height > 2048 * 2048) return image;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) return image;

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGImageRef decoded = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (decoded == NULL) return image;

    UIImage *result = [UIImage imageWithCGImage:decoded scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(decoded);
    return result;
}

void GHDecodeImageDataAsync(NSData *data, void (^completion)(UIImage *image)) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        UIImage *image = GHDecodedImageWithData(data);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(image);
        });
    });
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
