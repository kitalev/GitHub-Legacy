#import "GHJSONSerialization.h"

typedef struct {
    const uint8_t *cursor;
    const uint8_t *end;
    const uint8_t *start;
} GHJSONReader;

static Class GHNativeJSONClass(void) {
    static Class cls = Nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = NSClassFromString(@"NSJSONSerialization");
    });
    return cls;
}

static NSError *GHJSONError(NSString *message, NSUInteger offset) {
    NSString *description = [NSString stringWithFormat:@"%@ (offset %lu)", message, (unsigned long)offset];
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:3840
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static void GHJSONSkipWhitespace(GHJSONReader *reader) {
    while (reader->cursor < reader->end) {
        uint8_t c = *reader->cursor;
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
        reader->cursor++;
    }
}

static id GHJSONParseValue(GHJSONReader *reader, NSUInteger depth, NSString **message);

static int GHJSONHexValue(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static BOOL GHJSONReadHex4(GHJSONReader *reader, uint32_t *value) {
    if (reader->end - reader->cursor < 4) return NO;
    uint32_t result = 0;
    for (int i = 0; i < 4; i++) {
        int digit = GHJSONHexValue(reader->cursor[i]);
        if (digit < 0) return NO;
        result = (result << 4) | (uint32_t)digit;
    }
    reader->cursor += 4;
    *value = result;
    return YES;
}

static void GHJSONAppendCodePoint(NSMutableData *buffer, uint32_t code) {
    uint8_t bytes[4];
    NSUInteger length;
    if (code < 0x80) {
        bytes[0] = (uint8_t)code;
        length = 1;
    } else if (code < 0x800) {
        bytes[0] = (uint8_t)(0xC0 | (code >> 6));
        bytes[1] = (uint8_t)(0x80 | (code & 0x3F));
        length = 2;
    } else if (code < 0x10000) {
        bytes[0] = (uint8_t)(0xE0 | (code >> 12));
        bytes[1] = (uint8_t)(0x80 | ((code >> 6) & 0x3F));
        bytes[2] = (uint8_t)(0x80 | (code & 0x3F));
        length = 3;
    } else {
        bytes[0] = (uint8_t)(0xF0 | (code >> 18));
        bytes[1] = (uint8_t)(0x80 | ((code >> 12) & 0x3F));
        bytes[2] = (uint8_t)(0x80 | ((code >> 6) & 0x3F));
        bytes[3] = (uint8_t)(0x80 | (code & 0x3F));
        length = 4;
    }
    [buffer appendBytes:bytes length:length];
}

static NSString *GHJSONParseString(GHJSONReader *reader, NSString **message) {
    reader->cursor++;
    const uint8_t *runStart = reader->cursor;
    while (reader->cursor < reader->end) {
        uint8_t c = *reader->cursor;
        if (c == '"') {
            NSString *string = [[NSString alloc] initWithBytes:runStart
                                                        length:(NSUInteger)(reader->cursor - runStart)
                                                      encoding:NSUTF8StringEncoding];
            reader->cursor++;
            if (string == nil) *message = @"Invalid UTF-8 in string";
            return string;
        }
        if (c == '\\') break;
        if (c < 0x20) {
            *message = @"Unescaped control character in string";
            return nil;
        }
        reader->cursor++;
    }

    NSMutableData *buffer = [NSMutableData dataWithBytes:runStart length:(NSUInteger)(reader->cursor - runStart)];
    while (reader->cursor < reader->end) {
        uint8_t c = *reader->cursor;
        if (c == '"') {
            reader->cursor++;
            NSString *string = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
            if (string == nil) *message = @"Invalid UTF-8 in string";
            return string;
        }
        if (c < 0x20) {
            *message = @"Unescaped control character in string";
            return nil;
        }
        if (c != '\\') {
            const uint8_t *chunk = reader->cursor;
            while (reader->cursor < reader->end && *reader->cursor != '"' && *reader->cursor != '\\' && *reader->cursor >= 0x20) {
                reader->cursor++;
            }
            [buffer appendBytes:chunk length:(NSUInteger)(reader->cursor - chunk)];
            continue;
        }
        reader->cursor++;
        if (reader->cursor >= reader->end) break;
        uint8_t escape = *reader->cursor++;
        uint8_t literal;
        switch (escape) {
            case '"': literal = '"'; break;
            case '\\': literal = '\\'; break;
            case '/': literal = '/'; break;
            case 'b': literal = '\b'; break;
            case 'f': literal = '\f'; break;
            case 'n': literal = '\n'; break;
            case 'r': literal = '\r'; break;
            case 't': literal = '\t'; break;
            case 'u': {
                uint32_t code;
                if (!GHJSONReadHex4(reader, &code)) {
                    *message = @"Invalid unicode escape";
                    return nil;
                }
                if (code >= 0xD800 && code <= 0xDBFF) {
                    uint32_t low = 0;
                    const uint8_t *saved = reader->cursor;
                    if (reader->end - reader->cursor >= 6 && reader->cursor[0] == '\\' && reader->cursor[1] == 'u') {
                        reader->cursor += 2;
                        if (GHJSONReadHex4(reader, &low) && low >= 0xDC00 && low <= 0xDFFF) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                        } else {
                            reader->cursor = saved;
                            code = 0xFFFD;
                        }
                    } else {
                        code = 0xFFFD;
                    }
                } else if (code >= 0xDC00 && code <= 0xDFFF) {
                    code = 0xFFFD;
                }
                GHJSONAppendCodePoint(buffer, code);
                continue;
            }
            default:
                *message = @"Invalid escape sequence";
                return nil;
        }
        [buffer appendBytes:&literal length:1];
    }
    *message = @"Unterminated string";
    return nil;
}

static NSNumber *GHJSONParseNumber(GHJSONReader *reader, NSString **message) {
    const uint8_t *start = reader->cursor;
    BOOL isFloat = NO;
    if (reader->cursor < reader->end && *reader->cursor == '-') reader->cursor++;
    const uint8_t *digits = reader->cursor;
    while (reader->cursor < reader->end && *reader->cursor >= '0' && *reader->cursor <= '9') reader->cursor++;
    if (reader->cursor == digits) {
        *message = @"Invalid number";
        return nil;
    }
    if (reader->cursor < reader->end && *reader->cursor == '.') {
        isFloat = YES;
        reader->cursor++;
        const uint8_t *fraction = reader->cursor;
        while (reader->cursor < reader->end && *reader->cursor >= '0' && *reader->cursor <= '9') reader->cursor++;
        if (reader->cursor == fraction) {
            *message = @"Invalid number";
            return nil;
        }
    }
    if (reader->cursor < reader->end && (*reader->cursor == 'e' || *reader->cursor == 'E')) {
        isFloat = YES;
        reader->cursor++;
        if (reader->cursor < reader->end && (*reader->cursor == '+' || *reader->cursor == '-')) reader->cursor++;
        const uint8_t *exponent = reader->cursor;
        while (reader->cursor < reader->end && *reader->cursor >= '0' && *reader->cursor <= '9') reader->cursor++;
        if (reader->cursor == exponent) {
            *message = @"Invalid number";
            return nil;
        }
    }

    size_t length = (size_t)(reader->cursor - start);
    char stackBuffer[64];
    char *text = length < sizeof(stackBuffer) ? stackBuffer : malloc(length + 1);
    if (text == NULL) return nil;
    memcpy(text, start, length);
    text[length] = '\0';

    NSNumber *number = nil;
    if (!isFloat) {
        errno = 0;
        long long value = strtoll(text, NULL, 10);
        if (errno == 0) {
            number = [NSNumber numberWithLongLong:value];
        } else if (text[0] != '-') {
            errno = 0;
            unsigned long long unsignedValue = strtoull(text, NULL, 10);
            if (errno == 0) number = [NSNumber numberWithUnsignedLongLong:unsignedValue];
        }
    }
    if (number == nil) {
        number = [NSNumber numberWithDouble:strtod(text, NULL)];
    }
    if (text != stackBuffer) free(text);
    return number;
}

static BOOL GHJSONMatchLiteral(GHJSONReader *reader, const char *literal) {
    size_t length = strlen(literal);
    if ((size_t)(reader->end - reader->cursor) < length) return NO;
    if (memcmp(reader->cursor, literal, length) != 0) return NO;
    reader->cursor += length;
    return YES;
}

static id GHJSONParseArray(GHJSONReader *reader, NSUInteger depth, NSString **message) {
    reader->cursor++;
    NSMutableArray *array = [NSMutableArray array];
    GHJSONSkipWhitespace(reader);
    if (reader->cursor < reader->end && *reader->cursor == ']') {
        reader->cursor++;
        return array;
    }
    while (reader->cursor < reader->end) {
        id value = GHJSONParseValue(reader, depth + 1, message);
        if (value == nil) return nil;
        [array addObject:value];
        GHJSONSkipWhitespace(reader);
        if (reader->cursor >= reader->end) break;
        uint8_t c = *reader->cursor++;
        if (c == ']') return array;
        if (c != ',') {
            *message = @"Expected ',' or ']' in array";
            return nil;
        }
    }
    *message = @"Unterminated array";
    return nil;
}

static id GHJSONParseObject(GHJSONReader *reader, NSUInteger depth, NSString **message) {
    reader->cursor++;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    GHJSONSkipWhitespace(reader);
    if (reader->cursor < reader->end && *reader->cursor == '}') {
        reader->cursor++;
        return dictionary;
    }
    while (reader->cursor < reader->end) {
        GHJSONSkipWhitespace(reader);
        if (reader->cursor >= reader->end || *reader->cursor != '"') {
            *message = @"Expected string key in object";
            return nil;
        }
        NSString *key = GHJSONParseString(reader, message);
        if (key == nil) return nil;
        GHJSONSkipWhitespace(reader);
        if (reader->cursor >= reader->end || *reader->cursor != ':') {
            *message = @"Expected ':' in object";
            return nil;
        }
        reader->cursor++;
        id value = GHJSONParseValue(reader, depth + 1, message);
        if (value == nil) return nil;
        [dictionary setObject:value forKey:key];
        GHJSONSkipWhitespace(reader);
        if (reader->cursor >= reader->end) break;
        uint8_t c = *reader->cursor++;
        if (c == '}') return dictionary;
        if (c != ',') {
            *message = @"Expected ',' or '}' in object";
            return nil;
        }
    }
    *message = @"Unterminated object";
    return nil;
}

static id GHJSONParseValue(GHJSONReader *reader, NSUInteger depth, NSString **message) {
    if (depth > 512) {
        *message = @"Nesting too deep";
        return nil;
    }
    GHJSONSkipWhitespace(reader);
    if (reader->cursor >= reader->end) {
        *message = @"Unexpected end of data";
        return nil;
    }
    uint8_t c = *reader->cursor;
    switch (c) {
        case '{': return GHJSONParseObject(reader, depth, message);
        case '[': return GHJSONParseArray(reader, depth, message);
        case '"': return GHJSONParseString(reader, message);
        case 't':
            if (GHJSONMatchLiteral(reader, "true")) return (__bridge NSNumber *)kCFBooleanTrue;
            break;
        case 'f':
            if (GHJSONMatchLiteral(reader, "false")) return (__bridge NSNumber *)kCFBooleanFalse;
            break;
        case 'n':
            if (GHJSONMatchLiteral(reader, "null")) return [NSNull null];
            break;
        default:
            if (c == '-' || (c >= '0' && c <= '9')) return GHJSONParseNumber(reader, message);
            break;
    }
    *message = @"Unexpected character";
    return nil;
}

static void GHJSONAppendString(NSMutableData *output, const char *text) {
    [output appendBytes:text length:strlen(text)];
}

static void GHJSONAppendIndent(NSMutableData *output, NSUInteger level) {
    for (NSUInteger i = 0; i < level; i++) GHJSONAppendString(output, "  ");
}

static void GHJSONWriteString(NSMutableData *output, NSString *string) {
    NSData *utf8 = [string dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = utf8.bytes;
    NSUInteger length = utf8.length;
    GHJSONAppendString(output, "\"");
    NSUInteger runStart = 0;
    for (NSUInteger i = 0; i < length; i++) {
        uint8_t c = bytes[i];
        const char *escape = NULL;
        char unicode[7];
        switch (c) {
            case '"': escape = "\\\""; break;
            case '\\': escape = "\\\\"; break;
            case '/': escape = "\\/"; break;
            case '\n': escape = "\\n"; break;
            case '\r': escape = "\\r"; break;
            case '\t': escape = "\\t"; break;
            case '\b': escape = "\\b"; break;
            case '\f': escape = "\\f"; break;
            default:
                if (c < 0x20) {
                    snprintf(unicode, sizeof(unicode), "\\u%04x", c);
                    escape = unicode;
                }
                break;
        }
        if (escape == NULL) continue;
        if (i > runStart) [output appendBytes:bytes + runStart length:i - runStart];
        GHJSONAppendString(output, escape);
        runStart = i + 1;
    }
    if (length > runStart) [output appendBytes:bytes + runStart length:length - runStart];
    GHJSONAppendString(output, "\"");
}

static BOOL GHJSONWriteValue(NSMutableData *output, id value, BOOL pretty, NSUInteger level) {
    if ([value isKindOfClass:[NSString class]]) {
        GHJSONWriteString(output, value);
        return YES;
    }
    if ([value isKindOfClass:[NSNull class]]) {
        GHJSONAppendString(output, "null");
        return YES;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            GHJSONAppendString(output, [value boolValue] ? "true" : "false");
            return YES;
        }
        double doubleValue = [value doubleValue];
        if (isnan(doubleValue) || isinf(doubleValue)) return NO;
        GHJSONAppendString(output, [[value stringValue] UTF8String]);
        return YES;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        GHJSONAppendString(output, "[");
        NSUInteger index = 0;
        for (id item in value) {
            if (index++ > 0) GHJSONAppendString(output, ",");
            if (pretty) {
                GHJSONAppendString(output, "\n");
                GHJSONAppendIndent(output, level + 1);
            }
            if (!GHJSONWriteValue(output, item, pretty, level + 1)) return NO;
        }
        if (pretty && index > 0) {
            GHJSONAppendString(output, "\n");
            GHJSONAppendIndent(output, level);
        }
        GHJSONAppendString(output, "]");
        return YES;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        GHJSONAppendString(output, "{");
        NSUInteger index = 0;
        for (id key in value) {
            if (![key isKindOfClass:[NSString class]]) return NO;
            if (index++ > 0) GHJSONAppendString(output, ",");
            if (pretty) {
                GHJSONAppendString(output, "\n");
                GHJSONAppendIndent(output, level + 1);
            }
            GHJSONWriteString(output, key);
            GHJSONAppendString(output, pretty ? " : " : ":");
            if (!GHJSONWriteValue(output, [value objectForKey:key], pretty, level + 1)) return NO;
        }
        if (pretty && index > 0) {
            GHJSONAppendString(output, "\n");
            GHJSONAppendIndent(output, level);
        }
        GHJSONAppendString(output, "}");
        return YES;
    }
    return NO;
}

@implementation GHJSONSerialization

+ (BOOL)isValidJSONObject:(id)obj {
    Class native = GHNativeJSONClass();
    if (native != Nil) return [native isValidJSONObject:obj];
    if (![obj isKindOfClass:[NSArray class]] && ![obj isKindOfClass:[NSDictionary class]]) return NO;
    return GHJSONWriteValue([NSMutableData data], obj, NO, 0);
}

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    Class native = GHNativeJSONClass();
    if (native != Nil) return [native JSONObjectWithData:data options:opt error:error];

    if (data == nil) {
        if (error) *error = GHJSONError(@"No data", 0);
        return nil;
    }

    GHJSONReader reader;
    reader.start = data.bytes;
    reader.cursor = reader.start;
    reader.end = reader.start + data.length;
    if (data.length >= 3 && reader.cursor[0] == 0xEF && reader.cursor[1] == 0xBB && reader.cursor[2] == 0xBF) {
        reader.cursor += 3;
    }

    NSString *message = nil;
    GHJSONSkipWhitespace(&reader);
    BOOL container = reader.cursor < reader.end && (*reader.cursor == '{' || *reader.cursor == '[');
    if (!container && !(opt & NSJSONReadingAllowFragments)) {
        if (error) *error = GHJSONError(@"JSON text did not start with array or object", (NSUInteger)(reader.cursor - reader.start));
        return nil;
    }

    id result = GHJSONParseValue(&reader, 0, &message);
    if (result != nil) {
        GHJSONSkipWhitespace(&reader);
        if (reader.cursor < reader.end) {
            result = nil;
            message = @"Garbage at end";
        }
    }
    if (result == nil && error) {
        *error = GHJSONError(message ?: @"Invalid JSON", (NSUInteger)(reader.cursor - reader.start));
    }
    return result;
}

+ (NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error {
    Class native = GHNativeJSONClass();
    if (native != Nil) return [native dataWithJSONObject:obj options:opt error:error];

    NSMutableData *output = [NSMutableData data];
    if (!GHJSONWriteValue(output, obj, (opt & NSJSONWritingPrettyPrinted) != 0, 0)) {
        if (error) *error = GHJSONError(@"Invalid type in JSON write", 0);
        return nil;
    }
    return output;
}

@end
