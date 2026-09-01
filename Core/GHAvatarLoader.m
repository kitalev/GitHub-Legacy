#import "GHAvatarLoader.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

static void * const kGHAvatarURLAssociationKey = (void *)&kGHAvatarURLAssociationKey;

static CGFloat const kGHAvatarDiameter = 30.0;

@interface GHAvatarLoader ()
@property (nonatomic, strong) NSCache *imageCache;
@end

@implementation GHAvatarLoader

+ (instancetype)sharedLoader {
    static GHAvatarLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHAvatarLoader alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _imageCache = [[NSCache alloc] init];
        _imageCache.countLimit = 300;
    }
    return self;
}

- (UIImage *)circularAvatarFromImage:(UIImage *)sourceImage {
    CGRect rect = CGRectMake(0, 0, kGHAvatarDiameter, kGHAvatarDiameter);

    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextAddEllipseInRect(context, rect);
    CGContextClip(context);

    CGSize sourceSize = sourceImage.size;
    if (sourceSize.width > 0 && sourceSize.height > 0) {
        CGFloat scale = MAX(rect.size.width / sourceSize.width, rect.size.height / sourceSize.height);
        CGSize drawSize = CGSizeMake(sourceSize.width * scale, sourceSize.height * scale);
        CGRect drawRect = CGRectMake((rect.size.width - drawSize.width) / 2.0,
                                     (rect.size.height - drawSize.height) / 2.0,
                                     drawSize.width, drawSize.height);
        [sourceImage drawInRect:drawRect];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)styleAvatarImageView:(UIImageView *)imageView {
    imageView.contentMode = UIViewContentModeCenter;
    imageView.clipsToBounds = YES;
}

- (UIImage *)placeholderAvatarImage {
    static UIImage *placeholder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect rect = CGRectMake(0, 0, kGHAvatarDiameter, kGHAvatarDiameter);
        UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);

        placeholder = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return placeholder;
}

- (void)loadAvatarWithURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView {
    [self loadAvatarWithURLString:urlString intoImageView:imageView completion:nil];
}

- (void)loadAvatarWithURLString:(NSString *)urlString intoImageView:(UIImageView *)imageView completion:(void (^)(void))completion {
    [self styleAvatarImageView:imageView];

    objc_setAssociatedObject(imageView, kGHAvatarURLAssociationKey, urlString, OBJC_ASSOCIATION_COPY_NONATOMIC);

    if (urlString.length == 0) {

        imageView.image = nil;
        return;
    }

    UIImage *cached = [self.imageCache objectForKey:urlString];
    if (cached) {
        imageView.image = cached;

        return;
    }

    imageView.image = [self placeholderAvatarImage];

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;

    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    __weak typeof(self) weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || connectionError || data.length == 0) return;

        UIImage *rawImage = [UIImage imageWithData:data];
        if (!rawImage) return;

        UIImage *circularImage = [strongSelf circularAvatarFromImage:rawImage];
        if (!circularImage) return;

        [strongSelf.imageCache setObject:circularImage forKey:urlString];

        NSString *currentURL = objc_getAssociatedObject(imageView, kGHAvatarURLAssociationKey);
        if ([currentURL isEqualToString:urlString]) {

            imageView.image = circularImage;
            [strongSelf nudgeLayoutForImageView:imageView];
        }

        if (completion) completion();
    }];
}

- (void)nudgeLayoutForImageView:(UIImageView *)imageView {
    UIView *ancestor = imageView.superview;
    while (ancestor && ![ancestor isKindOfClass:[UITableViewCell class]]) {
        ancestor = ancestor.superview;
    }
    if (!ancestor) return;

    [ancestor setNeedsLayout];
    [ancestor layoutIfNeeded];
}

@end
