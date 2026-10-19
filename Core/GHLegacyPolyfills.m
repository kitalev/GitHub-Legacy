#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void GHAddMethod(Class cls, SEL selector, IMP implementation, const char *types) {
    if (cls == Nil || class_getInstanceMethod(cls, selector) != NULL) return;
    class_addMethod(cls, selector, implementation, types);
}

static void GHAddClassMethod(Class cls, SEL selector, IMP implementation, const char *types) {
    if (cls == Nil) return;
    GHAddMethod(object_getClass(cls), selector, implementation, types);
}

static IMP GHSwizzle(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) return NULL;
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(method, replacement);
    }
    return original;
}

static void GHAfterDelay(NSTimeInterval delay, void (^block)(void)) {
    if (block == nil) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

static void GHNoop(id self, SEL _cmd) {
}

static void GHNoopObject(id self, SEL _cmd, id value) {
}

static void GHNoopObjectInteger(id self, SEL _cmd, id value, NSInteger state) {
}

static void GHNoopObjectIntegerInteger(id self, SEL _cmd, id value, NSInteger first, NSInteger second) {
}

static void GHNoopObjectIntegerIntegerInteger(id self, SEL _cmd, id value, NSInteger first, NSInteger second, NSInteger third) {
}

static id GHNilGetter(id self, SEL _cmd) {
    return nil;
}

static id GHNilGetterInteger(id self, SEL _cmd, NSInteger state) {
    return nil;
}

static BOOL GHNoGetter(id self, SEL _cmd) {
    return NO;
}

#pragma mark - Appearance

@interface GHNullAppearanceProxy : NSObject {
    Class _targetClass;
}
@end

@implementation GHNullAppearanceProxy

- (id)initWithTargetClass:(Class)cls {
    if ((self = [super init])) {
        _targetClass = cls;
    }
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    NSMethodSignature *signature = [_targetClass instanceMethodSignatureForSelector:selector];
    return signature ?: [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
}

@end

static id GHAppearance(id self, SEL _cmd) {
    return [[[GHNullAppearanceProxy alloc] initWithTargetClass:self] autorelease];
}

static id GHAppearanceWhenContainedIn(id self, SEL _cmd, Class container, ...) {
    return GHAppearance(self, _cmd);
}

#pragma mark - UIViewController presentation

static char kGHBeingDismissedKey;
static char kGHMovingFromParentKey;

static void GHSetFlag(id object, const void *key, BOOL value) {
    objc_setAssociatedObject(object, key, value ? [NSNumber numberWithBool:YES] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL GHFlag(id object, const void *key) {
    return [objc_getAssociatedObject(object, key) boolValue];
}

static void GHPresentViewController(UIViewController *self, SEL _cmd, UIViewController *controller, BOOL animated, void (^completion)(void)) {
    [self presentModalViewController:controller animated:animated];
    GHAfterDelay(animated ? 0.45 : 0.0, completion);
}

static void GHDismissViewController(UIViewController *self, SEL _cmd, BOOL animated, void (^completion)(void)) {
    UIViewController *target = self.modalViewController;
    if (target == nil) {
        target = self;
        while (target.parentViewController != nil && target.parentViewController.modalViewController != target) {
            target = target.parentViewController;
        }
    }
    GHSetFlag(target, &kGHBeingDismissedKey, YES);
    [target retain];
    [self dismissModalViewControllerAnimated:animated];
    GHAfterDelay(animated ? 0.45 : 0.0, ^{
        GHSetFlag(target, &kGHBeingDismissedKey, NO);
        [target release];
        if (completion) completion();
    });
}

static UIViewController *GHPresentingViewController(UIViewController *self, SEL _cmd) {
    for (UIViewController *controller = self; controller != nil; controller = controller.parentViewController) {
        UIViewController *parent = controller.parentViewController;
        if (parent != nil && parent.modalViewController == controller) return parent;
    }
    return nil;
}

static UIViewController *GHPresentedViewController(UIViewController *self, SEL _cmd) {
    if (self.modalViewController) return self.modalViewController;
    if (self.navigationController.modalViewController) return self.navigationController.modalViewController;
    return self.tabBarController.modalViewController;
}

static BOOL GHIsBeingDismissed(UIViewController *self, SEL _cmd) {
    return GHFlag(self, &kGHBeingDismissedKey);
}

static BOOL GHIsMovingFromParentViewController(UIViewController *self, SEL _cmd) {
    if (GHFlag(self, &kGHMovingFromParentKey)) return YES;
    UINavigationController *navigationController = self.navigationController;
    return navigationController != nil && ![navigationController.viewControllers containsObject:self];
}

static IMP gGHOrigPop;
static IMP gGHOrigPopTo;
static IMP gGHOrigPopToRoot;
static IMP gGHOrigPush;

static void GHMarkPopped(NSArray *controllers) {
    for (UIViewController *controller in controllers) {
        GHSetFlag(controller, &kGHMovingFromParentKey, YES);
    }
}

static UIViewController *GHPop(UINavigationController *self, SEL _cmd, BOOL animated) {
    if (self.viewControllers.count > 1) GHMarkPopped([NSArray arrayWithObject:self.topViewController]);
    return ((UIViewController *(*)(id, SEL, BOOL))gGHOrigPop)(self, _cmd, animated);
}

static NSArray *GHPopTo(UINavigationController *self, SEL _cmd, UIViewController *controller, BOOL animated) {
    NSArray *stack = self.viewControllers;
    NSUInteger index = [stack indexOfObject:controller];
    if (index != NSNotFound && index + 1 < stack.count) {
        GHMarkPopped([stack subarrayWithRange:NSMakeRange(index + 1, stack.count - index - 1)]);
    }
    return ((NSArray *(*)(id, SEL, UIViewController *, BOOL))gGHOrigPopTo)(self, _cmd, controller, animated);
}

static NSArray *GHPopToRoot(UINavigationController *self, SEL _cmd, BOOL animated) {
    NSArray *stack = self.viewControllers;
    if (stack.count > 1) GHMarkPopped([stack subarrayWithRange:NSMakeRange(1, stack.count - 1)]);
    return ((NSArray *(*)(id, SEL, BOOL))gGHOrigPopToRoot)(self, _cmd, animated);
}

static void GHPush(UINavigationController *self, SEL _cmd, UIViewController *controller, BOOL animated) {
    GHSetFlag(controller, &kGHMovingFromParentKey, NO);
    ((void (*)(id, SEL, UIViewController *, BOOL))gGHOrigPush)(self, _cmd, controller, animated);
}

#pragma mark - View controller layout callbacks

static IMP gGHOrigLayoutSublayers;

static void GHLayoutSublayersOfLayer(UIView *self, SEL _cmd, CALayer *layer) {
    UIViewController *controller = nil;
    if (layer == self.layer) {
        id next = [self nextResponder];
        if ([next isKindOfClass:[UIViewController class]] && [next isViewLoaded] && [next view] == self) {
            controller = next;
        }
    }
    [controller viewWillLayoutSubviews];
    ((void (*)(id, SEL, CALayer *))gGHOrigLayoutSublayers)(self, _cmd, layer);
    [controller viewDidLayoutSubviews];
}

#pragma mark - UINavigationItem multiple items

@interface GHLegacyBarItemsToolbar : UIToolbar
@end

@implementation GHLegacyBarItemsToolbar

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    for (UIView *view = self.superview; view != nil; view = view.superview) {
        if ([view isKindOfClass:[UINavigationBar class]]) {
            UINavigationBar *bar = (UINavigationBar *)view;
            self.barStyle = bar.barStyle;
            self.tintColor = bar.tintColor;
            break;
        }
    }
}

@end

static char kGHRightItemsKey;
static char kGHLeftItemsKey;

static UIBarButtonItem *GHCombinedBarItem(NSArray *items, UIBarStyle barStyle) {
    if (items.count == 0) return nil;
    if (items.count == 1) return [items objectAtIndex:0];
    CGFloat width = 0;
    for (UIBarButtonItem *item in items) {
        if (item.customView == nil && item.style == UIBarButtonItemStylePlain) {
            item.style = UIBarButtonItemStyleBordered;
        }
        if (item.customView != nil) {
            width += item.customView.bounds.size.width + 10;
        } else if (item.width > 0) {
            width += item.width + 10;
        } else if (item.title.length > 0) {
            width += [item.title sizeWithFont:[UIFont boldSystemFontOfSize:12]].width + 30;
        } else {
            width += 44;
        }
    }
    GHLegacyBarItemsToolbar *toolbar = [[GHLegacyBarItemsToolbar alloc] initWithFrame:CGRectMake(0, 0, width, 44)];
    toolbar.barStyle = barStyle;
    toolbar.items = items;
    UIBarButtonItem *container = [[UIBarButtonItem alloc] initWithCustomView:toolbar];
    [toolbar release];
    return [container autorelease];
}

static void GHSetRightItemsAnimated(UINavigationItem *self, SEL _cmd, NSArray *items, BOOL animated) {
    objc_setAssociatedObject(self, &kGHRightItemsKey, items, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self setRightBarButtonItem:GHCombinedBarItem(items, UIBarStyleDefault) animated:animated];
}

static void GHSetRightItems(UINavigationItem *self, SEL _cmd, NSArray *items) {
    GHSetRightItemsAnimated(self, _cmd, items, NO);
}

static NSArray *GHRightItems(UINavigationItem *self, SEL _cmd) {
    NSArray *items = objc_getAssociatedObject(self, &kGHRightItemsKey);
    if (items.count > 0) return items;
    return self.rightBarButtonItem ? [NSArray arrayWithObject:self.rightBarButtonItem] : nil;
}

static void GHSetLeftItemsAnimated(UINavigationItem *self, SEL _cmd, NSArray *items, BOOL animated) {
    objc_setAssociatedObject(self, &kGHLeftItemsKey, items, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self setLeftBarButtonItem:GHCombinedBarItem(items, UIBarStyleDefault) animated:animated];
}

static void GHSetLeftItems(UINavigationItem *self, SEL _cmd, NSArray *items) {
    GHSetLeftItemsAnimated(self, _cmd, items, NO);
}

static NSArray *GHLeftItems(UINavigationItem *self, SEL _cmd) {
    NSArray *items = objc_getAssociatedObject(self, &kGHLeftItemsKey);
    if (items.count > 0) return items;
    return self.leftBarButtonItem ? [NSArray arrayWithObject:self.leftBarButtonItem] : nil;
}

#pragma mark - UIKit helpers

static UIScrollView *GHWebViewScrollView(UIWebView *self, SEL _cmd) {
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:[UIScrollView class]]) return (UIScrollView *)subview;
    }
    return nil;
}

static UIImage *GHResizableImage(UIImage *self, SEL _cmd, UIEdgeInsets insets) {
    return [self stretchableImageWithLeftCapWidth:(NSInteger)insets.left topCapHeight:(NSInteger)insets.top];
}

static BOOL GHColorGetRGBA(UIColor *self, SEL _cmd, CGFloat *red, CGFloat *green, CGFloat *blue, CGFloat *alpha) {
    CGColorRef color = self.CGColor;
    const CGFloat *components = CGColorGetComponents(color);
    CGColorSpaceModel model = CGColorSpaceGetModel(CGColorGetColorSpace(color));
    CGFloat r, g, b, a;
    if (model == kCGColorSpaceModelMonochrome) {
        r = g = b = components[0];
        a = components[1];
    } else if (model == kCGColorSpaceModelRGB) {
        r = components[0];
        g = components[1];
        b = components[2];
        a = components[3];
    } else {
        return NO;
    }
    if (red) *red = r;
    if (green) *green = g;
    if (blue) *blue = b;
    if (alpha) *alpha = a;
    return YES;
}

#pragma mark - Foundation

static void GHSendAsynchronousRequest(id self, SEL _cmd, NSURLRequest *request, NSOperationQueue *queue,
                                      void (^handler)(NSURLResponse *, NSData *, NSError *)) {
    NSURLRequest *requestCopy = [request copy];
    void (^handlerCopy)(NSURLResponse *, NSData *, NSError *) = [handler copy];
    NSOperationQueue *targetQueue = [(queue ?: [NSOperationQueue mainQueue]) retain];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSURLResponse *response = nil;
        NSError *error = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:requestCopy returningResponse:&response error:&error];
        if (handlerCopy) {
            [targetQueue addOperationWithBlock:^{
                handlerCopy(response, data, error);
            }];
        }
        [requestCopy release];
        [handlerCopy release];
        [targetQueue release];
        [pool drain];
    });
}

static id GHHTTPResponseInit(NSHTTPURLResponse *self, SEL _cmd, NSURL *url, NSInteger statusCode, NSString *version, NSDictionary *headers) {
    SEL legacy = sel_registerName("initWithURL:statusCode:headerFields:requestTime:");
    if ([self respondsToSelector:legacy]) {
        return ((id (*)(id, SEL, NSURL *, NSInteger, NSDictionary *, double))objc_msgSend)(self, legacy, url, statusCode, headers, 0.0);
    }
    [self release];
    return nil;
}

#pragma mark - Installation

@interface GHLegacyPolyfills : NSObject
@end

@implementation GHLegacyPolyfills

+ (void)load {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    Class viewController = [UIViewController class];
    BOOL nativeLayoutCallbacks = [viewController instancesRespondToSelector:@selector(viewDidLayoutSubviews)];
    BOOL nativeMovingState = [viewController instancesRespondToSelector:@selector(isMovingFromParentViewController)];

    GHAddClassMethod([UIView class], @selector(appearance), (IMP)GHAppearance, "@@:");
    GHAddClassMethod([UIView class], @selector(appearanceWhenContainedIn:), (IMP)GHAppearanceWhenContainedIn, "@@:#");

    GHAddMethod(viewController, @selector(presentViewController:animated:completion:), (IMP)GHPresentViewController, "v@:@c@?");
    GHAddMethod(viewController, @selector(dismissViewControllerAnimated:completion:), (IMP)GHDismissViewController, "v@:c@?");
    GHAddMethod(viewController, @selector(presentingViewController), (IMP)GHPresentingViewController, "@@:");
    GHAddMethod(viewController, @selector(presentedViewController), (IMP)GHPresentedViewController, "@@:");
    GHAddMethod(viewController, @selector(isBeingDismissed), (IMP)GHIsBeingDismissed, "c@:");
    GHAddMethod(viewController, @selector(isBeingPresented), (IMP)GHNoGetter, "c@:");
    GHAddMethod(viewController, @selector(isMovingFromParentViewController), (IMP)GHIsMovingFromParentViewController, "c@:");
    GHAddMethod(viewController, @selector(isMovingToParentViewController), (IMP)GHNoGetter, "c@:");
    GHAddMethod(viewController, @selector(viewWillLayoutSubviews), (IMP)GHNoop, "v@:");
    GHAddMethod(viewController, @selector(viewDidLayoutSubviews), (IMP)GHNoop, "v@:");

    if (!nativeMovingState) {
        Class navigationController = [UINavigationController class];
        gGHOrigPop = GHSwizzle(navigationController, @selector(popViewControllerAnimated:), (IMP)GHPop);
        gGHOrigPopTo = GHSwizzle(navigationController, @selector(popToViewController:animated:), (IMP)GHPopTo);
        gGHOrigPopToRoot = GHSwizzle(navigationController, @selector(popToRootViewControllerAnimated:), (IMP)GHPopToRoot);
        gGHOrigPush = GHSwizzle(navigationController, @selector(pushViewController:animated:), (IMP)GHPush);
    }

    if (!nativeLayoutCallbacks) {
        gGHOrigLayoutSublayers = GHSwizzle([UIView class], @selector(layoutSublayersOfLayer:), (IMP)GHLayoutSublayersOfLayer);
    }

    Class navigationItem = [UINavigationItem class];
    GHAddMethod(navigationItem, @selector(setRightBarButtonItems:animated:), (IMP)GHSetRightItemsAnimated, "v@:@c");
    GHAddMethod(navigationItem, @selector(setRightBarButtonItems:), (IMP)GHSetRightItems, "v@:@");
    GHAddMethod(navigationItem, @selector(rightBarButtonItems), (IMP)GHRightItems, "@@:");
    GHAddMethod(navigationItem, @selector(setLeftBarButtonItems:animated:), (IMP)GHSetLeftItemsAnimated, "v@:@c");
    GHAddMethod(navigationItem, @selector(setLeftBarButtonItems:), (IMP)GHSetLeftItems, "v@:@");
    GHAddMethod(navigationItem, @selector(leftBarButtonItems), (IMP)GHLeftItems, "@@:");

    GHAddMethod([UIWebView class], @selector(scrollView), (IMP)GHWebViewScrollView, "@@:");
    GHAddMethod([UIImage class], @selector(resizableImageWithCapInsets:), (IMP)GHResizableImage, "@@:{UIEdgeInsets=ffff}");
    GHAddMethod([UIColor class], @selector(getRed:green:blue:alpha:), (IMP)GHColorGetRGBA, "c@:^f^f^f^f");

    Class navigationBar = [UINavigationBar class];
    GHAddMethod(navigationBar, @selector(setTitleTextAttributes:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(navigationBar, @selector(titleTextAttributes), (IMP)GHNilGetter, "@@:");
    GHAddMethod(navigationBar, @selector(setBackgroundImage:forBarMetrics:), (IMP)GHNoopObjectInteger, "v@:@i");
    GHAddMethod(navigationBar, @selector(backgroundImageForBarMetrics:), (IMP)GHNilGetterInteger, "@@:i");

    GHAddMethod([UIToolbar class], @selector(setBackgroundImage:forToolbarPosition:barMetrics:), (IMP)GHNoopObjectIntegerInteger, "v@:@ii");

    Class searchBar = [UISearchBar class];
    GHAddMethod(searchBar, @selector(setBackgroundImage:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(searchBar, @selector(backgroundImage), (IMP)GHNilGetter, "@@:");
    GHAddMethod(searchBar, @selector(setScopeBarBackgroundImage:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(searchBar, @selector(scopeBarBackgroundImage), (IMP)GHNilGetter, "@@:");
    GHAddMethod(searchBar, @selector(setSearchFieldBackgroundImage:forState:), (IMP)GHNoopObjectInteger, "v@:@I");
    GHAddMethod(searchBar, @selector(setImage:forSearchBarIcon:state:), (IMP)GHNoopObjectIntegerInteger, "v@:@iI");

    Class barItem = [UIBarItem class];
    GHAddMethod(barItem, @selector(setTitleTextAttributes:forState:), (IMP)GHNoopObjectInteger, "v@:@I");
    GHAddMethod(barItem, @selector(titleTextAttributesForState:), (IMP)GHNilGetterInteger, "@@:I");

    Class barButtonItem = [UIBarButtonItem class];
    GHAddMethod(barButtonItem, @selector(setTintColor:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(barButtonItem, @selector(tintColor), (IMP)GHNilGetter, "@@:");
    GHAddMethod(barButtonItem, @selector(setBackgroundImage:forState:barMetrics:), (IMP)GHNoopObjectIntegerInteger, "v@:@Ii");
    GHAddMethod(barButtonItem, @selector(setBackgroundImage:forState:style:barMetrics:), (IMP)GHNoopObjectIntegerIntegerInteger, "v@:@Iii");

    Class tabBar = [UITabBar class];
    GHAddMethod(tabBar, @selector(setTintColor:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(tabBar, @selector(tintColor), (IMP)GHNilGetter, "@@:");
    GHAddMethod(tabBar, @selector(setSelectedImageTintColor:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(tabBar, @selector(setBackgroundImage:), (IMP)GHNoopObject, "v@:@");
    GHAddMethod(tabBar, @selector(setSelectionIndicatorImage:), (IMP)GHNoopObject, "v@:@");

    GHAddClassMethod([NSURLConnection class], @selector(sendAsynchronousRequest:queue:completionHandler:),
                     (IMP)GHSendAsynchronousRequest, "v@:@@@?");
    GHAddMethod([NSHTTPURLResponse class], @selector(initWithURL:statusCode:HTTPVersion:headerFields:),
                (IMP)GHHTTPResponseInit, "@@:@i@@");

    [pool drain];
}

@end
