#import "GHIconRenderer.h"
#import <math.h>

@implementation GHIconRenderer

+ (UIImage *)gearIconWithColor:(UIColor *)color size:(CGFloat)size {
    CGRect canvas = CGRectMake(0, 0, size, size);

    UIGraphicsBeginImageContextWithOptions(canvas.size, NO, 0.0);

    CGPoint center = CGPointMake(size / 2.0, size / 2.0);

    NSInteger teeth = 8;
    CGFloat power = 2.4;
    NSInteger segments = 240;

    CGFloat baseRadius = size * 0.3855;
    CGFloat amplitude = size * 0.0483;
    CGFloat lineWidth = size * 0.0740;
    CGFloat holeRadius = size * 0.1395;

    UIBezierPath *gearPath = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i <= segments; i++) {
        CGFloat theta = (2.0 * M_PI * i) / segments;
        CGFloat c = cos(teeth * theta);
        CGFloat shaped = copysign(pow(fabs(c), 1.0 / power), c);
        CGFloat r = baseRadius + amplitude * shaped;
        CGPoint point = CGPointMake(center.x + r * cos(theta), center.y + r * sin(theta));
        if (i == 0) {
            [gearPath moveToPoint:point];
        } else {
            [gearPath addLineToPoint:point];
        }
    }
    [gearPath closePath];

    gearPath.lineWidth = lineWidth;
    gearPath.lineJoinStyle = kCGLineJoinRound;
    gearPath.lineCapStyle = kCGLineCapRound;

    UIBezierPath *holePath = [UIBezierPath bezierPathWithArcCenter:center
                                                              radius:holeRadius
                                                          startAngle:0
                                                            endAngle:2.0 * M_PI
                                                           clockwise:YES];
    holePath.lineWidth = lineWidth;

    [color setStroke];
    [gearPath stroke];
    [holePath stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)disclosureChevronWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);

    CGFloat lineWidth = MAX(size.width, size.height) * 0.14;
    CGFloat inset = lineWidth;

    UIBezierPath *chevron = [UIBezierPath bezierPath];
    [chevron moveToPoint:CGPointMake(inset, inset)];
    [chevron addLineToPoint:CGPointMake(size.width - inset, size.height / 2.0)];
    [chevron addLineToPoint:CGPointMake(inset, size.height - inset)];

    chevron.lineWidth = lineWidth;
    chevron.lineJoinStyle = kCGLineJoinRound;
    chevron.lineCapStyle = kCGLineCapRound;

    [color setStroke];
    [chevron stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)personIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    CGFloat headRadius = size * 0.16;
    CGPoint headCenter = CGPointMake(size / 2.0, size * 0.28);
    UIBezierPath *head = [UIBezierPath bezierPathWithArcCenter:headCenter
                                                          radius:headRadius
                                                      startAngle:0
                                                        endAngle:2.0 * M_PI
                                                       clockwise:YES];
    [color setFill];
    [head fill];

    CGRect bodyRect = CGRectMake(size * 0.18, size * 0.48, size * 0.64, size * 0.62);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:bodyRect cornerRadius:bodyRect.size.width / 2.0];
    [body fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)starIconWithColor:(UIColor *)color size:(CGFloat)size filled:(BOOL)filled {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    CGPoint center = CGPointMake(size / 2.0, size / 2.0);
    CGFloat outerRadius = size * 0.48;
    CGFloat innerRadius = outerRadius * 0.42;
    NSInteger points = 5;

    UIBezierPath *star = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i < points * 2; i++) {
        CGFloat radius = (i % 2 == 0) ? outerRadius : innerRadius;
        CGFloat angle = (M_PI / points) * i - M_PI_2;
        CGPoint point = CGPointMake(center.x + radius * cos(angle), center.y + radius * sin(angle));
        if (i == 0) {
            [star moveToPoint:point];
        } else {
            [star addLineToPoint:point];
        }
    }
    [star closePath];

    if (filled) {
        [color setFill];
        [star fill];
    } else {
        star.lineWidth = size * 0.06;
        star.lineJoinStyle = kCGLineJoinRound;
        [color setStroke];
        [star stroke];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)compassIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    CGPoint center = CGPointMake(size / 2.0, size / 2.0);
    CGFloat radius = size * 0.42;
    CGFloat lineWidth = size * 0.07;

    UIBezierPath *circle = [UIBezierPath bezierPathWithArcCenter:center
                                                            radius:radius
                                                        startAngle:0
                                                          endAngle:2.0 * M_PI
                                                         clockwise:YES];
    circle.lineWidth = lineWidth;
    [color setStroke];
    [circle stroke];

    CGFloat needleLength = radius * 1.15;
    CGFloat needleWidth = radius * 0.34;
    UIBezierPath *needle = [UIBezierPath bezierPath];
    [needle moveToPoint:CGPointMake(center.x - needleLength * 0.5, center.y + needleLength * 0.5)];
    [needle addLineToPoint:CGPointMake(center.x - needleWidth * 0.3, center.y - needleWidth * 0.3)];
    [needle addLineToPoint:CGPointMake(center.x + needleLength * 0.5, center.y - needleLength * 0.5)];
    [needle addLineToPoint:CGPointMake(center.x + needleWidth * 0.3, center.y + needleWidth * 0.3)];
    [needle closePath];
    [color setFill];
    [needle fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)searchIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    CGFloat lineWidth = size * 0.09;
    CGFloat glassRadius = size * 0.30;
    CGPoint glassCenter = CGPointMake(size * 0.42, size * 0.42);

    UIBezierPath *glass = [UIBezierPath bezierPathWithArcCenter:glassCenter
                                                           radius:glassRadius
                                                       startAngle:0
                                                         endAngle:2.0 * M_PI
                                                        clockwise:YES];
    glass.lineWidth = lineWidth;
    [color setStroke];
    [glass stroke];

    CGFloat handleStart = glassRadius + lineWidth * 0.5;
    CGPoint handleFrom = CGPointMake(glassCenter.x + handleStart * cos(M_PI_4),
                                      glassCenter.y + handleStart * sin(M_PI_4));
    CGPoint handleTo = CGPointMake(size * 0.92, size * 0.92);

    UIBezierPath *handle = [UIBezierPath bezierPath];
    [handle moveToPoint:handleFrom];
    [handle addLineToPoint:handleTo];
    handle.lineWidth = lineWidth;
    handle.lineCapStyle = kCGLineCapRound;
    [color setStroke];
    [handle stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)chevronUpIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    UIBezierPath *arrow = [UIBezierPath bezierPath];

    CGFloat headTopY = size * 0.10;
    CGFloat headBaseY = size * 0.54;
    CGFloat headHalfWidth = size * 0.34;
    CGPoint apex = CGPointMake(size / 2.0, headTopY);
    CGPoint leftBase = CGPointMake(size / 2.0 - headHalfWidth, headBaseY);
    CGPoint rightBase = CGPointMake(size / 2.0 + headHalfWidth, headBaseY);
    [arrow moveToPoint:apex];
    [arrow addLineToPoint:rightBase];
    [arrow addLineToPoint:leftBase];
    [arrow closePath];
    arrow.lineJoinStyle = kCGLineJoinRound;

    CGFloat stemWidth = size * 0.22;
    CGFloat stemTop = headBaseY - size * 0.06;
    CGFloat stemBottom = size * 0.90;
    CGRect stemRect = CGRectMake(size / 2.0 - stemWidth / 2.0, stemTop, stemWidth, stemBottom - stemTop);
    UIBezierPath *stem = [UIBezierPath bezierPathWithRoundedRect:stemRect cornerRadius:stemWidth * 0.3];
    [arrow appendPath:stem];

    [color setFill];
    [arrow fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)filledCircleWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGRect ovalRect = CGRectMake(0, 0, size, size);
    UIBezierPath *oval = [UIBezierPath bezierPathWithOvalInRect:ovalRect];
    CGContextAddPath(ctx, oval.CGPath);
    CGContextClip(ctx);

    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    CGFloat topComponents[4] = {MIN(r * 1.18, 1.0), MIN(g * 1.18, 1.0), MIN(b * 1.18, 1.0), a};
    CGFloat bottomComponents[4] = {r * 0.82, g * 0.82, b * 0.82, a};

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[2] = {0.0, 1.0};
    CGFloat allComponents[8];
    memcpy(allComponents, topComponents, sizeof(topComponents));
    memcpy(allComponents + 4, bottomComponents, sizeof(bottomComponents));
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, allComponents, locations, 2);

    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(size / 2.0, 0), CGPointMake(size / 2.0, size), 0);

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    [[UIColor colorWithWhite:1.0 alpha:0.25] setStroke];
    UIBezierPath *rim = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(ovalRect, 0.75, 0.75)];
    rim.lineWidth = 1.0;
    [rim stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)dotIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)smileyIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [color setStroke];
    [color setFill];

    CGFloat lineWidth = MAX(1.0, size / 16.0);
    CGFloat inset = lineWidth / 2.0 + 1.0;
    CGRect circleRect = CGRectInset(CGRectMake(0, 0, size, size), inset, inset);

    UIBezierPath *outerCircle = [UIBezierPath bezierPathWithOvalInRect:circleRect];
    outerCircle.lineWidth = lineWidth;
    [outerCircle stroke];

    CGFloat eyeRadius = MAX(1.0, size / 16.0);
    CGFloat eyeY = size * 0.40;
    CGFloat leftEyeX = size * 0.36;
    CGFloat rightEyeX = size * 0.64;
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(leftEyeX - eyeRadius, eyeY - eyeRadius, eyeRadius * 2, eyeRadius * 2)] fill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(rightEyeX - eyeRadius, eyeY - eyeRadius, eyeRadius * 2, eyeRadius * 2)] fill];

    CGFloat mouthRadius = size * 0.22;
    CGPoint mouthCenter = CGPointMake(size / 2.0, size * 0.46);
    UIBezierPath *mouth = [UIBezierPath bezierPathWithArcCenter:mouthCenter
                                                           radius:mouthRadius
                                                       startAngle:20.0 * M_PI / 180.0
                                                         endAngle:160.0 * M_PI / 180.0
                                                        clockwise:YES];
    mouth.lineWidth = lineWidth;
    mouth.lineCapStyle = kCGLineCapRound;
    [mouth stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)issueLabelBadgeWithText:(NSString *)text
                       backgroundColor:(UIColor *)backgroundColor
                             textColor:(UIColor *)textColor
                             pointSize:(CGFloat)pointSize {
    UIFont *font = [UIFont boldSystemFontOfSize:pointSize];

    CGSize textSize = [text sizeWithFont:font];

    CGFloat horizontalPadding = 7.0;
    CGFloat verticalPadding = 3.0;
    CGSize badgeSize = CGSizeMake(textSize.width + horizontalPadding * 2,
                                   textSize.height + verticalPadding * 2);

    UIGraphicsBeginImageContextWithOptions(badgeSize, NO, 0.0);

    UIBezierPath *background = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, badgeSize.width, badgeSize.height)
                                                             cornerRadius:badgeSize.height / 2.0];
    [backgroundColor setFill];
    [background fill];

    [textColor setFill];
    [text drawAtPoint:CGPointMake(horizontalPadding, verticalPadding) withFont:font];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIColor *)colorFromHexString:(NSString *)hex {
    if (hex.length != 6) return nil;

    static NSCharacterSet *nonHex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableCharacterSet *hexSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
        nonHex = [hexSet invertedSet];
    });
    if ([hex rangeOfCharacterFromSet:nonHex].location != NSNotFound) return nil;

    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&value]) return nil;

    CGFloat r = ((value >> 16) & 0xFF) / 255.0;
    CGFloat g = ((value >> 8) & 0xFF) / 255.0;
    CGFloat b = (value & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

+ (UIColor *)readableTextColorOverColor:(UIColor *)backgroundColor {
    if (!backgroundColor) return [UIColor blackColor];

    CGFloat r = 0, g = 0, b = 0, a = 0;
    [backgroundColor getRed:&r green:&g blue:&b alpha:&a];
    CGFloat luma = (0.299 * r) + (0.587 * g) + (0.114 * b);
    return luma > 0.6 ? [UIColor blackColor] : [UIColor whiteColor];
}

@end
