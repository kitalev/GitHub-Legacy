#import "GHYAMLParser.h"

@interface GHYAMLLine : NSObject
@property (nonatomic, assign) NSInteger indent;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *raw;
@end

@implementation GHYAMLLine
@end

static NSInteger GHYAMLLeadingSpaces(NSString *string) {
    NSInteger count = 0;
    while (count < (NSInteger)string.length && [string characterAtIndex:count] == ' ') count++;
    return count;
}

static NSString *GHYAMLTrim(NSString *string) {
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static BOOL GHYAMLIsSequenceEntry(NSString *text) {
    return [text isEqualToString:@"-"] || [text hasPrefix:@"- "];
}

static NSString *GHYAMLStripComment(NSString *text) {
    if ([text hasPrefix:@"#"]) return @"";
    NSRange range = [text rangeOfString:@" #"];
    if (range.location == NSNotFound) return text;
    return GHYAMLTrim([text substringToIndex:range.location]);
}

static NSUInteger GHYAMLClosingQuoteIndex(NSString *text, NSUInteger openIndex) {
    unichar quote = [text characterAtIndex:openIndex];
    for (NSUInteger i = openIndex + 1; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (quote == '"' && c == '\\') {
            i++;
            continue;
        }
        if (c != quote) continue;
        if (quote == '\'' && i + 1 < text.length && [text characterAtIndex:i + 1] == '\'') {
            i++;
            continue;
        }
        return i;
    }
    return NSNotFound;
}

static NSString *GHYAMLUnquote(NSString *text) {
    unichar quote = [text characterAtIndex:0];
    NSUInteger close = GHYAMLClosingQuoteIndex(text, 0);
    NSString *inner = close == NSNotFound
        ? [text substringFromIndex:1]
        : [text substringWithRange:NSMakeRange(1, close - 1)];

    if (quote == '\'') return [inner stringByReplacingOccurrencesOfString:@"''" withString:@"'"];

    NSMutableString *result = [NSMutableString stringWithCapacity:inner.length];
    for (NSUInteger i = 0; i < inner.length; i++) {
        unichar c = [inner characterAtIndex:i];
        if (c != '\\' || i + 1 >= inner.length) {
            [result appendFormat:@"%C", c];
            continue;
        }
        unichar escaped = [inner characterAtIndex:++i];
        switch (escaped) {
            case 'n': [result appendString:@"\n"]; break;
            case 't': [result appendString:@"\t"]; break;
            case 'r': [result appendString:@"\r"]; break;
            case '0': break;
            case 'x':
            case 'u':
            case 'U': {
                NSUInteger digits = escaped == 'x' ? 2 : (escaped == 'u' ? 4 : 8);
                if (i + digits >= inner.length) {
                    [result appendFormat:@"%C", escaped];
                    break;
                }
                unsigned int code = 0;
                NSScanner *scanner = [NSScanner scannerWithString:[inner substringWithRange:NSMakeRange(i + 1, digits)]];
                if ([scanner scanHexInt:&code]) {
                    if (code > 0xFFFF) {
                        code -= 0x10000;
                        [result appendFormat:@"%C%C", (unichar)(0xD800 + (code >> 10)), (unichar)(0xDC00 + (code & 0x3FF))];
                    } else {
                        [result appendFormat:@"%C", (unichar)code];
                    }
                }
                i += digits;
                break;
            }
            default:
                [result appendFormat:@"%C", escaped];
                break;
        }
    }
    return result;
}

static id GHYAMLPlainScalar(NSString *text) {
    NSString *lower = [text lowercaseString];
    if (text.length == 0 || [text isEqualToString:@"~"] || [lower isEqualToString:@"null"]) return [NSNull null];
    if ([lower isEqualToString:@"true"]) return @YES;
    if ([lower isEqualToString:@"false"]) return @NO;

    static NSRegularExpression *integerRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        integerRegex = [NSRegularExpression regularExpressionWithPattern:@"^[-+]?[0-9]{1,15}$" options:0 error:nil];
    });
    if ([integerRegex numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0) {
        return @([text longLongValue]);
    }
    return text;
}

static BOOL GHYAMLFlowIsBalanced(NSString *text) {
    NSInteger depth = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '"' || c == '\'') {
            NSUInteger close = GHYAMLClosingQuoteIndex(text, i);
            if (close == NSNotFound) return NO;
            i = close;
            continue;
        }
        if (c == '[' || c == '{') depth++;
        if (c == ']' || c == '}') depth--;
        if (depth == 0) return YES;
    }
    return depth <= 0;
}

static void GHYAMLSkipFlowWhitespace(NSString *text, NSUInteger *index) {
    while (*index < text.length) {
        unichar c = [text characterAtIndex:*index];
        if (c != ' ' && c != '\n' && c != '\t') break;
        (*index)++;
    }
}

static id GHYAMLParseFlowValue(NSString *text, NSUInteger *index, BOOL isKey) {
    GHYAMLSkipFlowWhitespace(text, index);
    if (*index >= text.length) return [NSNull null];

    unichar c = [text characterAtIndex:*index];
    if (c == '[') {
        (*index)++;
        NSMutableArray *items = [NSMutableArray array];
        while (*index < text.length) {
            GHYAMLSkipFlowWhitespace(text, index);
            if (*index >= text.length) break;
            if ([text characterAtIndex:*index] == ']') {
                (*index)++;
                break;
            }
            [items addObject:GHYAMLParseFlowValue(text, index, NO)];
            GHYAMLSkipFlowWhitespace(text, index);
            if (*index >= text.length) break;
            unichar separator = [text characterAtIndex:*index];
            (*index)++;
            if (separator != ',') break;
        }
        return items;
    }

    if (c == '{') {
        (*index)++;
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        while (*index < text.length) {
            GHYAMLSkipFlowWhitespace(text, index);
            if (*index >= text.length) break;
            if ([text characterAtIndex:*index] == '}') {
                (*index)++;
                break;
            }
            NSString *key = GHYAMLString(GHYAMLParseFlowValue(text, index, YES)) ?: @"";
            GHYAMLSkipFlowWhitespace(text, index);
            id value = [NSNull null];
            if (*index < text.length && [text characterAtIndex:*index] == ':') {
                (*index)++;
                GHYAMLSkipFlowWhitespace(text, index);
                if (*index < text.length) {
                    unichar next = [text characterAtIndex:*index];
                    if (next != ',' && next != '}') value = GHYAMLParseFlowValue(text, index, NO);
                }
            }
            dict[key] = value;
            GHYAMLSkipFlowWhitespace(text, index);
            if (*index >= text.length) break;
            unichar separator = [text characterAtIndex:*index];
            (*index)++;
            if (separator != ',') break;
        }
        return dict;
    }

    if (c == '"' || c == '\'') {
        NSUInteger close = GHYAMLClosingQuoteIndex(text, *index);
        NSUInteger end = close == NSNotFound ? text.length : close + 1;
        NSString *quoted = [text substringWithRange:NSMakeRange(*index, end - *index)];
        *index = end;
        return GHYAMLUnquote(quoted);
    }

    NSUInteger start = *index;
    while (*index < text.length) {
        unichar current = [text characterAtIndex:*index];
        if (current == ',' || current == ']' || current == '}') break;
        if (current == ':') {
            BOOL atEnd = *index + 1 >= text.length;
            unichar next = atEnd ? ' ' : [text characterAtIndex:*index + 1];
            if (next == ' ' || next == ',' || next == '}' || (isKey && atEnd)) break;
        }
        (*index)++;
    }
    return GHYAMLPlainScalar(GHYAMLTrim([text substringWithRange:NSMakeRange(start, *index - start)]));
}

static NSUInteger GHYAMLKeySeparatorIndex(NSString *text) {
    NSUInteger length = text.length;
    if (length == 0) return NSNotFound;

    unichar first = [text characterAtIndex:0];
    if (first == '"' || first == '\'') {
        NSUInteger close = GHYAMLClosingQuoteIndex(text, 0);
        if (close == NSNotFound) return NSNotFound;
        NSUInteger i = close + 1;
        while (i < length && [text characterAtIndex:i] == ' ') i++;
        if (i < length && [text characterAtIndex:i] == ':' && (i + 1 == length || [text characterAtIndex:i + 1] == ' ')) return i;
        return NSNotFound;
    }
    if (first == '[' || first == '{' || first == '#' || first == '|' || first == '>') return NSNotFound;

    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '#' && i > 0 && [text characterAtIndex:i - 1] == ' ') return NSNotFound;
        if (c == ':' && (i + 1 == length || [text characterAtIndex:i + 1] == ' ')) return i;
    }
    return NSNotFound;
}

static NSString *GHYAMLFoldLines(NSArray *lines) {
    NSMutableString *result = [NSMutableString string];
    BOOL previousWasText = NO;
    BOOL previousMoreIndented = NO;
    for (NSString *line in lines) {
        if (line.length == 0) {
            [result appendString:@"\n"];
            previousWasText = NO;
            continue;
        }
        BOOL moreIndented = [line hasPrefix:@" "];
        if (previousWasText) [result appendString:(moreIndented || previousMoreIndented) ? @"\n" : @" "];
        [result appendString:line];
        previousWasText = YES;
        previousMoreIndented = moreIndented;
    }
    return result;
}

@interface GHYAMLParser ()
@property (nonatomic, strong) NSArray *lines;
@property (nonatomic, assign) NSUInteger position;
@end

@implementation GHYAMLParser

+ (id)objectFromString:(NSString *)string {
    if (string.length == 0) return nil;
    GHYAMLParser *parser = [[GHYAMLParser alloc] initWithString:string];
    id result = [parser parseNodeWithMinimumIndent:0];
    return result == [NSNull null] ? nil : result;
}

- (id)initWithString:(NSString *)string {
    self = [super init];
    if (self) {
        NSString *normalized = [string stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
        normalized = [normalized stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
        if ([normalized hasPrefix:@"﻿"]) normalized = [normalized substringFromIndex:1];

        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *raw in [normalized componentsSeparatedByString:@"\n"]) {
            GHYAMLLine *line = [[GHYAMLLine alloc] init];
            line.raw = raw;
            line.indent = GHYAMLLeadingSpaces(raw);
            NSString *text = [raw substringFromIndex:line.indent];
            line.text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [lines addObject:line];
        }
        _lines = lines;
    }
    return self;
}

- (BOOL)isBlankLine:(GHYAMLLine *)line {
    if (line.text.length == 0 || [line.text hasPrefix:@"#"]) return YES;
    return line.indent == 0 && ([line.text isEqualToString:@"---"] || [line.text isEqualToString:@"..."]);
}

- (GHYAMLLine *)currentLine {
    while (self.position < self.lines.count && [self isBlankLine:self.lines[self.position]]) {
        self.position++;
    }
    return self.position < self.lines.count ? self.lines[self.position] : nil;
}

- (id)parseNodeWithMinimumIndent:(NSInteger)minimumIndent {
    GHYAMLLine *line = [self currentLine];
    if (line == nil || line.indent < minimumIndent) return [NSNull null];

    if (GHYAMLIsSequenceEntry(line.text)) return [self parseSequenceAtIndent:line.indent];
    if (GHYAMLKeySeparatorIndex(line.text) != NSNotFound) return [self parseMappingAtIndent:line.indent];

    self.position++;
    return [self parseValueText:line.text parentIndent:line.indent - 1];
}

- (NSArray *)parseSequenceAtIndent:(NSInteger)indent {
    NSMutableArray *items = [NSMutableArray array];
    while (YES) {
        GHYAMLLine *line = [self currentLine];
        if (line == nil || line.indent != indent || !GHYAMLIsSequenceEntry(line.text)) break;

        NSString *rest = [line.text substringFromIndex:1];
        NSInteger spaces = GHYAMLLeadingSpaces(rest);
        NSString *content = [rest substringFromIndex:spaces];
        if (content.length == 0 || [content hasPrefix:@"#"]) {
            self.position++;
            [items addObject:[self parseNodeWithMinimumIndent:indent + 1]];
        } else {
            line.indent = indent + 1 + spaces;
            line.text = content;
            [items addObject:[self parseNodeWithMinimumIndent:line.indent]];
        }
    }
    return items;
}

- (NSDictionary *)parseMappingAtIndent:(NSInteger)indent {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    while (YES) {
        GHYAMLLine *line = [self currentLine];
        if (line == nil || line.indent != indent || GHYAMLIsSequenceEntry(line.text)) break;

        NSUInteger separator = GHYAMLKeySeparatorIndex(line.text);
        self.position++;
        if (separator == NSNotFound) continue;

        NSString *rawKey = GHYAMLTrim([line.text substringToIndex:separator]);
        NSString *key = rawKey;
        if ([rawKey hasPrefix:@"\""] || [rawKey hasPrefix:@"'"]) key = GHYAMLUnquote(rawKey);
        NSString *valueText = GHYAMLTrim([line.text substringFromIndex:separator + 1]);
        dict[key] = [self parseValueText:valueText parentIndent:indent];
    }
    return dict;
}

- (id)parseValueText:(NSString *)text parentIndent:(NSInteger)indent {
    if (text.length == 0 || [text hasPrefix:@"#"]) {
        GHYAMLLine *next = [self currentLine];
        if (next == nil) return [NSNull null];
        if (next.indent > indent) return [self parseNodeWithMinimumIndent:next.indent];
        if (next.indent == indent && GHYAMLIsSequenceEntry(next.text)) return [self parseSequenceAtIndent:indent];
        return [NSNull null];
    }

    unichar first = [text characterAtIndex:0];
    if (first == '|' || first == '>') return [self parseBlockScalarWithHeader:text parentIndent:indent];

    if (first == '"' || first == '\'') {
        NSMutableString *joined = [text mutableCopy];
        while (GHYAMLClosingQuoteIndex(joined, 0) == NSNotFound && self.position < self.lines.count) {
            GHYAMLLine *line = self.lines[self.position];
            self.position++;
            NSString *piece = GHYAMLTrim(line.raw);
            [joined appendString:piece.length > 0 ? [@" " stringByAppendingString:piece] : @"\n"];
        }
        return GHYAMLUnquote(joined);
    }

    if (first == '[' || first == '{') {
        NSMutableString *joined = [text mutableCopy];
        while (!GHYAMLFlowIsBalanced(joined) && self.position < self.lines.count) {
            GHYAMLLine *line = self.lines[self.position];
            self.position++;
            [joined appendFormat:@" %@", GHYAMLTrim(line.raw)];
        }
        NSUInteger index = 0;
        return GHYAMLParseFlowValue(joined, &index, NO);
    }

    NSMutableString *joined = [GHYAMLStripComment(text) mutableCopy];
    while (YES) {
        GHYAMLLine *next = [self currentLine];
        if (next == nil || next.indent <= indent) break;
        self.position++;
        NSString *piece = GHYAMLStripComment(next.text);
        if (piece.length > 0) [joined appendFormat:@" %@", piece];
    }
    return GHYAMLPlainScalar(joined);
}

- (NSString *)parseBlockScalarWithHeader:(NSString *)header parentIndent:(NSInteger)indent {
    BOOL folded = [header characterAtIndex:0] == '>';
    BOOL strip = NO;
    BOOL keep = NO;
    NSInteger explicitIndent = 0;
    for (NSUInteger i = 1; i < header.length; i++) {
        unichar c = [header characterAtIndex:i];
        if (c == '-') strip = YES;
        else if (c == '+') keep = YES;
        else if (c >= '1' && c <= '9') explicitIndent = c - '0';
        else break;
    }

    NSInteger blockIndent = explicitIndent > 0 ? MAX(indent, 0) + explicitIndent : -1;
    NSMutableArray *content = [NSMutableArray array];
    while (self.position < self.lines.count) {
        GHYAMLLine *line = self.lines[self.position];
        NSString *raw = line.raw;
        if (GHYAMLTrim(raw).length == 0) {
            [content addObject:@""];
            self.position++;
            continue;
        }
        NSInteger lineIndent = GHYAMLLeadingSpaces(raw);
        if (lineIndent <= indent) break;
        if (blockIndent < 0) blockIndent = lineIndent;
        if (lineIndent < blockIndent) break;
        [content addObject:[raw substringFromIndex:blockIndent]];
        self.position++;
    }

    NSInteger trailingBlankLines = 0;
    while (content.count > 0 && [[content lastObject] length] == 0) {
        [content removeLastObject];
        trailingBlankLines++;
    }

    NSString *body = folded ? GHYAMLFoldLines(content) : [content componentsJoinedByString:@"\n"];
    if (body.length == 0) return @"";
    if (strip) return body;

    NSMutableString *result = [NSMutableString stringWithFormat:@"%@\n", body];
    if (keep) {
        for (NSInteger i = 0; i < trailingBlankLines; i++) [result appendString:@"\n"];
    }
    return result;
}

@end

NSString *GHYAMLString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            return [value boolValue] ? @"true" : @"false";
        }
        return [value stringValue];
    }
    return nil;
}

BOOL GHYAMLBool(id value, BOOL defaultValue) {
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    if ([value isKindOfClass:[NSString class]]) {
        NSString *lower = [GHYAMLTrim(value) lowercaseString];
        if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"yes"] || [lower isEqualToString:@"on"]) return YES;
        if ([lower isEqualToString:@"false"] || [lower isEqualToString:@"no"] || [lower isEqualToString:@"off"]) return NO;
    }
    return defaultValue;
}

NSArray *GHYAMLStringList(id value) {
    NSArray *items = nil;
    if ([value isKindOfClass:[NSArray class]]) {
        items = value;
    } else if ([value isKindOfClass:[NSString class]]) {
        items = [value componentsSeparatedByString:@","];
    } else {
        return @[];
    }

    NSMutableArray *result = [NSMutableArray array];
    for (id item in items) {
        NSString *string = GHYAMLTrim(GHYAMLString(item) ?: @"");
        if (string.length > 0) [result addObject:string];
    }
    return result;
}
