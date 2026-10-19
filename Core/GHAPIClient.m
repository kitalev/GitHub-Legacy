#import "GHAPIClient.h"
#import "GHJSONSerialization.h"
#import "GHAuthManager.h"
#import "GHLocalization.h"

static NSString * const kGHBaseURL = @"https://api.github.com";

static NSOperationQueue *GHAPIResponseQueue(void) {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 2;
    });
    return queue;
}

static GHJSONCompletionBlock GHJSONCompletionOnMain(GHJSONCompletionBlock completion) {
    if (completion == nil) return nil;
    return ^(id jsonObject, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(jsonObject, error);
        });
    };
}

static GHTextCompletionBlock GHTextCompletionOnMain(GHTextCompletionBlock completion) {
    if (completion == nil) return nil;
    return ^(NSString *text, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(text, error);
        });
    };
}

static GHStatusCompletionBlock GHStatusCompletionOnMain(GHStatusCompletionBlock completion) {
    if (completion == nil) return nil;
    return ^(NSInteger statusCode, NSString *message, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(statusCode, message, error);
        });
    };
}

@implementation GHAPIClient

+ (instancetype)sharedClient {
    static GHAPIClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GHAPIClient alloc] init];
    });
    return instance;
}

- (void)getJSONFromPath:(NSString *)path completion:(GHJSONCompletionBlock)completion {
    [self getJSONFromPath:path accept:@"application/vnd.github.v3+json" completion:completion];
}

- (void)getJSONFromPath:(NSString *)path accept:(NSString *)accept completion:(GHJSONCompletionBlock)completion {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kGHBaseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:accept forHTTPHeaderField:@"Accept"];

    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:15.0];

    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    GHJSONCompletionBlock mainCompletion = GHJSONCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(nil, connectionError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {

            NSString *githubMessage = nil;
            id errorJSON = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([errorJSON isKindOfClass:[NSDictionary class]]) {
                id msg = errorJSON[@"message"];
                if ([msg isKindOfClass:[NSString class]]) githubMessage = msg;
            }
            NSString *acceptedPermissions = [httpResponse.allHeaderFields[@"X-Accepted-GitHub-Permissions"] description];

            NSString *description = githubMessage.length > 0
                ? [NSString stringWithFormat:@"HTTP %ld: %@", (long)httpResponse.statusCode, githubMessage]
                : [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];

            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
            if (acceptedPermissions.length > 0) userInfo[@"GHAcceptedPermissions"] = acceptedPermissions;

            NSError *httpError = [NSError errorWithDomain:@"GHAPIClient"
                                                       code:httpResponse.statusCode
                                                   userInfo:userInfo];
            if (mainCompletion) mainCompletion(nil, httpError);
            return;
        }

        NSError *jsonError = nil;
        id jsonObject = [GHJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (mainCompletion) mainCompletion(jsonObject, jsonError);
    }];
}

- (void)searchRepositoriesWithQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *escapedQuery = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString *path = [NSString stringWithFormat:@"/search/repositories?q=%@", escapedQuery];
    [self getJSONFromPath:path completion:completion];
}

- (void)searchIssuesAndPullRequestsWithQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *escapedQuery = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [NSString stringWithFormat:@"/search/issues?q=%@&per_page=50", escapedQuery];
    [self getJSONFromPath:path completion:completion];
}

- (void)labelsForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/labels?per_page=100", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (void)searchUsersWithQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *escapedQuery = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [NSString stringWithFormat:@"/search/users?q=%@", escapedQuery];
    [self getJSONFromPath:path completion:completion];
}

- (void)releasesForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (void)releaseForOwner:(NSString *)owner repo:(NSString *)repo releaseID:(long long)releaseID completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/%lld", owner, repo, releaseID];
    [self getJSONFromPath:path completion:completion];
}

- (void)latestReleaseForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/latest", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (void)releaseForOwner:(NSString *)owner repo:(NSString *)repo tag:(NSString *)tag completion:(GHJSONCompletionBlock)completion {
    NSString *escapedTag = [tag stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/tags/%@", owner, repo, escapedTag];
    [self getJSONFromPath:path completion:completion];
}

- (void)currentUserWithCompletion:(GHJSONCompletionBlock)completion {
    [self getJSONFromPath:@"/user" completion:completion];
}

- (void)repoDetailForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (void)starredRepositoriesWithCompletion:(GHJSONCompletionBlock)completion {
    [self getJSONFromPath:@"/user/starred?per_page=50" completion:completion];
}

- (void)readmeForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/readme", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (NSString *)contentsAPIPathForOwner:(NSString *)owner repo:(NSString *)repo path:(NSString *)path {
    if (path.length == 0) return [NSString stringWithFormat:@"/repos/%@/%@/contents", owner, repo];

    NSMutableArray *encodedComponents = [NSMutableArray array];
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {

        NSString *encoded = [component stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: component;
        [encodedComponents addObject:encoded];
    }
    NSString *encodedPath = [encodedComponents componentsJoinedByString:@"/"];
    return [NSString stringWithFormat:@"/repos/%@/%@/contents/%@", owner, repo, encodedPath];
}

- (void)fileContentsForOwner:(NSString *)owner repo:(NSString *)repo path:(NSString *)path completion:(GHJSONCompletionBlock)completion {
    [self getJSONFromPath:[self contentsAPIPathForOwner:owner repo:repo path:path] completion:completion];
}

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path accept:(NSString *)accept {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", kGHBaseURL, path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    [request setValue:accept forHTTPHeaderField:@"Accept"];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:15.0];

    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }
    return request;
}

- (NSError *)errorForHTTPResponse:(NSHTTPURLResponse *)httpResponse data:(NSData *)data {
    NSString *githubMessage = nil;
    NSMutableArray *details = [NSMutableArray array];
    id errorJSON = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if ([errorJSON isKindOfClass:[NSDictionary class]]) {
        id msg = errorJSON[@"message"];
        if ([msg isKindOfClass:[NSString class]]) githubMessage = msg;

        id errors = errorJSON[@"errors"];
        for (id entry in [errors isKindOfClass:[NSArray class]] ? errors : @[]) {
            if ([entry isKindOfClass:[NSString class]]) {
                [details addObject:entry];
                continue;
            }
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            id entryMessage = entry[@"message"];
            id field = entry[@"field"];
            id code = entry[@"code"];
            if ([entryMessage isKindOfClass:[NSString class]] && [entryMessage length] > 0) {
                [details addObject:entryMessage];
            } else if ([field isKindOfClass:[NSString class]] && [code isKindOfClass:[NSString class]]) {
                [details addObject:[NSString stringWithFormat:@"%@: %@", field, code]];
            }
        }
    }
    if (details.count > 0) {
        NSString *joined = [details componentsJoinedByString:@"; "];
        githubMessage = githubMessage.length > 0 ? [NSString stringWithFormat:@"%@ (%@)", githubMessage, joined] : joined;
    }

    NSString *description = githubMessage.length > 0
        ? [NSString stringWithFormat:@"HTTP %ld: %@", (long)httpResponse.statusCode, githubMessage]
        : [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
    return [NSError errorWithDomain:@"GHAPIClient"
                               code:httpResponse.statusCode
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)rawFileForOwner:(NSString *)owner repo:(NSString *)repo path:(NSString *)path completion:(GHTextCompletionBlock)completion {
    NSString *apiPath = [self contentsAPIPathForOwner:owner repo:repo path:path];
    NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:apiPath accept:@"application/vnd.github.raw"];

    GHTextCompletionBlock mainCompletion = GHTextCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(nil, connectionError);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {
            if (mainCompletion) mainCompletion(nil, [self errorForHTTPResponse:httpResponse data:data]);
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
        if (text == nil) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (mainCompletion) mainCompletion(text ?: @"", nil);
    }];
}

- (void)createIssueForOwner:(NSString *)owner repo:(NSString *)repo parameters:(NSDictionary *)parameters completion:(GHJSONCompletionBlock)completion {
    if ([GHAuthManager sharedManager].accessToken.length == 0) {
        NSError *authError = [NSError errorWithDomain:@"GHAPIClient"
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: GHL(@"Чтобы создать задачу, войдите в аккаунт в настройках.")}];
        if (completion) completion(nil, authError);
        return;
    }

    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/issues", owner, repo];
    NSMutableURLRequest *request = [self requestWithMethod:@"POST" path:path accept:@"application/vnd.github.v3+json"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setTimeoutInterval:30.0];

    NSError *encodeError = nil;
    NSData *bodyData = [GHJSONSerialization dataWithJSONObject:parameters ?: @{} options:0 error:&encodeError];
    if (encodeError) {
        if (completion) completion(nil, encodeError);
        return;
    }
    request.HTTPBody = bodyData;

    GHJSONCompletionBlock mainCompletion = GHJSONCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(nil, connectionError);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {
            if (mainCompletion) mainCompletion(nil, [self errorForHTTPResponse:httpResponse data:data]);
            return;
        }
        NSError *jsonError = nil;
        id jsonObject = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
        if (mainCompletion) mainCompletion(jsonObject, jsonError);
    }];
}

- (void)commitsForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    [self commitsForOwner:owner repo:repo page:1 completion:completion];
}

- (void)forksForOwner:(NSString *)owner repo:(NSString *)repo sort:(NSString *)sort page:(NSInteger)page completion:(GHJSONCompletionBlock)completion {
    NSInteger safePage = page > 0 ? page : 1;
    NSString *safeSort = sort.length > 0 ? sort : @"newest";
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/forks?sort=%@&per_page=30&page=%ld", owner, repo, safeSort, (long)safePage];
    [self getJSONFromPath:path completion:completion];
}

- (void)commitsForOwner:(NSString *)owner repo:(NSString *)repo page:(NSInteger)page completion:(GHJSONCompletionBlock)completion {
    NSInteger safePage = page > 0 ? page : 1;
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/commits?per_page=30&page=%ld", owner, repo, (long)safePage];
    [self getJSONFromPath:path completion:completion];
}

- (void)commitDetailForOwner:(NSString *)owner repo:(NSString *)repo sha:(NSString *)sha completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/commits/%@", owner, repo, sha];
    [self getJSONFromPath:path completion:completion];
}

- (void)issuesForOwner:(NSString *)owner repo:(NSString *)repo state:(NSString *)state page:(NSInteger)page completion:(GHJSONCompletionBlock)completion {
    NSString *safeState = state.length > 0 ? state : @"open";
    NSInteger safePage = page > 0 ? page : 1;
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/issues?state=%@&per_page=100&page=%ld&sort=created&direction=desc", owner, repo, safeState, (long)safePage];
    [self getJSONFromPath:path completion:completion];
}

- (void)issueForOwner:(NSString *)owner repo:(NSString *)repo number:(NSInteger)number completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/issues/%ld", owner, repo, (long)number];
    [self getJSONFromPath:path completion:completion];
}

- (void)commentsForOwner:(NSString *)owner repo:(NSString *)repo number:(NSInteger)number completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/issues/%ld/comments?per_page=100", owner, repo, (long)number];
    [self getJSONFromPath:path completion:completion];
}

- (void)timelineForOwner:(NSString *)owner repo:(NSString *)repo number:(NSInteger)number completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/issues/%ld/timeline?per_page=100", owner, repo, (long)number];
    [self getJSONFromPath:path completion:completion];
}

- (void)checkRunsForOwner:(NSString *)owner repo:(NSString *)repo ref:(NSString *)ref completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/commits/%@/check-runs?per_page=100", owner, repo, ref];
    [self getJSONFromPath:path completion:completion];
}

- (void)pullRequestsForOwner:(NSString *)owner repo:(NSString *)repo state:(NSString *)state page:(NSInteger)page completion:(GHJSONCompletionBlock)completion {
    NSString *safeState = state.length > 0 ? state : @"open";
    NSInteger safePage = page > 0 ? page : 1;
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/pulls?state=%@&per_page=100&page=%ld&sort=created&direction=desc", owner, repo, safeState, (long)safePage];
    [self getJSONFromPath:path completion:completion];
}

- (void)latestPullRequestForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/pulls?state=all&per_page=1", owner, repo];
    [self getJSONFromPath:path completion:completion];
}

- (void)pullRequestForOwner:(NSString *)owner repo:(NSString *)repo number:(NSInteger)number completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/pulls/%ld", owner, repo, (long)number];
    [self getJSONFromPath:path completion:completion];
}

- (void)repositoriesForCurrentUserWithCompletion:(GHJSONCompletionBlock)completion {
    [self getJSONFromPath:@"/user/repos?sort=updated&per_page=50&affiliation=owner,collaborator" completion:completion];
}

- (void)followersForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@/followers?per_page=50", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)followingForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@/following?per_page=50", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)organizationsForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@/orgs?per_page=100", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)checkFollowingUser:(NSString *)login completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/following/%@", login];
    [self performStatusRequestWithMethod:@"GET" path:path completion:completion];
}

- (void)followUser:(NSString *)login completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/following/%@", login];
    [self performStatusRequestWithMethod:@"PUT" path:path completion:completion];
}

- (void)unfollowUser:(NSString *)login completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/following/%@", login];
    [self performStatusRequestWithMethod:@"DELETE" path:path completion:completion];
}

- (void)publicProfileForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)repositoriesForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@/repos?sort=updated&per_page=50", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)starredRepositoriesForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/users/%@/starred?per_page=50", login];
    [self getJSONFromPath:path completion:completion];
}

- (void)performStatusRequestWithMethod:(NSString *)method path:(NSString *)path completion:(GHStatusCompletionBlock)completion {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kGHBaseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"0" forHTTPHeaderField:@"Content-Length"];
    [request setTimeoutInterval:15.0];

    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    GHStatusCompletionBlock mainCompletion = GHStatusCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(0, nil, connectionError);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        NSString *message = nil;
        if (data.length > 0) {
            id json = [GHJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                id msg = json[@"message"];
                if ([msg isKindOfClass:[NSString class]]) message = msg;
            }
        }

        if (mainCompletion) mainCompletion(httpResponse.statusCode, message, nil);
    }];
}

- (void)checkStarredForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/starred/%@/%@", owner, repo];
    [self performStatusRequestWithMethod:@"GET" path:path completion:completion];
}

- (void)starRepoForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/starred/%@/%@", owner, repo];
    [self performStatusRequestWithMethod:@"PUT" path:path completion:completion];
}

- (void)unstarRepoForOwner:(NSString *)owner repo:(NSString *)repo completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/user/starred/%@/%@", owner, repo];
    [self performStatusRequestWithMethod:@"DELETE" path:path completion:completion];
}

- (void)graphQLQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length == 0) {
        NSError *authError = [NSError errorWithDomain:@"GHAPIClient"
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: GHL(@"GraphQL API требует авторизации.")}];
        if (completion) completion(nil, authError);
        return;
    }

    NSURL *url = [NSURL URLWithString:@"https://api.github.com/graphql"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:15.0];

    NSError *encodeError = nil;
    NSData *bodyData = [GHJSONSerialization dataWithJSONObject:@{@"query": query ?: @""} options:0 error:&encodeError];
    if (encodeError) {
        if (completion) completion(nil, encodeError);
        return;
    }
    request.HTTPBody = bodyData;

    GHJSONCompletionBlock mainCompletion = GHJSONCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(nil, connectionError);
            return;
        }

        NSError *jsonError = nil;
        id jsonObject = [GHJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (!jsonError && [jsonObject isKindOfClass:[NSDictionary class]] && jsonObject[@"errors"]) {
            NSArray *errors = [jsonObject[@"errors"] isKindOfClass:[NSArray class]] ? jsonObject[@"errors"] : @[];
            NSString *message = GHL(@"Ошибка GraphQL-запроса.");
            if (errors.count > 0 && [errors[0] isKindOfClass:[NSDictionary class]]) {
                id firstMessage = ((NSDictionary *)errors[0])[@"message"];
                if ([firstMessage isKindOfClass:[NSString class]]) message = firstMessage;
            }
            NSError *gqlError = [NSError errorWithDomain:@"GHAPIClient"
                                                       code:422
                                                   userInfo:@{NSLocalizedDescriptionKey: message}];
            if (mainCompletion) mainCompletion(nil, gqlError);
            return;
        }

        if (mainCompletion) mainCompletion(jsonObject, jsonError);
    }];
}

- (void)reactionsForOwner:(NSString *)owner
                      repo:(NSString *)repo
                 releaseID:(long long)releaseID
                completion:(GHJSONCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/%lld/reactions?per_page=100", owner, repo, releaseID];
    [self getJSONFromPath:path completion:completion];
}

- (void)addReactionForOwner:(NSString *)owner
                         repo:(NSString *)repo
                    releaseID:(long long)releaseID
                      content:(NSString *)content
                   completion:(GHJSONCompletionBlock)completion {
    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length == 0) {
        NSError *authError = [NSError errorWithDomain:@"GHAPIClient"
                                                   code:401
                                               userInfo:@{NSLocalizedDescriptionKey: GHL(@"Чтобы оставить реакцию, нужно войти в аккаунт.")}];
        if (completion) completion(nil, authError);
        return;
    }

    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/%lld/reactions", owner, repo, releaseID];
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kGHBaseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    [request setTimeoutInterval:15.0];

    NSData *bodyData = [GHJSONSerialization dataWithJSONObject:@{@"content": content ?: @""} options:0 error:nil];
    request.HTTPBody = bodyData;

    GHJSONCompletionBlock mainCompletion = GHJSONCompletionOnMain(completion);
    [NSURLConnection sendAsynchronousRequest:request
                                        queue:GHAPIResponseQueue()
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (mainCompletion) mainCompletion(nil, connectionError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {

            NSString *githubMessage = nil;
            id errorJSON = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([errorJSON isKindOfClass:[NSDictionary class]]) {
                id msg = errorJSON[@"message"];
                if ([msg isKindOfClass:[NSString class]]) githubMessage = msg;
            }
            NSString *description = githubMessage.length > 0
                ? [NSString stringWithFormat:@"HTTP %ld: %@", (long)httpResponse.statusCode, githubMessage]
                : [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
            NSError *httpError = [NSError errorWithDomain:@"GHAPIClient"
                                                       code:httpResponse.statusCode
                                                   userInfo:@{NSLocalizedDescriptionKey: description}];
            if (mainCompletion) mainCompletion(nil, httpError);
            return;
        }

        id jsonObject = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (mainCompletion) mainCompletion(jsonObject, nil);
    }];
}

- (void)deleteReactionForOwner:(NSString *)owner
                            repo:(NSString *)repo
                       releaseID:(long long)releaseID
                      reactionID:(long long)reactionID
                      completion:(GHStatusCompletionBlock)completion {
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/releases/%lld/reactions/%lld", owner, repo, releaseID, reactionID];
    [self performStatusRequestWithMethod:@"DELETE" path:path completion:completion];
}

@end
