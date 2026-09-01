#import "GHMarkdownRenderer.h"
#import "GHThemeManager.h"
#import "GHLocalization.h"
#import <UIKit/UIKit.h>

static const NSUInteger kStackTableColumnThreshold = 3;

@implementation GHMarkdownRenderer

+ (NSString *)replaceMatchesInString:(NSString *)string
                              pattern:(NSString *)pattern
                              options:(NSRegularExpressionOptions)options
                            transform:(NSString *(^)(NSArray *groups))transform {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                            options:options
                                                                              error:&error];
    if (!regex) return string;

    NSMutableString *result = [NSMutableString string];
    __block NSUInteger lastLocation = 0;

    [regex enumerateMatchesInString:string
                             options:0
                               range:NSMakeRange(0, string.length)
                          usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        [result appendString:[string substringWithRange:NSMakeRange(lastLocation, match.range.location - lastLocation)]];

        NSMutableArray *groups = [NSMutableArray array];
        for (NSUInteger i = 1; i < match.numberOfRanges; i++) {
            NSRange r = [match rangeAtIndex:i];
            [groups addObject:(r.location == NSNotFound) ? @"" : [string substringWithRange:r]];
        }
        [result appendString:transform(groups)];
        lastLocation = match.range.location + match.range.length;
    }];

    [result appendString:[string substringFromIndex:lastLocation]];
    return result;
}

+ (NSString *)extractFencedCodeBlocksFromMarkdown:(NSString *)markdown
                                    intoCodeBlocks:(NSMutableArray *)codeBlocks {
    if (markdown.length == 0) return markdown ?: @"";

    static NSRegularExpression *fenceLineRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{

        fenceLineRegex = [NSRegularExpression regularExpressionWithPattern:@"^([ \\t]*)(`{3,})[^`]*$"
                                                                     options:0
                                                                       error:nil];
    });

    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    NSMutableArray *outputLines = [NSMutableArray array];
    NSUInteger lineIndex = 0;

    while (lineIndex < lines.count) {
        NSString *line = lines[lineIndex];
        NSTextCheckingResult *openMatch = [fenceLineRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];

        if (!openMatch) {
            [outputLines addObject:line];
            lineIndex++;
            continue;
        }

        NSString *fenceChars = [line substringWithRange:[openMatch rangeAtIndex:2]];
        NSUInteger closeLineIndex = NSNotFound;
        for (NSUInteger j = lineIndex + 1; j < lines.count; j++) {
            NSString *candidate = lines[j];
            NSString *trimmedCandidate = [candidate stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            BOOL isAllBackticks = trimmedCandidate.length >= fenceChars.length;
            if (isAllBackticks) {
                for (NSUInteger k = 0; k < trimmedCandidate.length; k++) {
                    if ([trimmedCandidate characterAtIndex:k] != '`') { isAllBackticks = NO; break; }
                }
            }
            if (isAllBackticks) { closeLineIndex = j; break; }
        }

        if (closeLineIndex == NSNotFound) {

            [outputLines addObject:line];
            lineIndex++;
            continue;
        }

        NSMutableArray *codeLines = [NSMutableArray array];
        for (NSUInteger j = lineIndex + 1; j < closeLineIndex; j++) {
            [codeLines addObject:lines[j]];
        }
        NSString *code = [self escapeHTML:[codeLines componentsJoinedByString:@"\n"]];
        NSString *html = [NSString stringWithFormat:@"<pre><code>%@</code></pre>", code];
        [codeBlocks addObject:html];
        [outputLines addObject:[NSString stringWithFormat:@"\x02CODEBLOCK%lu\x03", (unsigned long)(codeBlocks.count - 1)]];

        lineIndex = closeLineIndex + 1;
    }

    return [outputLines componentsJoinedByString:@"\n"];
}

+ (NSString *)escapeHTML:(NSString *)text {
    text = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    text = [text stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    text = [text stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return text;
}

+ (NSString *)escapeHTMLAttribute:(NSString *)text {
    text = [self escapeHTML:text];
    text = [text stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return text;
}

+ (NSString *)escapePlainTextPreservingHTML:(NSString *)text {
    text = [self replaceMatchesInString:text
        pattern:@"&(?!(?:[a-zA-Z]+|#[0-9]+|#x[0-9a-fA-F]+);)"
        options:0
        transform:^NSString *(NSArray *groups) {
            return @"&amp;";
        }];

    text = [self replaceMatchesInString:text
        pattern:@"<(?![a-zA-Z/!])"
        options:0
        transform:^NSString *(NSArray *groups) {
            return @"&lt;";
        }];

    return text;
}

+ (NSArray *)tableCellsFromLine:(NSString *)line {
    NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([trimmedLine hasPrefix:@"|"]) {
        trimmedLine = [trimmedLine substringFromIndex:1];
    }
    if ([trimmedLine hasSuffix:@"|"]) {
        trimmedLine = [trimmedLine substringToIndex:trimmedLine.length - 1];
    }

    NSArray *rawCells = [trimmedLine componentsSeparatedByString:@"|"];
    NSMutableArray *cells = [NSMutableArray array];
    for (NSString *cell in rawCells) {
        [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    }
    return cells;
}

+ (NSString *)htmlFromTableCell:(id)cell {
    if ([cell isKindOfClass:[NSDictionary class]]) {
        NSString *html = ((NSDictionary *)cell)[@"html"];
        return html.length > 0 ? html : @"";
    }
    return [cell isKindOfClass:[NSString class]] ? cell : @"";
}

+ (NSUInteger)colspanFromTableCell:(id)cell {
    if ([cell isKindOfClass:[NSDictionary class]]) {
        NSUInteger colspan = [((NSDictionary *)cell)[@"colspan"] unsignedIntegerValue];
        return MAX((NSUInteger)1, colspan);
    }
    return 1;
}

+ (NSString *)anchorSlugFromHeadingHTML:(NSString *)headingHTML {
    if (headingHTML.length == 0) return @"";

    NSString *text = [headingHTML stringByReplacingOccurrencesOfString:@"<[^>]+>"
                                                           withString:@""
                                                              options:NSRegularExpressionSearch
                                                                range:NSMakeRange(0, headingHTML.length)];
    text = [text stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    text = [text stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    text = [text stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    text = [text stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    text = [text lowercaseString];

    NSMutableString *slug = [NSMutableString stringWithCapacity:text.length];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];

    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([letters characterIsMember:c] || [digits characterIsMember:c] || c == '-' || c == '_') {
            [slug appendFormat:@"%C", c];
        } else if (c == ' ') {
            [slug appendString:@"-"];
        }

    }
    return slug;
}

+ (NSString *)tableMarkupWithHeaderCells:(NSArray *)headerCells rows:(NSArray *)rows {
    NSMutableString *tableHTML = [NSMutableString string];
    if (headerCells.count > kStackTableColumnThreshold) {
        [tableHTML appendString:@"<div class=\"table-stack\">"];
        for (NSArray *rowCells in rows) {
            [tableHTML appendString:@"<div class=\"table-stack-row\">"];
            for (NSUInteger i = 0; i < rowCells.count; i++) {
                NSString *cellHTML = [self htmlFromTableCell:rowCells[i]];

                if ([self colspanFromTableCell:rowCells[i]] > 1) {
                    [tableHTML appendFormat:@"<div class=\"table-stack-cell\">%@</div>", cellHTML];
                    continue;
                }
                NSString *label = i < headerCells.count ? [self htmlFromTableCell:headerCells[i]] : @"";
                [tableHTML appendFormat:@"<div class=\"table-stack-cell\">"
                                          "<span class=\"table-stack-label\">%@</span>%@</div>",
                                         label, cellHTML];
            }
            [tableHTML appendString:@"</div>"];
        }
        [tableHTML appendString:@"</div>"];
    } else {
        [tableHTML appendString:@"<div class=\"table-scroll\"><table><thead><tr>"];
        for (id headerCell in headerCells) {
            [tableHTML appendFormat:@"<th>%@</th>", [self htmlFromTableCell:headerCell]];
        }
        [tableHTML appendString:@"</tr></thead><tbody>"];
        for (NSArray *rowCells in rows) {
            [tableHTML appendString:@"<tr>"];
            for (id cell in rowCells) {
                NSUInteger colspan = [self colspanFromTableCell:cell];

                if (colspan > 1) {
                    [tableHTML appendFormat:@"<td colspan=\"%lu\">%@</td>",
                                            (unsigned long)colspan, [self htmlFromTableCell:cell]];
                } else {
                    [tableHTML appendFormat:@"<td>%@</td>", [self htmlFromTableCell:cell]];
                }
            }
            [tableHTML appendString:@"</tr>"];
        }
        [tableHTML appendString:@"</tbody></table></div>"];
    }
    return tableHTML;
}

+ (NSUInteger)colspanFromTagAttributes:(NSString *)attributes {
    if (attributes.length == 0) return 1;

    static NSRegularExpression *colspanRegex = nil;
    static dispatch_once_t colspanOnceToken;
    dispatch_once(&colspanOnceToken, ^{
        colspanRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bcolspan\\s*=\\s*\"?(\\d+)"
                                                                 options:NSRegularExpressionCaseInsensitive
                                                                   error:nil];
    });
    if (!colspanRegex) return 1;

    NSTextCheckingResult *match = [colspanRegex firstMatchInString:attributes
                                                           options:0
                                                             range:NSMakeRange(0, attributes.length)];
    if (!match || match.numberOfRanges < 2) return 1;

    NSInteger value = [[attributes substringWithRange:[match rangeAtIndex:1]] integerValue];
    return value > 1 ? (NSUInteger)value : 1;
}

+ (NSString *)plainLabelFromTableCellHTML:(NSString *)cellHTML {
    if (cellHTML.length == 0) return @"";

    NSTextCheckingResult *altMatch = nil;
    static NSRegularExpression *altRegex = nil;
    static dispatch_once_t altOnceToken;
    dispatch_once(&altOnceToken, ^{
        altRegex = [NSRegularExpression regularExpressionWithPattern:@"<img\\b[^>]*\\balt=\"([^\"]*)\""
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
    });
    if (altRegex) {
        altMatch = [altRegex firstMatchInString:cellHTML options:0 range:NSMakeRange(0, cellHTML.length)];
    }
    if (altMatch && [altMatch rangeAtIndex:1].length > 0) {
        return [cellHTML substringWithRange:[altMatch rangeAtIndex:1]];
    }

    NSString *stripped = [cellHTML stringByReplacingOccurrencesOfString:@"<[^>]+>"
                                                                withString:@""
                                                                   options:NSRegularExpressionSearch
                                                                     range:NSMakeRange(0, cellHTML.length)];
    return [stripped stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)rasterizeLogoBadgesInHTML:(NSString *)html {
    if (html.length == 0 || [html rangeOfString:@"img.shields.io" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return html ?: @"";
    }

    static NSArray *githubSocialBadgePathFragments = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        githubSocialBadgePathFragments = @[@"/github/stars/", @"/github/forks/",
                                            @"/github/watchers/", @"/github/followers/"];
    });

    return [self replaceMatchesInString:html
        pattern:@"\\bsrc=\"(https://img\\.shields\\.io/[^\"]*)\""
        options:NSRegularExpressionCaseInsensitive
        transform:^NSString *(NSArray *groups) {
            NSString *url = groups[0];

            BOOL mayHaveLogo = [url rangeOfString:@"logo=" options:NSCaseInsensitiveSearch].location != NSNotFound;
            if (!mayHaveLogo) {
                for (NSString *fragment in githubSocialBadgePathFragments) {
                    if ([url rangeOfString:fragment options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        mayHaveLogo = YES;
                        break;
                    }
                }
            }
            if (!mayHaveLogo) {
                return [NSString stringWithFormat:@"src=\"%@\"", url];
            }

            NSString *rasterURL = [url stringByReplacingOccurrencesOfString:@"://img.shields.io/"
                                                                    withString:@"://raster.shields.io/"
                                                                       options:NSCaseInsensitiveSearch
                                                                         range:NSMakeRange(0, url.length)];
            return [NSString stringWithFormat:@"src=\"%@\"", rasterURL];
        }];
}

+ (NSString *)restyleRawHTMLTablesInHTML:(NSString *)html {
    if (html.length == 0 || [html rangeOfString:@"<table" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return html ?: @"";
    }

    static NSRegularExpression *rowRegex = nil;
    static NSRegularExpression *cellRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        rowRegex = [NSRegularExpression regularExpressionWithPattern:@"<tr\\b[^>]*>([\\s\\S]*?)</tr\\s*>"
                                                               options:NSRegularExpressionCaseInsensitive
                                                                 error:nil];

        cellRegex = [NSRegularExpression regularExpressionWithPattern:@"<t[hd]\\b([^>]*)>([\\s\\S]*?)</t[hd]\\s*>"
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
    });
    if (!rowRegex || !cellRegex) return html;

    return [self replaceMatchesInString:html
        pattern:@"<table\\b[^>]*>([\\s\\S]*?)</table\\s*>"
        options:NSRegularExpressionCaseInsensitive
        transform:^NSString *(NSArray *groups) {
            NSString *innerHTML = groups[0];

            NSMutableArray *rows = [NSMutableArray array];
            [rowRegex enumerateMatchesInString:innerHTML
                                        options:0
                                          range:NSMakeRange(0, innerHTML.length)
                                     usingBlock:^(NSTextCheckingResult *rowMatch, NSMatchingFlags flags, BOOL *stopRow) {
                NSString *rowInnerHTML = [innerHTML substringWithRange:[rowMatch rangeAtIndex:1]];
                NSMutableArray *cells = [NSMutableArray array];
                [cellRegex enumerateMatchesInString:rowInnerHTML
                                             options:0
                                               range:NSMakeRange(0, rowInnerHTML.length)
                                          usingBlock:^(NSTextCheckingResult *cellMatch, NSMatchingFlags cellFlags, BOOL *stopCell) {
                    NSString *cellAttributes = [rowInnerHTML substringWithRange:[cellMatch rangeAtIndex:1]];
                    NSString *cellHTML = [rowInnerHTML substringWithRange:[cellMatch rangeAtIndex:2]];
                    NSString *trimmed = [cellHTML stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

                    NSUInteger colspan = [self colspanFromTagAttributes:cellAttributes];
                    if (colspan > 1) {
                        [cells addObject:@{@"html": trimmed, @"colspan": @(colspan)}];
                    } else {
                        [cells addObject:trimmed];
                    }
                }];
                if (cells.count > 0) [rows addObject:cells];
            }];

            if (rows.count == 0) {
                return [NSString stringWithFormat:@"<table>%@</table>", innerHTML];
            }

            NSArray *headerRowCells = rows[0];
            NSMutableArray *headerLabels = [NSMutableArray array];
            for (id headerCell in headerRowCells) {
                [headerLabels addObject:[self plainLabelFromTableCellHTML:[self htmlFromTableCell:headerCell]]];
            }

            NSArray *dataRows = rows.count > 1
                ? [rows subarrayWithRange:NSMakeRange(1, rows.count - 1)]
                : rows;

            return [self tableMarkupWithHeaderCells:headerLabels rows:dataRows];
        }];
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown {
    return [self bodyHTMLFromMarkdown:markdown repoOwner:nil repoName:nil progress:nil];
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown progress:(void (^)(NSString *stepName))progressBlock {
    return [self bodyHTMLFromMarkdown:markdown repoOwner:nil repoName:nil progress:progressBlock];
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown repoOwner:(NSString *)repoOwner repoName:(NSString *)repoName {
    return [self bodyHTMLFromMarkdown:markdown repoOwner:repoOwner repoName:repoName progress:nil];
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                          repoOwner:(NSString *)repoOwner
                           repoName:(NSString *)repoName
                           progress:(void (^)(NSString *stepName))progressBlock {
    return [self bodyHTMLFromMarkdown:markdown repoOwner:repoOwner repoName:repoName repoDefaultBranch:nil progress:progressBlock];
}

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                          repoOwner:(NSString *)repoOwner
                           repoName:(NSString *)repoName
                  repoDefaultBranch:(NSString *)repoDefaultBranch
                           progress:(void (^)(NSString *stepName))progressBlock {
    void (^step)(NSString *) = ^(NSString *name) {
        if (progressBlock) progressBlock(name);
    };
    step(@"старт");

    NSMutableArray *codeBlocks = [NSMutableArray array];
    NSMutableArray *inlineCodes = [NSMutableArray array];

    NSString *text = [self extractFencedCodeBlocksFromMarkdown:markdown intoCodeBlocks:codeBlocks];
    step(@"1-код-блоки");

    text = [self replaceMatchesInString:text
        pattern:@"`([^`\\n]+)`"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *code = [self escapeHTML:groups[0]];
            NSString *html = [NSString stringWithFormat:@"<code>%@</code>", code];
            [inlineCodes addObject:html];
            return [NSString stringWithFormat:@"\x02INLINECODE%lu\x03", (unsigned long)(inlineCodes.count - 1)];
        }];
    step(@"2-инлайн-код");

    NSMutableDictionary *linkDefinitions = [NSMutableDictionary dictionary];
    text = [self replaceMatchesInString:text
        pattern:@"^\\[([^\\]]+)\\]:\\s*(\\S+).*$"
        options:NSRegularExpressionAnchorsMatchLines
        transform:^NSString *(NSArray *groups) {
            NSString *label = [groups[0] lowercaseString];
            NSString *url = groups[1];
            linkDefinitions[label] = url;
            return @"";
        }];
    step(@"2b-определения-ссылок");

    if (linkDefinitions.count > 0) {
        text = [self replaceMatchesInString:text
            pattern:@"\\[([^\\]]+)\\]\\[([^\\]]*)\\]"
            options:0
            transform:^NSString *(NSArray *groups) {
                NSString *linkText = groups[0];
                NSString *labelGroup = groups[1];
                NSString *label = labelGroup.length > 0 ? labelGroup : groups[0];
                NSString *url = linkDefinitions[[label lowercaseString]];
                if (url.length == 0) {
                    return [NSString stringWithFormat:@"[%@][%@]", groups[0], groups[1]];
                }
                return [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", url, linkText];
            }];
        step(@"2d-ссылки-по-метке");
    }

    NSMutableArray *htmlTags = [NSMutableArray array];
    text = [self replaceMatchesInString:text
        pattern:@"<(/?[a-zA-Z][^<>]*)>"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *tagHTML = [NSString stringWithFormat:@"<%@>", groups[0]];
            [htmlTags addObject:tagHTML];
            return [NSString stringWithFormat:@"\x02HTMLTAG%lu\x03", (unsigned long)(htmlTags.count - 1)];
        }];
    step(@"2e-html-теги");

    text = [self escapePlainTextPreservingHTML:text];
    step(@"3-экранирование");

    text = [self replaceMatchesInString:text
        pattern:@"^(#{1,6})\\s+(.+)$"
        options:NSRegularExpressionAnchorsMatchLines
        transform:^NSString *(NSArray *groups) {
            NSUInteger level = ((NSString *)groups[0]).length;

            NSString *slug = [self anchorSlugFromHeadingHTML:groups[1]];
            if (slug.length > 0) {
                return [NSString stringWithFormat:@"<h%lu id=\"%@\">%@</h%lu>",
                                                  (unsigned long)level, slug, groups[1], (unsigned long)level];
            }
            return [NSString stringWithFormat:@"<h%lu>%@</h%lu>", (unsigned long)level, groups[1], (unsigned long)level];
        }];
    step(@"4-заголовки");

    text = [self replaceMatchesInString:text
        pattern:@"^(-{3,}|\\*{3,})$"
        options:NSRegularExpressionAnchorsMatchLines
        transform:^NSString *(NSArray *groups) {
            return @"<hr/>";
        }];
    step(@"5-hr");

    BOOL hasRepoContext = repoOwner.length > 0 && repoName.length > 0;
    NSString *urlAlternative = @"(?<![(\"'])(https?://[^\\s<>()\"']+)";

    NSString *shaAlternative = @"(?<![\\w/@\"'-])([0-9a-fA-F]{7,40})(?![\\w-])";
    NSString *combinedPattern = hasRepoContext
        ? [NSString stringWithFormat:@"%@|%@", urlAlternative, shaAlternative]
        : urlAlternative;

    text = [self replaceMatchesInString:text
        pattern:combinedPattern
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *url = groups[0];
            NSString *bareSHA = hasRepoContext ? groups[1] : @"";

            if (url.length > 0) {

                static NSRegularExpression *commitRegex = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    commitRegex = [NSRegularExpression regularExpressionWithPattern:
                        @"^https?://github\\.com/([^/]+)/([^/]+)/commit/([0-9a-fA-F]{7,40})"
                                                                            options:NSRegularExpressionCaseInsensitive
                                                                              error:nil];
                });
                NSTextCheckingResult *commitMatch = [commitRegex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)];
                if (commitMatch) {
                    NSString *owner = [url substringWithRange:[commitMatch rangeAtIndex:1]];
                    NSString *repo = [url substringWithRange:[commitMatch rangeAtIndex:2]];
                    NSString *sha = [url substringWithRange:[commitMatch rangeAtIndex:3]];
                    NSString *shortSHA = sha.length > 7 ? [sha substringToIndex:7] : sha;
                    return [NSString stringWithFormat:
                        @"<a class=\"commit-ref\" href=\"%@\">%@/%@@<code>%@</code></a>",
                        url, owner, repo, shortSHA];
                }
                return [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", url, url];
            }

            NSString *shortSHA = bareSHA.length > 7 ? [bareSHA substringToIndex:7] : bareSHA;
            NSString *commitURL = [NSString stringWithFormat:@"https://github.com/%@/%@/commit/%@", repoOwner, repoName, bareSHA];
            return [NSString stringWithFormat:@"<a class=\"commit-ref\" href=\"%@\"><code>%@</code></a>", commitURL, shortSHA];
        }];
    step(@"5a-ссылки-на-коммиты-и-url");

    text = [self replaceMatchesInString:text
        pattern:@"!\\[([^\\]]*)\\]\\(([^)]+)\\)"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *rawAlt = groups[0];
            NSString *altAttr = rawAlt.length > 0 ? rawAlt : GHL(@"изображение");
            altAttr = [self escapeHTMLAttribute:altAttr];
            NSString *rawSrc = groups[1];
            if (repoDefaultBranch.length > 0 && repoOwner.length > 0 && repoName.length > 0
                && [rawSrc rangeOfString:@"://"].location == NSNotFound
                && ![rawSrc hasPrefix:@"//"]
                && ![rawSrc hasPrefix:@"data:"]) {
                NSString *relativePath = [rawSrc hasPrefix:@"/"] ? [rawSrc substringFromIndex:1] : rawSrc;
                rawSrc = [NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/%@/%@",
                          repoOwner, repoName, repoDefaultBranch, relativePath];
            }
            NSString *src = [self escapeHTMLAttribute:rawSrc];
            return [NSString stringWithFormat:@"<img src=\"%@\" alt=\"%@\"/>", src, altAttr];
        }];
    step(@"6-картинки");

    text = [self replaceMatchesInString:text
        pattern:@"\\[([^\\]]+)\\]\\(([^)]+)\\)"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *href = [self escapeHTMLAttribute:groups[1]];
            return [NSString stringWithFormat:@"<a href=\"%@\">%@</a>", href, groups[0]];
        }];
    step(@"7-ссылки");

    text = [self replaceMatchesInString:text
        pattern:@"<(/?[a-zA-Z][^<>]*)>"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *tagHTML = [NSString stringWithFormat:@"<%@>", groups[0]];
            [htmlTags addObject:tagHTML];
            return [NSString stringWithFormat:@"\x02HTMLTAG%lu\x03", (unsigned long)(htmlTags.count - 1)];
        }];
    step(@"7б-защита-собственных-тегов");

    text = [self replaceMatchesInString:text
        pattern:@"\\*\\*([^*]+)\\*\\*|__([^_]+)__"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *first = groups[0];
            NSString *content = first.length > 0 ? first : groups[1];
            return [NSString stringWithFormat:@"<strong>%@</strong>", content];
        }];
    step(@"8-жирный");

    text = [self replaceMatchesInString:text
        pattern:@"\\*([^*]+)\\*|_([^_]+)_"
        options:0
        transform:^NSString *(NSArray *groups) {
            NSString *first = groups[0];
            NSString *content = first.length > 0 ? first : groups[1];
            return [NSString stringWithFormat:@"<em>%@</em>", content];
        }];
    step(@"9-курсив");

    text = [self replaceMatchesInString:text
        pattern:@"(^>\\s?.*(?:\\n>\\s?.*)*)"
        options:NSRegularExpressionAnchorsMatchLines
        transform:^NSString *(NSArray *groups) {
            NSString *block = groups[0];
            NSArray *lines = [block componentsSeparatedByString:@"\n"];
            NSMutableArray *cleaned = [NSMutableArray array];
            for (NSString *line in lines) {
                NSString *stripped = [line stringByReplacingOccurrencesOfString:@"^>\\s?"
                                                                       withString:@""
                                                                          options:NSRegularExpressionSearch
                                                                            range:NSMakeRange(0, line.length)];
                [cleaned addObject:stripped];
            }
            return [NSString stringWithFormat:@"<blockquote>%@</blockquote>", [cleaned componentsJoinedByString:@"<br/>"]];
        }];
    step(@"10-цитаты");

    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray *outputLines = [NSMutableArray array];
    NSMutableArray *currentListItems = [NSMutableArray array];
    BOOL inOrderedList = NO;

    NSRegularExpression *taskRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\[([ xX])\\]\\s+(.*)$" options:0 error:nil];

    void (^flushList)(void) = ^{
        if (currentListItems.count == 0) return;
        NSString *tag = inOrderedList ? @"ol" : @"ul";
        NSMutableString *listHTML = [NSMutableString stringWithFormat:@"<%@>", tag];
        for (NSString *item in currentListItems) {
            NSTextCheckingResult *taskMatch = [taskRegex firstMatchInString:item options:0 range:NSMakeRange(0, item.length)];
            if (taskMatch) {
                BOOL checked = [[item substringWithRange:[taskMatch rangeAtIndex:1]] caseInsensitiveCompare:@"x"] == NSOrderedSame;
                NSString *label = [item substringWithRange:[taskMatch rangeAtIndex:2]];
                [listHTML appendFormat:@"<li class=\"task-list-item\"><input type=\"checkbox\" disabled=\"disabled\"%@/>%@</li>",
                    checked ? @" checked=\"checked\"" : @"", label];
            } else {
                [listHTML appendFormat:@"<li>%@</li>", item];
            }
        }
        [listHTML appendFormat:@"</%@>", tag];
        [outputLines addObject:listHTML];
        [currentListItems removeAllObjects];
    };

    NSRegularExpression *unorderedRegex = [NSRegularExpression regularExpressionWithPattern:@"^[-*+]\\s+(.+)$" options:0 error:nil];
    NSRegularExpression *orderedRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d+\\.\\s+(.+)$" options:0 error:nil];
    NSRegularExpression *tableSeparatorRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\|?\\s*:?-{2,}:?\\s*(\\|\\s*:?-{2,}:?\\s*)*\\|?\\s*$" options:0 error:nil];

    NSUInteger lineIndex = 0;
    while (lineIndex < lines.count) {
        NSString *line = lines[lineIndex];

        BOOL looksLikeTableHeader = [line rangeOfString:@"|"].location != NSNotFound;
        BOOL nextIsSeparator = NO;
        if (looksLikeTableHeader && lineIndex + 1 < lines.count) {
            NSString *nextLine = lines[lineIndex + 1];
            nextIsSeparator = [tableSeparatorRegex firstMatchInString:nextLine options:0 range:NSMakeRange(0, nextLine.length)] != nil
                              && [nextLine rangeOfString:@"-"].location != NSNotFound;
        }

        if (looksLikeTableHeader && nextIsSeparator) {
            flushList();

            NSArray *headerCells = [self tableCellsFromLine:line];
            lineIndex += 2;

            NSMutableArray *rows = [NSMutableArray array];
            while (lineIndex < lines.count && [lines[lineIndex] rangeOfString:@"|"].location != NSNotFound) {
                [rows addObject:[self tableCellsFromLine:lines[lineIndex]]];
                lineIndex++;
            }

            NSString *tableHTML = [self tableMarkupWithHeaderCells:headerCells rows:rows];
            [outputLines addObject:tableHTML];
            continue;
        }

        NSTextCheckingResult *uMatch = [unorderedRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSTextCheckingResult *oMatch = [orderedRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];

        if (uMatch) {
            if (inOrderedList) flushList();
            inOrderedList = NO;
            [currentListItems addObject:[line substringWithRange:[uMatch rangeAtIndex:1]]];
        } else if (oMatch) {
            if (!inOrderedList) flushList();
            inOrderedList = YES;
            [currentListItems addObject:[line substringWithRange:[oMatch rangeAtIndex:1]]];
        } else {
            flushList();
            [outputLines addObject:line];
        }

        lineIndex++;
    }
    flushList();
    text = [outputLines componentsJoinedByString:@"\n"];
    step(@"11-списки-таблицы");

    NSArray *blocks = [text componentsSeparatedByString:@"\n\n"];
    NSMutableArray *paragraphs = [NSMutableArray array];
    for (NSString *block in blocks) {
        NSString *trimmed = [block stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;

        BOOL isBlockTag = [trimmed hasPrefix:@"<"] || [trimmed hasPrefix:@"\x02CODEBLOCK"] || [trimmed hasPrefix:@"\x02HTMLTAG"];

        if (isBlockTag) {
            [paragraphs addObject:trimmed];
        } else {
            NSString *withBreaks = [trimmed stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"];
            [paragraphs addObject:[NSString stringWithFormat:@"<p>%@</p>", withBreaks]];
        }
    }
    text = [paragraphs componentsJoinedByString:@"\n"];
    step(@"12-абзацы");

    for (NSUInteger i = 0; i < codeBlocks.count; i++) {
        NSString *placeholder = [NSString stringWithFormat:@"\x02CODEBLOCK%lu\x03", (unsigned long)i];
        text = [text stringByReplacingOccurrencesOfString:placeholder withString:codeBlocks[i]];
    }
    step(@"13a-восстановление-код-блоков");

    for (NSUInteger i = 0; i < inlineCodes.count; i++) {
        NSString *placeholder = [NSString stringWithFormat:@"\x02INLINECODE%lu\x03", (unsigned long)i];
        text = [text stringByReplacingOccurrencesOfString:placeholder withString:inlineCodes[i]];
    }
    step(@"13b-восстановление-инлайн-кода");

    for (NSUInteger i = 0; i < htmlTags.count; i++) {
        NSString *placeholder = [NSString stringWithFormat:@"\x02HTMLTAG%lu\x03", (unsigned long)i];
        text = [text stringByReplacingOccurrencesOfString:placeholder withString:htmlTags[i]];
    }
    step(@"13c-восстановление-html-тегов");

    step(@"13d-пропущено-растеризация-бейджиков-отключена");

    text = [self restyleRawHTMLTablesInHTML:text];
    step(@"13e-сырые-html-таблицы");

    step(@"13-восстановление-плейсхолдеров");
    return text;
}

+ (NSString *)htmlDocumentFromMarkdown:(NSString *)markdown {
    NSString *body = [self bodyHTMLFromMarkdown:markdown ?: @""];
    return [self htmlDocumentWrappingBody:body];
}

+ (NSString *)htmlDocumentFromMarkdown:(NSString *)markdown pixelWidth:(CGFloat)pixelWidth {
    NSString *body = [self bodyHTMLFromMarkdown:markdown ?: @""];
    return [self htmlDocumentWrappingBody:body pixelWidth:pixelWidth];
}

+ (NSString *)htmlDocumentWrappingBody:(NSString *)bodyHTML {
    return [self htmlDocumentWrappingBody:bodyHTML pixelWidth:0];
}

+ (NSString *)inlineUserAttachmentImagesInHTML:(NSString *)html
                                     ownerLogin:(NSString *)ownerLogin
                                       repoName:(NSString *)repoName {
    if (html.length == 0 || ownerLogin.length == 0 || repoName.length == 0) return html ?: @"";

    static NSRegularExpression *attachmentImgRegex = nil;
    static dispatch_once_t onceToken;

    html = [self rasterizeRemoteSVGImagesInHTML:html];

    dispatch_once(&onceToken, ^{

        attachmentImgRegex = [NSRegularExpression regularExpressionWithPattern:
            @"\\bsrc=\"(https://(?:github\\.com/user-attachments/assets/"
             "|private-user-images\\.githubusercontent\\.com/"
             "|user-images\\.githubusercontent\\.com/"
             "|data\\.jsdelivr\\.com/)[^\"]+)\""
                                                                        options:0
                                                                          error:nil];
    });
    if (!attachmentImgRegex) return html;

    NSMutableArray *urls = [NSMutableArray array];
    [attachmentImgRegex enumerateMatchesInString:html
                                          options:0
                                            range:NSMakeRange(0, html.length)
                                       usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSString *urlString = [html substringWithRange:[match rangeAtIndex:1]];
        if (![urls containsObject:urlString]) [urls addObject:urlString];
    }];
    if (urls.count == 0) return html;

    static const NSUInteger kMaxInlinedImages = 6;
    static const NSUInteger kMaxTotalInlinedBytes = 1500 * 1024;

    NSUInteger inlinedCount = 0;
    NSUInteger inlinedBytes = 0;

    NSMutableArray *diagnostics = [NSMutableArray array];

    NSMutableString *result = [html mutableCopy];
    for (NSString *urlString in urls) {
        NSString *replacement = nil;

        NSMutableArray *attemptFailures = [NSMutableArray array];

        BOOL isBadge = ([urlString rangeOfString:@"jsdelivr.com" options:NSCaseInsensitiveSearch].location != NSNotFound);
        if (isBadge) {
            NSString *badgeURL = [self proxiedImageURLStringForURLString:urlString asBadge:YES];
            if (badgeURL.length > 0) {
                [result replaceOccurrencesOfString:urlString
                                        withString:badgeURL
                                           options:0
                                             range:NSMakeRange(0, result.length)];
            }
            continue;
        }

        if (inlinedCount < kMaxInlinedImages && inlinedBytes < kMaxTotalInlinedBytes) {
            for (NSString *candidate in [self candidateSourceURLStringsForURLString:urlString]) {
                NSString *failureReason = nil;
                NSData *imageData = [self imageDataByFetchingURLString:candidate failureReason:&failureReason];

                if (imageData.length == 0) {
                    [attemptFailures addObject:[NSString stringWithFormat:@"%@ — %@",
                                                [NSURL URLWithString:candidate].host ?: candidate,
                                                failureReason ?: @"нет данных"]];
                    continue;
                }

                NSData *compressed = [self downscaledJPEGDataFromImageData:imageData];
                if (compressed.length == 0) {

                    [attemptFailures addObject:[NSString stringWithFormat:@"%@ — не удалось разобрать как картинку (%lu Б)",
                                                [NSURL URLWithString:candidate].host ?: candidate,
                                                (unsigned long)imageData.length]];
                    continue;
                }

                if ((inlinedBytes + compressed.length) > kMaxTotalInlinedBytes) break;

                NSString *base64 = [self base64StringFromData:compressed];
                if (base64.length == 0) break;

                replacement = [@"data:image/jpeg;base64," stringByAppendingString:base64];
                inlinedCount += 1;
                inlinedBytes += compressed.length;
                break;
            }
        }

        if (replacement.length == 0) {

            replacement = [self proxiedImageURLStringForURLString:urlString];

            if (replacement.length == 0) {
                [diagnostics addObjectsFromArray:attemptFailures];
            }
        }

        if (replacement.length == 0) continue;
        [result replaceOccurrencesOfString:urlString
                                 withString:replacement
                                    options:0
                                      range:NSMakeRange(0, result.length)];
    }

    if (diagnostics.count > 0) {
        NSMutableString *diagBlock = [NSMutableString string];
        [diagBlock appendString:@"<div style=\"margin:16px 0;padding:10px;border:1px solid #b34;"
                                 "border-radius:6px;font-size:12px;line-height:1.5;opacity:0.85\">"];
        [diagBlock appendString:@"<b>Картинки: не удалось загрузить</b><br/>"];
        for (NSString *line in diagnostics) {
            [diagBlock appendFormat:@"%@<br/>", [self escapeHTML:line]];
        }
        [diagBlock appendString:@"</div>"];
        [result appendString:diagBlock];
    }

    return result;
}

+ (NSArray *)candidateSourceURLStringsForURLString:(NSString *)urlString {
    if (urlString.length == 0) return @[];

    NSMutableArray *candidates = [NSMutableArray array];
    [candidates addObject:urlString];

    NSString *escaped = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"?" withString:@"%3F"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"=" withString:@"%3D"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@":" withString:@"%3A"];

    if (escaped.length > 0) {
        [candidates addObject:[NSString stringWithFormat:@"https://wsrv.nl/?w=640&output=jpg&url=%@", escaped]];
        [candidates addObject:[NSString stringWithFormat:@"https://images.weserv.nl/?w=640&output=jpg&url=%@", escaped]];
    }

    return candidates;
}

+ (NSData *)imageDataByFetchingURLString:(NSString *)urlString
                          failureReason:(NSString **)failureReason {
    if (urlString.length == 0) return nil;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (failureReason) *failureReason = @"некорректный адрес";
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:12.0];
    request.HTTPMethod = @"GET";
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 6_0 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10A5376e Safari/8536.25"
   forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://github.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"image/png,image/jpeg,image/gif,image/webp" forHTTPHeaderField:@"Accept"];

    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (error || data.length == 0) {

        NSString *reason = error ? [NSString stringWithFormat:@"%@ (код %ld)",
                                    error.localizedDescription ?: @"ошибка сети",
                                    (long)error.code]
                                 : @"пустой ответ";
        NSLog(@"GHMarkdownRenderer: не удалось скачать картинку %@ — %@", urlString, reason);
        if (failureReason) *failureReason = reason;
        return nil;
    }

    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
        if (statusCode < 200 || statusCode >= 300) {
            NSLog(@"GHMarkdownRenderer: картинка %@ вернула HTTP %ld", urlString, (long)statusCode);
            if (failureReason) *failureReason = [NSString stringWithFormat:@"HTTP %ld", (long)statusCode];
            return nil;
        }
    }

    return data;
}

+ (NSData *)downscaledJPEGDataFromImageData:(NSData *)imageData {
    if (imageData.length == 0) return nil;

    UIImage *image = [UIImage imageWithData:imageData];
    if (image == nil || image.size.width <= 0 || image.size.height <= 0) return nil;

    const CGFloat maxWidth = 640.0;
    CGSize targetSize = image.size;
    if (targetSize.width > maxWidth) {
        targetSize = CGSizeMake(maxWidth, floorf(image.size.height * (maxWidth / image.size.width)));
    }

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (resized == nil) return nil;
    return UIImageJPEGRepresentation(resized, 0.6);
}

+ (NSString *)base64StringFromData:(NSData *)data {
    if (data.length == 0) return nil;
    static const char table[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    const unsigned char *input = (const unsigned char *)data.bytes;
    NSUInteger length = data.length;

    NSMutableData *output = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
    char *out = (char *)output.mutableBytes;

    NSUInteger i = 0, j = 0;
    while (i + 2 < length) {
        out[j++] = table[(input[i] >> 2) & 0x3F];
        out[j++] = table[((input[i] & 0x3) << 4) | ((input[i + 1] >> 4) & 0xF)];
        out[j++] = table[((input[i + 1] & 0xF) << 2) | ((input[i + 2] >> 6) & 0x3)];
        out[j++] = table[input[i + 2] & 0x3F];
        i += 3;
    }

    if (i < length) {
        out[j++] = table[(input[i] >> 2) & 0x3F];
        if (i + 1 < length) {
            out[j++] = table[((input[i] & 0x3) << 4) | ((input[i + 1] >> 4) & 0xF)];
            out[j++] = table[(input[i + 1] & 0xF) << 2];
            out[j++] = '=';
        } else {
            out[j++] = table[(input[i] & 0x3) << 4];
            out[j++] = '=';
            out[j++] = '=';
        }
    }

    return [[NSString alloc] initWithBytes:output.bytes length:j encoding:NSASCIIStringEncoding];
}

+ (NSString *)resolvedFinalURLStringForPossibleRedirectURLString:(NSString *)urlString {
    if (urlString.length == 0) return urlString;
    if ([urlString rangeOfString:@"github.com/user-attachments/assets/" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return urlString;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return urlString;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                         timeoutInterval:8.0];

    request.HTTPMethod = @"GET";

    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 6_0 like Mac OS X) AppleWebKit/536.26 (KHTML, like Gecko) Version/6.0 Mobile/10A5376e Safari/8536.25"
    forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://github.com/" forHTTPHeaderField:@"Referer"];

    NSURLResponse *response = nil;
    NSError *error = nil;

    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];

    if (error || response.URL == nil) {

        return urlString;
    }
    return response.URL.absoluteString;
}

+ (NSString *)rasterizeRemoteSVGImagesInHTML:(NSString *)html {
    if (html.length == 0) return html;

    static NSRegularExpression *svgImgRegex = nil;
    static dispatch_once_t svgOnceToken;
    dispatch_once(&svgOnceToken, ^{

        svgImgRegex = [NSRegularExpression regularExpressionWithPattern:
            @"\\bsrc=\"(https?://[^\"]+?\\.svg(?:\\?[^\"]*)?)\""
                                                                options:NSRegularExpressionCaseInsensitive
                                                                  error:nil];
    });
    if (!svgImgRegex) return html;

    NSMutableArray *urls = [NSMutableArray array];
    [svgImgRegex enumerateMatchesInString:html
                                  options:0
                                    range:NSMakeRange(0, html.length)
                               usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        if (match.numberOfRanges < 2) return;
        NSString *url = [html substringWithRange:[match rangeAtIndex:1]];

        NSArray *skipHosts = @[@"shields.io", @"deepwiki.com", @"starchart.cc", @"badgen.net"];
        for (NSString *host in skipHosts) {
            if ([url rangeOfString:host options:NSCaseInsensitiveSearch].location != NSNotFound) return;
        }

        if (![urls containsObject:url]) [urls addObject:url];
    }];

    if (urls.count == 0) return html;

    NSMutableString *result = [html mutableCopy];
    for (NSString *urlString in urls) {
        NSString *proxied = [self proxiedImageURLStringForURLString:urlString];
        if (proxied.length == 0) continue;

        proxied = [proxied stringByAppendingString:@"&output=png"];
        [result replaceOccurrencesOfString:urlString
                                withString:proxied
                                   options:0
                                     range:NSMakeRange(0, result.length)];
    }
    return result;
}

+ (NSString *)proxiedImageURLStringForURLString:(NSString *)urlString {
    return [self proxiedImageURLStringForURLString:urlString asBadge:NO];
}

+ (NSString *)proxiedImageURLStringForURLString:(NSString *)urlString asBadge:(BOOL)isBadge {
    if (urlString.length == 0) return nil;

    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(
        NULL,
        (__bridge CFStringRef)urlString,
        NULL,
        CFSTR(":/?#[]@!$&'()*+,;="),
        kCFStringEncodingUTF8);
    if (!escaped) return nil;
    NSString *encodedTarget = (__bridge_transfer NSString *)escaped;

    if (isBadge) {
        return [NSString stringWithFormat:@"https://wsrv.nl/?h=40&we&_badge=1&url=%@", encodedTarget];
    }
    return [NSString stringWithFormat:@"https://wsrv.nl/?w=640&we&url=%@", encodedTarget];
}

+ (NSString *)htmlDocumentWrappingBody:(NSString *)bodyHTML pixelWidth:(CGFloat)pixelWidth {
    NSString *viewportWidth = (pixelWidth > 0)
        ? [NSString stringWithFormat:@"%.0f", pixelWidth]
        : @"device-width";

    NSString *css =

        @"*{-webkit-box-sizing:border-box;box-sizing:border-box;}"

        "html,body{max-width:100%;}"
        "body{font-family:-apple-system,Helvetica;font-size:15px;line-height:1.45;color:#000;margin:0;padding:12px 16px 16px 16px;word-wrap:break-word;overflow-wrap:break-word;}"

        "#readme-root{overflow-x:hidden;max-width:100%;}"
        "h1,h2,h3,h4,h5,h6{font-weight:bold;margin:14px 0 6px;line-height:1.25;}"
        "h1{font-size:22px;border-bottom:1px solid #ddd;padding-bottom:4px;}"
        "h2{font-size:19px;border-bottom:1px solid #eee;padding-bottom:3px;}"
        "h3{font-size:17px;}"
        "p{margin:8px 0;}"
        "a{color:#0366d6;text-decoration:none;word-wrap:break-word;overflow-wrap:break-word;}"
        "code{background:#f2f2f2;padding:1px 4px;border-radius:3px;font-family:Menlo,monospace;font-size:13px;word-wrap:break-word;overflow-wrap:break-word;}"
        "pre{background:#f6f8fa;padding:10px;border-radius:5px;overflow-x:auto;max-width:100%;box-sizing:border-box;}"

        "pre code{background:transparent;padding:0;white-space:pre-wrap;word-wrap:break-word;overflow-wrap:break-word;word-break:break-word;}"
        "blockquote{border-left:3px solid #ddd;margin:8px 0;padding:2px 12px;color:#555;}"
        "ul,ol{margin:6px 0;padding-left:22px;}"
        "li{margin:3px 0;word-wrap:break-word;overflow-wrap:break-word;}"

        "li.task-list-item{list-style:none;margin-left:-18px;}"
        "li.task-list-item input{margin-right:6px;vertical-align:middle;}"
        "img{max-width:100%;height:auto;}"

        "img[src*=\"_badge=1\"]{height:20px;width:auto;max-width:100%;}"
        "hr{border:none;border-top:1px solid #ddd;margin:14px 0;}"

        "table{border-collapse:collapse;margin:10px 0;font-size:14px;box-sizing:border-box;}"
        ".table-scroll{overflow-x:auto;margin:10px 0;-webkit-overflow-scrolling:touch;}"
        ".table-scroll table{margin:0;width:auto;}"

        ".table-scroll th,.table-scroll td{min-width:110px;}"

        ".table-stack{margin:10px 0;}"
        ".table-stack-row{border:1px solid #ddd;border-radius:6px;padding:8px 10px;margin:0 0 8px;}"
        ".table-stack-cell{padding:4px 0;}"
        ".table-stack-cell:not(:last-child){border-bottom:1px solid #eee;}"
        ".table-stack-label{display:block;font-size:11px;text-transform:uppercase;"
        "letter-spacing:0.03em;color:#888;margin-bottom:2px;}"

        "th,td{border:1px solid #ddd;padding:6px 8px;text-align:left;word-wrap:break-word;overflow-wrap:break-word;box-sizing:border-box;}"
        "th{background:#f6f8fa;font-weight:bold;}"

        ".show-more{display:block;box-sizing:border-box;width:100%;padding:10px 12px;text-align:center;"
        "color:#0366d6;font-size:14px;font-weight:bold;background:#f6f8fa;border:1px solid #ddd;"
        "border-radius:6px;margin:14px 0;text-decoration:none;}"

        ".readme-clip{max-height:280px;overflow:hidden;position:relative;}"

        ".readme-clip::after{content:'';position:absolute;left:0;right:0;bottom:0;height:56px;"
        "background:linear-gradient(rgba(255,255,255,0),rgba(255,255,255,0.96));pointer-events:none;}"
        ".readme-loading{padding:10px 12px;text-align:center;color:#666;font-size:13px;}"

        ".issue-header{padding-bottom:4px;}"
        ".issue-state{font-size:13px;font-weight:bold;margin-bottom:4px;}"
        ".issue-title{margin:0 0 6px;}"
        ".issue-meta{font-size:13px;color:#666;}"

        ".avatar{width:18px;height:18px;border-radius:50%;vertical-align:middle;margin-right:5px;}"

        ".commit-ref{text-decoration:none;}"
        ".commit-ref code{background:#eee;border-radius:4px;padding:1px 5px;font-size:0.9em;color:#0366d6;}"

        ".comments-heading{font-weight:bold;font-size:15px;margin:18px 0 8px;padding-top:12px;border-top:1px solid #eee;}"
        ".comment{background:#f6f8fa;border:1px solid #eee;border-radius:6px;padding:10px 12px;margin:0 0 10px;}"
        ".comment-meta{font-size:12px;color:#666;font-weight:bold;margin-bottom:6px;}"
        ".comment-body{font-size:14px;}"
        ".comment-body p:first-child{margin-top:0;}"
        ".comment-body p:last-child{margin-bottom:0;}"
        ".comments-error{color:#cb2431;font-size:13px;padding:10px 0;}"

        ".pr-branches{font-size:13px;color:#555;background:#f6f8fa;border:1px solid #eee;"
        "border-radius:6px;padding:6px 10px;margin:6px 0 0;word-wrap:break-word;overflow-wrap:break-word;}"

        ".issue-labels{display:inline;}"
        ".issue-label{display:inline-block;padding:2px 8px;margin:0 0 0 6px;"
        "vertical-align:middle;border-radius:10px;font-size:11px;font-weight:bold;line-height:1.6;"
        "white-space:nowrap;}";

    NSString *darkCss =
        @"body{background:#121212;color:#e6e6e6;}"
        "h1{border-bottom-color:#333;}"
        "h2{border-bottom-color:#2a2a2a;}"
        "a{color:#58a6ff;}"
        "code{background:#2a2a2a;color:#e6e6e6;}"
        "pre{background:#1c1c1c;}"
        "blockquote{border-left-color:#444;color:#a0a0a0;}"
        "hr{border-top-color:#333;}"
        "th,td{border-color:#333;}"
        "th{background:#1c1c1c;}"
        ".table-stack-row{border-color:#333;}"
        ".table-stack-cell:not(:last-child){border-bottom-color:#2a2a2a;}"
        ".table-stack-label{color:#888;}"
        ".show-more{background:#1c1c1c;border-color:#333;}"
        ".readme-clip::after{background:linear-gradient(rgba(18,18,18,0),rgba(18,18,18,0.96));}"
        ".readme-loading{color:#999;}"
        ".issue-meta{color:#999;}"
        ".commit-ref code{background:#2a2a2a;color:#58a6ff;}"
        ".comments-heading{border-top-color:#2a2a2a;}"
        ".comment{background:#1c1c1c;border-color:#2a2a2a;}"
        ".comment-meta{color:#999;}"
        ".pr-branches{color:#a0a0a0;background:#1c1c1c;border-color:#2a2a2a;}";

    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;

    NSString *initialThemeJS = [self themeToggleScriptForDarkModeEnabled:isDark];

    NSString *imageFallbackJS =
        @"document.addEventListener('DOMContentLoaded', function(){"
         "function bridge(){try{if(window.location){window.location.href='app://readme-img-loaded';}}catch(e){}}"
         "function fallback(img){"
         "if(img.getAttribute('data-gh-done'))return;img.setAttribute('data-gh-done','1');"
         "if(img.parentNode){img.parentNode.removeChild(img);}"
         "bridge();"
         "}"
         "var imgs=document.getElementsByTagName('img');"
         "for(var i=0;i<imgs.length;i++){"
         "(function(img){"
         "if((' '+(img.className||'')+' ').indexOf(' avatar ')>=0)return;"
         "if(img.complete&&img.naturalWidth>0){img.setAttribute('data-gh-done','1');bridge();return;}"
         "var timer=setTimeout(function(){fallback(img);},25000);"
         "img.addEventListener('load',function(){clearTimeout(timer);"
         "if(img.getAttribute('data-gh-done'))return;img.setAttribute('data-gh-done','1');bridge();});"

         "img.addEventListener('error',function(){"
         "if(img.getAttribute('data-gh-retried')){clearTimeout(timer);fallback(img);return;}"
         "img.setAttribute('data-gh-retried','1');"
         "setTimeout(function(){"
         "if(img.getAttribute('data-gh-done'))return;"
         "img.src=img.src+(img.src.indexOf('?')>=0?'&':'?')+'gh_retry=1';"
         "},1500);"
         "});"
         "})(imgs[i]);"
         "}"
         "});";

    NSString *js = [initialThemeJS stringByAppendingString:imageFallbackJS];

    return [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head>"
        "<meta name=\"viewport\" content=\"width=%@, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>"
        "<style id=\"gh-base-style\">%@</style>"
        "<style id=\"gh-dark-style\">%@</style>"
        "<script>%@</script>"
        "</head><body><div id=\"readme-root\">%@</div></body></html>",
        viewportWidth, css, darkCss, js, bodyHTML ?: @""];
}

+ (NSString *)themeToggleScriptForDarkModeEnabled:(BOOL)darkModeEnabled {
    return [NSString stringWithFormat:
        @"(function(){var s=document.getElementById('gh-dark-style');"
        "if(s){s.disabled=%@;}})();",
        darkModeEnabled ? @"false" : @"true"];
}

+ (NSString *)plainTextHTMLDocument:(NSString *)text {
    NSString *escaped = text ?: @"";
    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];

    NSString *css =
        @"body{font-family:-apple-system,Helvetica;font-size:14px;line-height:1.5;color:#000;margin:0;"
        "padding:12px 16px 16px 16px;word-wrap:break-word;overflow-wrap:break-word;}"
        "pre{white-space:pre-wrap;word-wrap:break-word;overflow-wrap:break-word;margin:0;"
        "font-family:-apple-system,Helvetica;font-size:14px;}"
        ".notice{background:#fff8db;border:1px solid #f0e2a4;color:#6b5900;padding:8px 10px;"
        "border-radius:4px;font-size:12px;margin-bottom:12px;}";

    BOOL isDark = [GHThemeManager sharedManager].darkModeEnabled;
    NSString *darkCss = @"body{background:#121212;color:#e6e6e6;}";
    NSString *initialThemeJS = [self themeToggleScriptForDarkModeEnabled:isDark];

    NSString *notice = @"<div class=\"notice\">README слишком большой для форматированного отображения "
                         "на этом устройстве — показан как обычный текст.</div>";

    return [NSString stringWithFormat:
        @"<!DOCTYPE html><html><head>"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\"/>"
        "<style id=\"gh-base-style\">%@</style>"
        "<style id=\"gh-dark-style\">%@</style>"
        "<script>%@</script>"
        "</head><body>%@<pre>%@</pre></body></html>",
        css, darkCss, initialThemeJS, notice, escaped];
}

+ (NSString *)autoCloseUnclosedTagsInHTML:(NSString *)html {
    if (html.length == 0) return html;

    static NSSet *voidElements = nil;
    static NSRegularExpression *tagRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        voidElements = [NSSet setWithObjects:@"img", @"br", @"hr", @"input", @"meta",
                        @"link", @"source", @"col", @"area", @"base", @"embed", @"track", @"wbr", nil];
        tagRegex = [NSRegularExpression regularExpressionWithPattern:@"<(/?)([a-zA-Z][a-zA-Z0-9]*)([^<>]*)>"
                                                               options:0
                                                                 error:nil];
    });

    NSMutableArray *openStack = [NSMutableArray array];

    [tagRegex enumerateMatchesInString:html
                                options:0
                                  range:NSMakeRange(0, html.length)
                             usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        BOOL isClosing = [match rangeAtIndex:1].length > 0;
        NSString *tagName = [[html substringWithRange:[match rangeAtIndex:2]] lowercaseString];
        NSString *attrs = [html substringWithRange:[match rangeAtIndex:3]];
        BOOL isSelfClosing = [attrs hasSuffix:@"/"] || [voidElements containsObject:tagName];

        if (isClosing) {

            for (NSInteger i = openStack.count - 1; i >= 0; i--) {
                if ([openStack[i] isEqualToString:tagName]) {
                    [openStack removeObjectsInRange:NSMakeRange(i, openStack.count - i)];
                    break;
                }
            }
        } else if (!isSelfClosing) {
            [openStack addObject:tagName];
        }
    }];

    if (openStack.count == 0) return html;

    NSMutableString *result = [html mutableCopy];
    for (NSInteger i = openStack.count - 1; i >= 0; i--) {
        [result appendFormat:@"</%@>", openStack[i]];
    }
    return result;
}

@end
