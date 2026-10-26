#import "GHLegacyScopeBar.h"

// Geometry and colors are sampled from the stock iOS 5/6 scope bar.
static const CGFloat kScopeHorizontalInset = 5.0;
static const CGFloat kScopeControlHeight = 29.0;
static const CGFloat kScopeCornerRadius = 4.5;

static UIColor *GHHexColor(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:alpha];
}

static void GHFillVerticalGradient(CGContextRef context, CGRect rect, UIColor *top, UIColor *bottom) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[2] = {0.0, 1.0};
    CFArrayRef colors = (__bridge CFArrayRef)@[(__bridge id)top.CGColor, (__bridge id)bottom.CGColor];
    CGGradientRef gradient = CGGradientCreateWithColors(space, colors, locations);
    CGColorSpaceRelease(space);
    if (gradient == NULL) return;
    CGContextSaveGState(context);
    CGContextClipToRect(context, rect);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, CGRectGetMinY(rect)),
                                CGPointMake(0, CGRectGetMaxY(rect)), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
}

@implementation GHLegacyScopeBar

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    }
    return self;
}

- (void)setTitles:(NSArray *)titles {
    _titles = [titles copy];
    if (_selectedIndex >= (NSInteger)_titles.count) _selectedIndex = 0;
    [self setNeedsDisplay];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay];
}

- (void)setDark:(BOOL)dark {
    _dark = dark;
    [self setNeedsDisplay];
}

- (CGRect)controlRect {
    CGFloat height = MIN(kScopeControlHeight, self.bounds.size.height);
    return CGRectMake(kScopeHorizontalInset, floorf((self.bounds.size.height - height) / 2.0),
                      self.bounds.size.width - kScopeHorizontalInset * 2.0, height);
}

- (CGRect)segmentRectAtIndex:(NSInteger)index inRect:(CGRect)control {
    CGFloat width = control.size.width / MAX(self.titles.count, (NSUInteger)1);
    CGFloat x = roundf(control.origin.x + width * index);
    CGFloat nextX = roundf(control.origin.x + width * (index + 1));
    return CGRectMake(x, control.origin.y, nextX - x, control.size.height);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect control = [self controlRect];
    NSUInteger count = self.titles.count;
    if (count == 0 || control.size.width <= 0) return;

    UIColor *normalTop, *normalBottom, *selectedTop, *selectedBottom;
    UIColor *borderTop, *borderBottom, *divider, *emboss;
    UIColor *normalText, *normalShadow, *selectedText, *selectedShadow;
    CGFloat normalShadowY;
    if (self.dark) {
        normalTop = GHHexColor(0x444444, 1.0);
        normalBottom = GHHexColor(0x030303, 1.0);
        selectedTop = GHHexColor(0x616161, 1.0);
        selectedBottom = GHHexColor(0x2F2F2F, 1.0);
        borderTop = GHHexColor(0x000000, 0.8);
        borderBottom = GHHexColor(0x000000, 0.25);
        divider = GHHexColor(0xFFFFFF, 0.15);
        emboss = GHHexColor(0xFFFFFF, 0.25);
        normalText = [UIColor whiteColor];
        normalShadow = GHHexColor(0x000000, 0.6);
        normalShadowY = -1.0;
        selectedText = [UIColor whiteColor];
        selectedShadow = GHHexColor(0x000000, 0.6);
    } else {
        normalTop = GHHexColor(0xD5DCE0, 1.0);
        normalBottom = GHHexColor(0xB4BEC6, 1.0);
        selectedTop = GHHexColor(0x8C9AAF, 1.0);
        selectedBottom = GHHexColor(0x647791, 1.0);
        borderTop = GHHexColor(0x203048, 0.7);
        borderBottom = GHHexColor(0x203048, 0.14);
        divider = GHHexColor(0x203048, 0.55);
        emboss = GHHexColor(0xFFFFFF, 0.25);
        normalText = GHHexColor(0x3F5C84, 1.0);
        normalShadow = GHHexColor(0xFFFFFF, 0.6);
        normalShadowY = 1.0;
        selectedText = [UIColor whiteColor];
        selectedShadow = GHHexColor(0x000000, 0.3);
    }

    CGFloat pixel = 1.0 / MAX([UIScreen mainScreen].scale, 1.0);
    [emboss setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(control, 0, pixel) cornerRadius:kScopeCornerRadius] fill];

    UIBezierPath *shape = [UIBezierPath bezierPathWithRoundedRect:control cornerRadius:kScopeCornerRadius];
    CGContextSaveGState(context);
    [shape addClip];
    GHFillVerticalGradient(context, control, normalTop, normalBottom);
    if (self.selectedIndex >= 0 && self.selectedIndex < (NSInteger)count) {
        GHFillVerticalGradient(context, [self segmentRectAtIndex:self.selectedIndex inRect:control],
                               selectedTop, selectedBottom);
    }
    [divider setFill];
    for (NSUInteger i = 1; i < count; i++) {
        CGRect segment = [self segmentRectAtIndex:i inRect:control];
        UIRectFillUsingBlendMode(CGRectMake(segment.origin.x, control.origin.y, 1.0, control.size.height),
                                 kCGBlendModeNormal);
    }

    // 1pt border, darker at the top than at the bottom like the stock control.
    UIBezierPath *outline = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(control, 0.5, 0.5)
                                                       cornerRadius:kScopeCornerRadius - 0.5];
    CGContextAddPath(context, outline.CGPath);
    CGContextSetLineWidth(context, 1.0);
    CGContextReplacePathWithStrokedPath(context);
    CGContextClip(context);
    GHFillVerticalGradient(context, control, borderTop, borderBottom);
    CGContextRestoreGState(context);

    UIFont *font = [UIFont boldSystemFontOfSize:12];
    for (NSUInteger i = 0; i < count; i++) {
        BOOL selected = (NSInteger)i == self.selectedIndex;
        CGRect segment = CGRectInset([self segmentRectAtIndex:i inRect:control], 4.0, 0);
        CGFloat textHeight = font.lineHeight;
        CGRect textRect = CGRectMake(segment.origin.x, roundf(CGRectGetMidY(segment) - textHeight / 2.0),
                                     segment.size.width, textHeight);
        CGContextSaveGState(context);
        CGContextSetShadowWithColor(context, CGSizeMake(0, selected ? -1.0 : normalShadowY), 0,
                                    (selected ? selectedShadow : normalShadow).CGColor);
        [(selected ? selectedText : normalText) setFill];
        [self.titles[i] drawInRect:textRect
                          withFont:font
                     lineBreakMode:NSLineBreakByTruncatingTail
                         alignment:NSTextAlignmentCenter];
        CGContextRestoreGState(context);
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGPoint point = [touch locationInView:self];
    CGRect control = [self controlRect];
    if (self.titles.count == 0 || !CGRectContainsPoint(CGRectInset(control, 0, -6), point)) return NO;
    NSInteger index = (NSInteger)((point.x - control.origin.x) / (control.size.width / self.titles.count));
    index = MAX(0, MIN(index, (NSInteger)self.titles.count - 1));
    if (index != self.selectedIndex) {
        self.selectedIndex = index;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
    return NO;
}

@end
