#import "GHTrendingClient.h"

@implementation GHTrendingRepo
@end

@implementation GHTrendingClient

+ (instancetype)sharedClient {
    static GHTrendingClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHTrendingClient alloc] init];
    });
    return instance;
}

- (void)trendingRepositoriesSince:(NSString *)since completion:(void (^)(NSArray *repos, NSError *error))completion {
    NSString *safeSince = since.length > 0 ? since : @"weekly";
    NSString *urlString = [NSString stringWithFormat:@"https://github.com/trending?since=%@", safeSince];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 9_3_6 like Mac OS X) AppleWebKit/601.1"
        forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:15.0];

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }

        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (html.length == 0) {
            if (completion) completion(nil, [NSError errorWithDomain:@"GHTrendingClient" code:1 userInfo:nil]);
            return;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSArray *repos = [self parseTrendingHTML:html];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (repos.count > 0) {
                    if (completion) completion(repos, nil);
                } else {

                    if (completion) completion(nil, [NSError errorWithDomain:@"GHTrendingClient" code:2 userInfo:nil]);
                }
            });
        });
    }];
}

- (NSArray *)parseTrendingHTML:(NSString *)html {
    NSRegularExpression *articleRegex = [NSRegularExpression regularExpressionWithPattern:
        @"<article class=\"Box-row\">([\\s\\S]*?)</article>"
                                                                                    options:0
                                                                                      error:nil];
    NSArray *articleMatches = [articleRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];

    NSRegularExpression *ownerRepoRegex = [NSRegularExpression regularExpressionWithPattern:
        @"href=\"/([^/\"]+)/([^/\"]+)\"\\s+data-view-component=\"true\"\\s+class=\"Link\">"
                                                                                      options:0
                                                                                        error:nil];
    NSRegularExpression *descriptionRegex = [NSRegularExpression regularExpressionWithPattern:
        @"<p class=\"col-9 color-fg-muted my-1[^\"]*\">\\s*([\\s\\S]*?)\\s*</p>"
                                                                                        options:0
                                                                                          error:nil];
    NSRegularExpression *languageRegex = [NSRegularExpression regularExpressionWithPattern:
        @"itemprop=\"programmingLanguage\">([^<]*)<"
                                                                                     options:0
                                                                                       error:nil];
    NSRegularExpression *totalStarsRegex = [NSRegularExpression regularExpressionWithPattern:
        @"/stargazers\"\\s+data-view-component=\"true\"\\s+class=\"[^\"]*\">[\\s\\S]*?</svg>\\s*([\\d,]+)</a>"
                                                                                       options:0
                                                                                         error:nil];
    NSRegularExpression *weekStarsRegex = [NSRegularExpression regularExpressionWithPattern:
        @"float-sm-right\">\\s*<svg[\\s\\S]*?</svg>\\s*([\\d,]+) stars this (?:week|month|today)"
                                                                                      options:0
                                                                                        error:nil];

    NSMutableArray *results = [NSMutableArray array];

    for (NSTextCheckingResult *articleMatch in articleMatches) {
        NSString *article = [html substringWithRange:[articleMatch rangeAtIndex:1]];

        NSTextCheckingResult *ownerRepoMatch = [ownerRepoRegex firstMatchInString:article options:0 range:NSMakeRange(0, article.length)];
        if (ownerRepoMatch == nil) continue;

        GHTrendingRepo *repo = [[GHTrendingRepo alloc] init];
        repo.ownerLogin = [self htmlUnescape:[article substringWithRange:[ownerRepoMatch rangeAtIndex:1]]];
        repo.repoName = [self htmlUnescape:[article substringWithRange:[ownerRepoMatch rangeAtIndex:2]]];

        NSTextCheckingResult *descMatch = [descriptionRegex firstMatchInString:article options:0 range:NSMakeRange(0, article.length)];
        if (descMatch) {
            repo.repoDescription = [self htmlUnescape:[article substringWithRange:[descMatch rangeAtIndex:1]]];
        }

        NSTextCheckingResult *langMatch = [languageRegex firstMatchInString:article options:0 range:NSMakeRange(0, article.length)];
        if (langMatch) {
            repo.language = [self htmlUnescape:[article substringWithRange:[langMatch rangeAtIndex:1]]];
        }

        NSTextCheckingResult *totalMatch = [totalStarsRegex firstMatchInString:article options:0 range:NSMakeRange(0, article.length)];
        if (totalMatch) {
            repo.totalStarsText = [article substringWithRange:[totalMatch rangeAtIndex:1]];
        }

        NSTextCheckingResult *weekMatch = [weekStarsRegex firstMatchInString:article options:0 range:NSMakeRange(0, article.length)];
        if (weekMatch) {
            repo.starsThisWeekText = [article substringWithRange:[weekMatch rangeAtIndex:1]];
        }

        [results addObject:repo];
    }

    return results;
}

- (NSString *)htmlUnescape:(NSString *)text {
    if (text.length == 0) return text;
    NSString *result = text;
    result = [result stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    result = [result stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    result = [result stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    result = [result stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    result = [result stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
