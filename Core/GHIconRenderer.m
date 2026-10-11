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

+ (UIImage *)successBadgeWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);

    UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)];
    [color setFill];
    [circle fill];

    UIBezierPath *check = [UIBezierPath bezierPath];
    [check moveToPoint:CGPointMake(size * 0.28, size * 0.52)];
    [check addLineToPoint:CGPointMake(size * 0.44, size * 0.67)];
    [check addLineToPoint:CGPointMake(size * 0.73, size * 0.36)];
    check.lineWidth = size * 0.08;
    check.lineCapStyle = kCGLineCapRound;
    check.lineJoinStyle = kCGLineJoinRound;
    [[UIColor whiteColor] setStroke];
    [check stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)devicesIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [color setStroke];
    [color setFill];

    CGFloat line = MAX(1.5, size * 0.06);

    CGRect screen = CGRectMake(size * 0.06, size * 0.18, size * 0.66, size * 0.46);
    UIBezierPath *monitor = [UIBezierPath bezierPathWithRoundedRect:screen cornerRadius:size * 0.05];
    monitor.lineWidth = line;
    [monitor stroke];

    UIBezierPath *stand = [UIBezierPath bezierPath];
    [stand moveToPoint:CGPointMake(size * 0.39, CGRectGetMaxY(screen))];
    [stand addLineToPoint:CGPointMake(size * 0.39, size * 0.76)];
    [stand moveToPoint:CGPointMake(size * 0.24, size * 0.78)];
    [stand addLineToPoint:CGPointMake(size * 0.54, size * 0.78)];
    stand.lineWidth = line;
    stand.lineCapStyle = kCGLineCapRound;
    [stand stroke];

    CGRect phoneRect = CGRectMake(size * 0.64, size * 0.40, size * 0.30, size * 0.50);
    [[UIColor clearColor] setFill];
    UIBezierPath *phoneBackground = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(phoneRect, -line, -line) cornerRadius:size * 0.07];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    [phoneBackground fill];
    CGContextRestoreGState(ctx);

    UIBezierPath *phone = [UIBezierPath bezierPathWithRoundedRect:phoneRect cornerRadius:size * 0.06];
    phone.lineWidth = line;
    [color setStroke];
    [phone stroke];

    [color setFill];
    UIBezierPath *button = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(CGRectGetMidX(phoneRect) - size * 0.025,
                                                                            CGRectGetMaxY(phoneRect) - size * 0.09,
                                                                            size * 0.05, size * 0.05)];
    [button fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)keyIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [color setStroke];

    CGFloat line = MAX(1.5, size * 0.07);

    CGRect ringRect = CGRectMake(size * 0.10, size * 0.30, size * 0.38, size * 0.38);
    UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:ringRect];
    ring.lineWidth = line;
    [ring stroke];

    UIBezierPath *shaft = [UIBezierPath bezierPath];
    [shaft moveToPoint:CGPointMake(CGRectGetMaxX(ringRect), CGRectGetMidY(ringRect))];
    [shaft addLineToPoint:CGPointMake(size * 0.90, CGRectGetMidY(ringRect))];
    [shaft moveToPoint:CGPointMake(size * 0.78, CGRectGetMidY(ringRect))];
    [shaft addLineToPoint:CGPointMake(size * 0.78, CGRectGetMidY(ringRect) + size * 0.14)];
    [shaft moveToPoint:CGPointMake(size * 0.66, CGRectGetMidY(ringRect))];
    [shaft addLineToPoint:CGPointMake(size * 0.66, CGRectGetMidY(ringRect) + size * 0.10)];
    shaft.lineWidth = line;
    shaft.lineCapStyle = kCGLineCapRound;
    [shaft stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)linkIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, size / 2.0, size / 2.0);
    CGContextRotateCTM(ctx, -M_PI_4);

    CGFloat line = MAX(1.2, size * 0.09);
    CGFloat linkHeight = size * 0.34;
    CGFloat linkWidth = size * 0.52;
    [color setStroke];

    UIBezierPath *left = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-linkWidth + size * 0.06, -linkHeight / 2.0, linkWidth, linkHeight)
                                                    cornerRadius:linkHeight / 2.0];
    left.lineWidth = line;
    [left stroke];

    UIBezierPath *right = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(-size * 0.06, -linkHeight / 2.0, linkWidth, linkHeight)
                                                     cornerRadius:linkHeight / 2.0];
    right.lineWidth = line;
    [right stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)externalLinkIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    CGFloat inset = line / 2.0 + size * 0.06;
    CGFloat top = inset;
    CGFloat right = size - inset;
    CGFloat boxTop = size * 0.24;
    CGFloat boxRight = size * 0.76;
    CGFloat bottom = size - inset;

    UIBezierPath *box = [UIBezierPath bezierPath];
    [box moveToPoint:CGPointMake(size * 0.46, boxTop)];
    [box addLineToPoint:CGPointMake(inset, boxTop)];
    [box addLineToPoint:CGPointMake(inset, bottom)];
    [box addLineToPoint:CGPointMake(boxRight, bottom)];
    [box addLineToPoint:CGPointMake(boxRight, size * 0.54)];

    UIBezierPath *arrow = [UIBezierPath bezierPath];
    [arrow moveToPoint:CGPointMake(size * 0.40, size * 0.60)];
    [arrow addLineToPoint:CGPointMake(right, top)];
    [arrow moveToPoint:CGPointMake(right - size * 0.34, top)];
    [arrow addLineToPoint:CGPointMake(right, top)];
    [arrow addLineToPoint:CGPointMake(right, top + size * 0.34)];

    [color setStroke];
    for (UIBezierPath *path in @[box, arrow]) {
        path.lineWidth = line;
        path.lineCapStyle = kCGLineCapRound;
        path.lineJoinStyle = kCGLineJoinRound;
        [path stroke];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)locationIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    CGPoint center = CGPointMake(size / 2.0, size * 0.40);
    CGFloat radius = size * 0.30;

    UIBezierPath *pin = [UIBezierPath bezierPath];
    [pin addArcWithCenter:center radius:radius startAngle:M_PI * 0.80 endAngle:M_PI * 0.20 clockwise:YES];
    [pin addLineToPoint:CGPointMake(size / 2.0, size * 0.92)];
    [pin closePath];
    pin.lineWidth = line;
    pin.lineJoinStyle = kCGLineJoinRound;
    [color setStroke];
    [pin stroke];

    UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - size * 0.09, center.y - size * 0.09, size * 0.18, size * 0.18)];
    dot.lineWidth = line;
    [dot stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)organizationIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];
    [color setFill];

    UIBezierPath *tower = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(size * 0.14, size * 0.10, size * 0.46, size * 0.80) cornerRadius:size * 0.04];
    tower.lineWidth = line;
    [tower stroke];

    UIBezierPath *wing = [UIBezierPath bezierPath];
    [wing moveToPoint:CGPointMake(size * 0.60, size * 0.40)];
    [wing addLineToPoint:CGPointMake(size * 0.86, size * 0.40)];
    [wing addLineToPoint:CGPointMake(size * 0.86, size * 0.90)];
    [wing addLineToPoint:CGPointMake(size * 0.60, size * 0.90)];
    wing.lineWidth = line;
    wing.lineJoinStyle = kCGLineJoinRound;
    [wing stroke];

    CGFloat window = size * 0.09;
    for (NSInteger row = 0; row < 3; row++) {
        for (NSInteger column = 0; column < 2; column++) {
            CGRect rect = CGRectMake(size * 0.24 + column * size * 0.16, size * 0.22 + row * size * 0.18, window, window);
            [[UIBezierPath bezierPathWithRect:rect] fill];
        }
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)repoIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];
    [color setFill];

    UIBezierPath *book = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(size * 0.20, size * 0.08, size * 0.60, size * 0.70) cornerRadius:size * 0.06];
    book.lineWidth = line;
    [book stroke];

    UIBezierPath *spine = [UIBezierPath bezierPath];
    [spine moveToPoint:CGPointMake(size * 0.20, size * 0.62)];
    [spine addLineToPoint:CGPointMake(size * 0.80, size * 0.62)];
    spine.lineWidth = line;
    [spine stroke];

    UIBezierPath *ribbon = [UIBezierPath bezierPath];
    [ribbon moveToPoint:CGPointMake(size * 0.34, size * 0.70)];
    [ribbon addLineToPoint:CGPointMake(size * 0.34, size * 0.94)];
    [ribbon addLineToPoint:CGPointMake(size * 0.42, size * 0.87)];
    [ribbon addLineToPoint:CGPointMake(size * 0.50, size * 0.94)];
    [ribbon addLineToPoint:CGPointMake(size * 0.50, size * 0.70)];
    [ribbon closePath];
    [ribbon fill];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)pinIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, size / 2.0, size / 2.0);
    CGContextRotateCTM(ctx, M_PI_4);

    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];

    UIBezierPath *head = [UIBezierPath bezierPath];
    [head moveToPoint:CGPointMake(-size * 0.16, -size * 0.42)];
    [head addLineToPoint:CGPointMake(size * 0.16, -size * 0.42)];
    [head addLineToPoint:CGPointMake(size * 0.12, -size * 0.12)];
    [head addLineToPoint:CGPointMake(size * 0.28, size * 0.04)];
    [head addLineToPoint:CGPointMake(-size * 0.28, size * 0.04)];
    [head addLineToPoint:CGPointMake(-size * 0.12, -size * 0.12)];
    [head closePath];
    head.lineWidth = line;
    head.lineJoinStyle = kCGLineJoinRound;
    [head stroke];

    UIBezierPath *needle = [UIBezierPath bezierPath];
    [needle moveToPoint:CGPointMake(0, size * 0.04)];
    [needle addLineToPoint:CGPointMake(0, size * 0.44)];
    needle.lineWidth = line;
    needle.lineCapStyle = kCGLineCapRound;
    [needle stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)mailIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];

    CGRect body = CGRectMake(size * 0.10, size * 0.22, size * 0.80, size * 0.56);
    UIBezierPath *envelope = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:size * 0.06];
    envelope.lineWidth = line;
    [envelope stroke];

    UIBezierPath *flap = [UIBezierPath bezierPath];
    [flap moveToPoint:CGPointMake(CGRectGetMinX(body) + line, CGRectGetMinY(body) + line)];
    [flap addLineToPoint:CGPointMake(size / 2.0, size * 0.54)];
    [flap addLineToPoint:CGPointMake(CGRectGetMaxX(body) - line, CGRectGetMinY(body) + line)];
    flap.lineWidth = line;
    flap.lineJoinStyle = kCGLineJoinRound;
    [flap stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)personOutlineIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];

    UIBezierPath *head = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.32, size * 0.10, size * 0.36, size * 0.36)];
    head.lineWidth = line;
    [head stroke];

    UIBezierPath *body = [UIBezierPath bezierPath];
    [body moveToPoint:CGPointMake(size * 0.14, size * 0.90)];
    [body addCurveToPoint:CGPointMake(size * 0.86, size * 0.90)
            controlPoint1:CGPointMake(size * 0.14, size * 0.52)
            controlPoint2:CGPointMake(size * 0.86, size * 0.52)];
    body.lineWidth = line;
    body.lineCapStyle = kCGLineCapRound;
    [body stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)tileWithIcon:(UIImage *)icon backgroundColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:size * 0.24];
    [color setFill];
    [tile fill];
    if (icon) {
        [icon drawInRect:CGRectMake(floor((size - icon.size.width) / 2.0), floor((size - icon.size.height) / 2.0),
                                    icon.size.width, icon.size.height)];
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static void GHStrokeRing(CGPoint center, CGFloat radius, CGFloat line) {
    UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2)];
    ring.lineWidth = line;
    [ring stroke];
}

static void GHStrokeSegment(CGPoint from, CGPoint to, CGFloat line) {
    UIBezierPath *segment = [UIBezierPath bezierPath];
    [segment moveToPoint:from];
    [segment addLineToPoint:to];
    segment.lineWidth = line;
    segment.lineCapStyle = kCGLineCapRound;
    [segment stroke];
}

+ (UIImage *)issueOpenIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    [color setStroke];
    [color setFill];
    GHStrokeRing(CGPointMake(size / 2.0, size / 2.0), size * 0.40, line);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.40, size * 0.40, size * 0.20, size * 0.20)] fill];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)pullRequestIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];
    [color setFill];

    CGPoint topLeft = CGPointMake(size * 0.26, size * 0.20);
    CGPoint bottomLeft = CGPointMake(size * 0.26, size * 0.80);
    CGPoint bottomRight = CGPointMake(size * 0.74, size * 0.80);
    GHStrokeRing(topLeft, r, line);
    GHStrokeRing(bottomLeft, r, line);
    GHStrokeRing(bottomRight, r, line);
    GHStrokeSegment(CGPointMake(topLeft.x, topLeft.y + r), CGPointMake(bottomLeft.x, bottomLeft.y - r), line);

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(bottomRight.x, bottomRight.y - r)];
    [path addLineToPoint:CGPointMake(bottomRight.x, size * 0.34)];
    [path addQuadCurveToPoint:CGPointMake(size * 0.58, size * 0.20) controlPoint:CGPointMake(bottomRight.x, size * 0.20)];
    [path addLineToPoint:CGPointMake(size * 0.46, size * 0.20)];
    path.lineWidth = line;
    path.lineCapStyle = kCGLineCapRound;
    [path stroke];

    UIBezierPath *arrow = [UIBezierPath bezierPath];
    [arrow moveToPoint:CGPointMake(size * 0.54, size * 0.10)];
    [arrow addLineToPoint:CGPointMake(size * 0.44, size * 0.20)];
    [arrow addLineToPoint:CGPointMake(size * 0.54, size * 0.30)];
    arrow.lineWidth = line;
    arrow.lineCapStyle = kCGLineCapRound;
    arrow.lineJoinStyle = kCGLineJoinRound;
    [arrow stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)tagIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];

    UIBezierPath *tag = [UIBezierPath bezierPath];
    [tag moveToPoint:CGPointMake(size * 0.12, size * 0.14)];
    [tag addLineToPoint:CGPointMake(size * 0.50, size * 0.14)];
    [tag addLineToPoint:CGPointMake(size * 0.88, size * 0.52)];
    [tag addLineToPoint:CGPointMake(size * 0.52, size * 0.88)];
    [tag addLineToPoint:CGPointMake(size * 0.12, size * 0.50)];
    [tag closePath];
    tag.lineWidth = line;
    tag.lineJoinStyle = kCGLineJoinRound;
    [tag stroke];

    GHStrokeRing(CGPointMake(size * 0.32, size * 0.34), size * 0.07, line);

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)moreIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    [color setFill];
    CGFloat dot = size * 0.16;
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat x = size * 0.14 + i * size * 0.28;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x, (size - dot) / 2.0, dot, dot)] fill];
    }
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)codeIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    [color setStroke];

    UIBezierPath *left = [UIBezierPath bezierPath];
    [left moveToPoint:CGPointMake(size * 0.34, size * 0.24)];
    [left addLineToPoint:CGPointMake(size * 0.10, size * 0.50)];
    [left addLineToPoint:CGPointMake(size * 0.34, size * 0.76)];
    left.lineWidth = line;
    left.lineCapStyle = kCGLineCapRound;
    left.lineJoinStyle = kCGLineJoinRound;
    [left stroke];

    UIBezierPath *right = [UIBezierPath bezierPath];
    [right moveToPoint:CGPointMake(size * 0.66, size * 0.24)];
    [right addLineToPoint:CGPointMake(size * 0.90, size * 0.50)];
    [right addLineToPoint:CGPointMake(size * 0.66, size * 0.76)];
    right.lineWidth = line;
    right.lineCapStyle = kCGLineCapRound;
    right.lineJoinStyle = kCGLineJoinRound;
    [right stroke];

    GHStrokeSegment(CGPointMake(size * 0.56, size * 0.16), CGPointMake(size * 0.44, size * 0.84), line);

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)commitIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    CGFloat r = size * 0.18;
    [color setStroke];
    GHStrokeRing(CGPointMake(size / 2.0, size / 2.0), r, line);
    GHStrokeSegment(CGPointMake(size * 0.06, size / 2.0), CGPointMake(size / 2.0 - r, size / 2.0), line);
    GHStrokeSegment(CGPointMake(size / 2.0 + r, size / 2.0), CGPointMake(size * 0.94, size / 2.0), line);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)forkIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];

    CGPoint left = CGPointMake(size * 0.26, size * 0.20);
    CGPoint right = CGPointMake(size * 0.74, size * 0.20);
    CGPoint bottom = CGPointMake(size * 0.50, size * 0.80);
    GHStrokeRing(left, r, line);
    GHStrokeRing(right, r, line);
    GHStrokeRing(bottom, r, line);

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(left.x, left.y + r)];
    [path addQuadCurveToPoint:CGPointMake(size * 0.50, size * 0.52) controlPoint:CGPointMake(left.x, size * 0.52)];
    [path addQuadCurveToPoint:CGPointMake(right.x, right.y + r) controlPoint:CGPointMake(right.x, size * 0.52)];
    [path moveToPoint:CGPointMake(size * 0.50, size * 0.52)];
    [path addLineToPoint:CGPointMake(bottom.x, bottom.y - r)];
    path.lineWidth = line;
    path.lineCapStyle = kCGLineCapRound;
    [path stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)branchIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];

    CGPoint top = CGPointMake(size * 0.28, size * 0.20);
    CGPoint bottom = CGPointMake(size * 0.28, size * 0.80);
    CGPoint side = CGPointMake(size * 0.74, size * 0.26);
    GHStrokeRing(top, r, line);
    GHStrokeRing(bottom, r, line);
    GHStrokeRing(side, r, line);
    GHStrokeSegment(CGPointMake(top.x, top.y + r), CGPointMake(bottom.x, bottom.y - r), line);

    UIBezierPath *curve = [UIBezierPath bezierPath];
    [curve moveToPoint:CGPointMake(side.x, side.y + r)];
    [curve addQuadCurveToPoint:CGPointMake(top.x, size * 0.62) controlPoint:CGPointMake(side.x, size * 0.58)];
    curve.lineWidth = line;
    curve.lineCapStyle = kCGLineCapRound;
    [curve stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)lawIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];

    GHStrokeSegment(CGPointMake(size * 0.50, size * 0.10), CGPointMake(size * 0.50, size * 0.86), line);
    GHStrokeSegment(CGPointMake(size * 0.30, size * 0.86), CGPointMake(size * 0.70, size * 0.86), line);
    GHStrokeSegment(CGPointMake(size * 0.14, size * 0.24), CGPointMake(size * 0.86, size * 0.24), line);

    for (NSInteger i = 0; i < 2; i++) {
        CGFloat cx = i == 0 ? size * 0.22 : size * 0.78;
        UIBezierPath *pan = [UIBezierPath bezierPath];
        [pan moveToPoint:CGPointMake(cx, size * 0.26)];
        [pan addLineToPoint:CGPointMake(cx - size * 0.13, size * 0.54)];
        [pan addQuadCurveToPoint:CGPointMake(cx + size * 0.13, size * 0.54) controlPoint:CGPointMake(cx, size * 0.68)];
        [pan closePath];
        pan.lineWidth = line;
        pan.lineJoinStyle = kCGLineJoinRound;
        [pan stroke];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)infoIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];
    [color setFill];
    GHStrokeRing(CGPointMake(size / 2.0, size / 2.0), size * 0.42, line);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(size * 0.44, size * 0.24, size * 0.12, size * 0.12)] fill];
    GHStrokeSegment(CGPointMake(size / 2.0, size * 0.46), CGPointMake(size / 2.0, size * 0.74), line * 1.2);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)issueClosedIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    [color setStroke];
    GHStrokeRing(CGPointMake(size / 2.0, size / 2.0), size * 0.40, line);
    UIBezierPath *check = [UIBezierPath bezierPath];
    [check moveToPoint:CGPointMake(size * 0.32, size * 0.51)];
    [check addLineToPoint:CGPointMake(size * 0.45, size * 0.64)];
    [check addLineToPoint:CGPointMake(size * 0.69, size * 0.38)];
    check.lineWidth = line;
    check.lineCapStyle = kCGLineCapRound;
    check.lineJoinStyle = kCGLineJoinRound;
    [check stroke];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)issueNotPlannedIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    [color setStroke];
    GHStrokeRing(CGPointMake(size / 2.0, size / 2.0), size * 0.40, line);
    GHStrokeSegment(CGPointMake(size * 0.24, size * 0.76), CGPointMake(size * 0.76, size * 0.24), line);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)commentIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.09);
    [color setStroke];
    UIBezierPath *bubble = [UIBezierPath bezierPath];
    CGFloat l = size * 0.10, r = size * 0.90, t = size * 0.14, b = size * 0.68, rad = size * 0.10;
    [bubble moveToPoint:CGPointMake(l + rad, t)];
    [bubble addLineToPoint:CGPointMake(r - rad, t)];
    [bubble addQuadCurveToPoint:CGPointMake(r, t + rad) controlPoint:CGPointMake(r, t)];
    [bubble addLineToPoint:CGPointMake(r, b - rad)];
    [bubble addQuadCurveToPoint:CGPointMake(r - rad, b) controlPoint:CGPointMake(r, b)];
    [bubble addLineToPoint:CGPointMake(size * 0.46, b)];
    [bubble addLineToPoint:CGPointMake(size * 0.28, size * 0.88)];
    [bubble addLineToPoint:CGPointMake(size * 0.28, b)];
    [bubble addLineToPoint:CGPointMake(l + rad, b)];
    [bubble addQuadCurveToPoint:CGPointMake(l, b - rad) controlPoint:CGPointMake(l, b)];
    [bubble addLineToPoint:CGPointMake(l, t + rad)];
    [bubble addQuadCurveToPoint:CGPointMake(l + rad, t) controlPoint:CGPointMake(l, t)];
    [bubble closePath];
    bubble.lineWidth = line;
    bubble.lineJoinStyle = kCGLineJoinRound;
    [bubble stroke];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)pullRequestMergedIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];

    CGPoint top = CGPointMake(size * 0.28, size * 0.20);
    CGPoint bottom = CGPointMake(size * 0.28, size * 0.80);
    CGPoint side = CGPointMake(size * 0.74, size * 0.58);
    GHStrokeRing(top, r, line);
    GHStrokeRing(bottom, r, line);
    GHStrokeRing(side, r, line);
    GHStrokeSegment(CGPointMake(top.x, top.y + r), CGPointMake(bottom.x, bottom.y - r), line);

    UIBezierPath *curve = [UIBezierPath bezierPath];
    [curve moveToPoint:CGPointMake(top.x, top.y + r)];
    [curve addQuadCurveToPoint:CGPointMake(side.x - r, side.y) controlPoint:CGPointMake(top.x, side.y)];
    curve.lineWidth = line;
    curve.lineCapStyle = kCGLineCapRound;
    [curve stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)pullRequestClosedIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];

    CGPoint topLeft = CGPointMake(size * 0.26, size * 0.20);
    CGPoint bottomLeft = CGPointMake(size * 0.26, size * 0.80);
    CGPoint bottomRight = CGPointMake(size * 0.74, size * 0.80);
    GHStrokeRing(topLeft, r, line);
    GHStrokeRing(bottomLeft, r, line);
    GHStrokeRing(bottomRight, r, line);
    GHStrokeSegment(CGPointMake(topLeft.x, topLeft.y + r), CGPointMake(bottomLeft.x, bottomLeft.y - r), line);
    GHStrokeSegment(CGPointMake(bottomRight.x, bottomRight.y - r), CGPointMake(bottomRight.x, size * 0.48), line);
    GHStrokeSegment(CGPointMake(size * 0.62, size * 0.10), CGPointMake(size * 0.86, size * 0.34), line);
    GHStrokeSegment(CGPointMake(size * 0.86, size * 0.10), CGPointMake(size * 0.62, size * 0.34), line);

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)pullRequestDraftIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    CGFloat r = size * 0.12;
    [color setStroke];
    [color setFill];

    CGPoint topLeft = CGPointMake(size * 0.26, size * 0.20);
    CGPoint bottomLeft = CGPointMake(size * 0.26, size * 0.80);
    CGPoint bottomRight = CGPointMake(size * 0.74, size * 0.80);
    GHStrokeRing(topLeft, r, line);
    GHStrokeRing(bottomLeft, r, line);
    GHStrokeRing(bottomRight, r, line);
    GHStrokeSegment(CGPointMake(topLeft.x, topLeft.y + r), CGPointMake(bottomLeft.x, bottomLeft.y - r), line);
    CGFloat dot = line * 1.3;
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat y = size * 0.20 + i * size * 0.16;
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(bottomRight.x - dot / 2.0, y - dot / 2.0, dot, dot)] fill];
    }

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

+ (UIImage *)fileZipIconWithColor:(UIColor *)color size:(CGFloat)size {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    CGFloat line = MAX(1.2, size * 0.08);
    [color setStroke];
    [color setFill];

    CGFloat left = size * 0.18;
    CGFloat right = size * 0.82;
    CGFloat top = size * 0.08;
    CGFloat bottom = size * 0.92;
    CGFloat fold = size * 0.22;

    UIBezierPath *page = [UIBezierPath bezierPath];
    [page moveToPoint:CGPointMake(left, top)];
    [page addLineToPoint:CGPointMake(right - fold, top)];
    [page addLineToPoint:CGPointMake(right, top + fold)];
    [page addLineToPoint:CGPointMake(right, bottom)];
    [page addLineToPoint:CGPointMake(left, bottom)];
    [page closePath];
    page.lineWidth = line;
    page.lineJoinStyle = kCGLineJoinRound;
    [page stroke];

    UIBezierPath *corner = [UIBezierPath bezierPath];
    [corner moveToPoint:CGPointMake(right - fold, top)];
    [corner addLineToPoint:CGPointMake(right - fold, top + fold)];
    [corner addLineToPoint:CGPointMake(right, top + fold)];
    corner.lineWidth = line;
    corner.lineJoinStyle = kCGLineJoinRound;
    [corner stroke];

    CGFloat zipX = size * 0.40;
    CGFloat tooth = size * 0.08;
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat y = top + size * 0.06 + i * tooth * 1.5;
        CGFloat x = (i % 2 == 0) ? zipX : zipX + tooth;
        [[UIBezierPath bezierPathWithRect:CGRectMake(x, y, tooth, tooth)] fill];
    }
    UIBezierPath *pull = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(zipX - tooth * 0.25, size * 0.62, tooth * 2.5, tooth * 2.2)
                                                    cornerRadius:tooth * 0.5];
    pull.lineWidth = line * 0.9;
    [pull stroke];

    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}


@end
