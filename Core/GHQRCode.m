#import "GHQRCode.h"

static const NSInteger kGHQRMaxVersion = 9;
static const NSInteger kGHQREccPerBlock[] = {0, 10, 16, 26, 18, 24, 16, 18, 22, 22};
static const NSInteger kGHQRNumBlocks[] = {0, 1, 1, 1, 2, 2, 4, 4, 4, 5};

static uint8_t GHQRMultiply(uint8_t x, uint8_t y) {
    NSInteger z = 0;
    for (NSInteger i = 7; i >= 0; i--) {
        z = (z << 1) ^ ((z >> 7) * 0x11D);
        z ^= ((y >> i) & 1) * x;
    }
    return (uint8_t)z;
}

static NSInteger GHQRRawModules(NSInteger ver) {
    NSInteger result = (16 * ver + 128) * ver + 64;
    if (ver >= 2) {
        NSInteger numAlign = ver / 7 + 2;
        result -= (25 * numAlign - 10) * numAlign - 55;
        if (ver >= 7) result -= 36;
    }
    return result;
}

static NSInteger GHQRDataCodewords(NSInteger ver) {
    return GHQRRawModules(ver) / 8 - kGHQREccPerBlock[ver] * kGHQRNumBlocks[ver];
}

@interface GHQRMatrix : NSObject {
@public
    NSInteger _size;
    BOOL *_modules;
    BOOL *_function;
}
@end

@implementation GHQRMatrix

- (id)initWithSize:(NSInteger)size {
    self = [super init];
    if (self) {
        _size = size;
        _modules = calloc(size * size, sizeof(BOOL));
        _function = calloc(size * size, sizeof(BOOL));
    }
    return self;
}

- (void)dealloc {
    free(_modules);
    free(_function);
}

- (void)setFunctionX:(NSInteger)x y:(NSInteger)y dark:(BOOL)dark {
    _modules[y * _size + x] = dark;
    _function[y * _size + x] = YES;
}

@end

@implementation GHQRCode

+ (NSArray *)alignmentPositionsForVersion:(NSInteger)ver size:(NSInteger)size {
    if (ver == 1) return @[];
    NSInteger numAlign = ver / 7 + 2;
    NSInteger step = (ver * 8 + numAlign * 3 + 5) / (numAlign * 4 - 4) * 2;
    NSMutableArray *result = [NSMutableArray arrayWithObject:@6];
    for (NSInteger pos = size - 7; (NSInteger)result.count < numAlign; pos -= step) {
        [result insertObject:@(pos) atIndex:1];
    }
    return result;
}

+ (void)drawFormatBitsWithMask:(NSInteger)mask matrix:(GHQRMatrix *)m {
    NSInteger data = (0 << 3) | mask;
    NSInteger rem = data;
    for (NSInteger i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    NSInteger bits = ((data << 10) | rem) ^ 0x5412;
    NSInteger size = m->_size;
    for (NSInteger i = 0; i <= 5; i++) [m setFunctionX:8 y:i dark:(bits >> i) & 1];
    [m setFunctionX:8 y:7 dark:(bits >> 6) & 1];
    [m setFunctionX:8 y:8 dark:(bits >> 7) & 1];
    [m setFunctionX:7 y:8 dark:(bits >> 8) & 1];
    for (NSInteger i = 9; i < 15; i++) [m setFunctionX:14 - i y:8 dark:(bits >> i) & 1];
    for (NSInteger i = 0; i < 8; i++) [m setFunctionX:size - 1 - i y:8 dark:(bits >> i) & 1];
    for (NSInteger i = 8; i < 15; i++) [m setFunctionX:8 y:size - 15 + i dark:(bits >> i) & 1];
    [m setFunctionX:8 y:size - 8 dark:YES];
}

+ (void)drawFunctionPatternsForVersion:(NSInteger)ver matrix:(GHQRMatrix *)m {
    NSInteger size = m->_size;
    for (NSInteger i = 0; i < size; i++) {
        [m setFunctionX:6 y:i dark:i % 2 == 0];
        [m setFunctionX:i y:6 dark:i % 2 == 0];
    }

    NSInteger finders[3][2] = {{3, 3}, {size - 4, 3}, {3, size - 4}};
    for (NSInteger f = 0; f < 3; f++) {
        for (NSInteger dy = -4; dy <= 4; dy++) {
            for (NSInteger dx = -4; dx <= 4; dx++) {
                NSInteger x = finders[f][0] + dx, y = finders[f][1] + dy;
                if (x < 0 || x >= size || y < 0 || y >= size) continue;
                NSInteger dist = MAX(labs(dx), labs(dy));
                [m setFunctionX:x y:y dark:dist != 2 && dist != 4];
            }
        }
    }

    NSArray *align = [self alignmentPositionsForVersion:ver size:size];
    NSInteger last = (NSInteger)align.count - 1;
    for (NSInteger i = 0; i <= last; i++) {
        for (NSInteger j = 0; j <= last; j++) {
            if ((i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)) continue;
            NSInteger cx = [align[i] integerValue], cy = [align[j] integerValue];
            for (NSInteger dy = -2; dy <= 2; dy++) {
                for (NSInteger dx = -2; dx <= 2; dx++) {
                    [m setFunctionX:cx + dx y:cy + dy dark:MAX(labs(dx), labs(dy)) != 1];
                }
            }
        }
    }

    [self drawFormatBitsWithMask:0 matrix:m];

    if (ver >= 7) {
        NSInteger rem = ver;
        for (NSInteger i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
        NSInteger bits = (ver << 12) | rem;
        for (NSInteger i = 0; i < 18; i++) {
            BOOL bit = (bits >> i) & 1;
            NSInteger a = size - 11 + i % 3, b = i / 3;
            [m setFunctionX:a y:b dark:bit];
            [m setFunctionX:b y:a dark:bit];
        }
    }
}

+ (NSData *)codewordsForData:(NSData *)data version:(NSInteger)ver {
    NSInteger dataCapacity = GHQRDataCodewords(ver);
    NSMutableData *buffer = [NSMutableData dataWithLength:dataCapacity];
    uint8_t *out = buffer.mutableBytes;
    __block NSInteger bitLength = 0;
    void (^append)(NSInteger, NSInteger) = ^(NSInteger value, NSInteger count) {
        for (NSInteger i = count - 1; i >= 0; i--) {
            if ((value >> i) & 1) out[bitLength >> 3] |= 0x80 >> (bitLength & 7);
            bitLength++;
        }
    };
    append(4, 4);
    append(data.length, 8);
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) append(bytes[i], 8);
    NSInteger capacityBits = dataCapacity * 8;
    append(0, MIN(4, capacityBits - bitLength));
    append(0, (8 - bitLength % 8) % 8);
    uint8_t pad = 0xEC;
    while (bitLength < capacityBits) {
        append(pad, 8);
        pad ^= 0xEC ^ 0x11;
    }

    NSInteger numBlocks = kGHQRNumBlocks[ver];
    NSInteger eccLen = kGHQREccPerBlock[ver];
    NSInteger rawCodewords = GHQRRawModules(ver) / 8;
    NSInteger numShortBlocks = numBlocks - rawCodewords % numBlocks;
    NSInteger shortBlockLen = rawCodewords / numBlocks;

    uint8_t divisor[32] = {0};
    divisor[eccLen - 1] = 1;
    uint8_t root = 1;
    for (NSInteger i = 0; i < eccLen; i++) {
        for (NSInteger j = 0; j < eccLen; j++) {
            divisor[j] = GHQRMultiply(divisor[j], root);
            if (j + 1 < eccLen) divisor[j] ^= divisor[j + 1];
        }
        root = GHQRMultiply(root, 0x02);
    }

    uint8_t blocks[8][160];
    NSInteger offset = 0;
    for (NSInteger b = 0; b < numBlocks; b++) {
        NSInteger datLen = shortBlockLen - eccLen + (b < numShortBlocks ? 0 : 1);
        uint8_t remainder[32] = {0};
        for (NSInteger k = 0; k < datLen; k++) {
            uint8_t factor = out[offset + k] ^ remainder[0];
            memmove(remainder, remainder + 1, eccLen - 1);
            remainder[eccLen - 1] = 0;
            for (NSInteger r = 0; r < eccLen; r++) remainder[r] ^= GHQRMultiply(divisor[r], factor);
        }
        NSInteger pos = 0;
        for (NSInteger k = 0; k < datLen; k++) blocks[b][pos++] = out[offset + k];
        if (b < numShortBlocks) blocks[b][pos++] = 0;
        for (NSInteger r = 0; r < eccLen; r++) blocks[b][pos++] = remainder[r];
        offset += datLen;
    }

    NSMutableData *result = [NSMutableData dataWithCapacity:rawCodewords];
    for (NSInteger i = 0; i < shortBlockLen + 1; i++) {
        for (NSInteger b = 0; b < numBlocks; b++) {
            if (i != shortBlockLen - eccLen || b >= numShortBlocks) [result appendBytes:&blocks[b][i] length:1];
        }
    }
    return result;
}

+ (GHQRMatrix *)matrixForString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSInteger ver = 1;
    while (ver <= kGHQRMaxVersion && GHQRDataCodewords(ver) * 8 < 12 + (NSInteger)data.length * 8) ver++;
    if (ver > kGHQRMaxVersion) return nil;

    GHQRMatrix *m = [[GHQRMatrix alloc] initWithSize:ver * 4 + 17];
    NSInteger size = m->_size;
    [self drawFunctionPatternsForVersion:ver matrix:m];

    NSData *codewords = [self codewordsForData:data version:ver];
    const uint8_t *cw = codewords.bytes;
    NSInteger totalBits = (NSInteger)codewords.length * 8;
    NSInteger i = 0;
    for (NSInteger right = size - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (NSInteger vert = 0; vert < size; vert++) {
            for (NSInteger j = 0; j < 2; j++) {
                NSInteger x = right - j;
                BOOL upward = ((right + 1) & 2) == 0;
                NSInteger y = upward ? size - 1 - vert : vert;
                if (!m->_function[y * size + x] && i < totalBits) {
                    m->_modules[y * size + x] = (cw[i >> 3] >> (7 - (i & 7))) & 1;
                    i++;
                }
            }
        }
    }

    for (NSInteger y = 0; y < size; y++) {
        for (NSInteger x = 0; x < size; x++) {
            if (!m->_function[y * size + x] && (x + y) % 2 == 0) m->_modules[y * size + x] = !m->_modules[y * size + x];
        }
    }
    [self drawFormatBitsWithMask:0 matrix:m];
    return m;
}

+ (UIImage *)imageForString:(NSString *)string size:(CGFloat)size {
    GHQRMatrix *m = [self matrixForString:string];
    if (!m) return nil;
    NSInteger count = m->_size + 8;
    CGFloat module = MAX(1, floor(size / count));
    CGFloat side = module * count;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetShouldAntialias(ctx, NO);
    [[UIColor whiteColor] setFill];
    UIRectFill(CGRectMake(0, 0, side, side));
    [[UIColor blackColor] setFill];
    for (NSInteger y = 0; y < m->_size; y++) {
        for (NSInteger x = 0; x < m->_size; x++) {
            if (m->_modules[y * m->_size + x]) UIRectFill(CGRectMake((x + 4) * module, (y + 4) * module, module, module));
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end
