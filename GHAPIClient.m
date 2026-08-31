#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHLocalization.h"

static NSString * const kGHBaseURL = @"https://api.github.com";

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
    NSString *urlString = [NSString stringWithFormat:@"%@%@", kGHBaseURL, path];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];

    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:15.0];

    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {

            NSString *githubMessage = nil;
            id errorJSON = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if ([errorJSON isKindOfClass:[NSDictionary class]]) {
                id msg = errorJSON[@"message"];
                if ([msg isKindOfClass:[NSString class]]) githubMessage = msg;
            }
            NSString *acceptedPermissions = [httpResponse.allHeaderFields[@"X-Accepted-GitHub-Permissions"] description];

            NSString *description = githubMessage.length > 0
                ? [NSString stringWithFormat:@"HTTP %ld: %@", (long)httpResponse.statusCode, githubMessage]
                : [NSString stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];

            NSLog(@"GHAPIClient: %@ -> HTTP %ld%@%@",
                  path, (long)httpResponse.statusCode,
                  githubMessage.length > 0 ? [@" — " stringByAppendingString:githubMessage] : @"",
                  acceptedPermissions.length > 0 ? [NSString stringWithFormat:@" (нужны права: %@)", acceptedPermissions] : @"");

            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
            if (acceptedPermissions.length > 0) userInfo[@"GHAcceptedPermissions"] = acceptedPermissions;

            NSError *httpError = [NSError errorWithDomain:@"GHAPIClient"
                                                       code:httpResponse.statusCode
                                                   userInfo:userInfo];
            if (completion) completion(nil, httpError);
            return;
        }

        NSError *jsonError = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (completion) completion(jsonObject, jsonError);
    }];
}

- (void)searchRepositoriesWithQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *escapedQuery = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString *path = [NSString stringWithFormat:@"/search/repositories?q=%@", escapedQuery];
    [self getJSONFromPath:path completion:completion];
}

- (void)searchIssuesAndPullRequestsWithQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion {
    NSString *escapedQuery = [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *path = [NSString stringWithFormat:@"/search/issues?q=%@", escapedQuery];
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

- (void)fileContentsForOwner:(NSString *)owner repo:(NSString *)repo path:(NSString *)path completion:(GHJSONCompletionBlock)completion {

    NSMutableArray *encodedComponents = [NSMutableArray array];
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {

        NSString *encoded = [component stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: component;
        [encodedComponents addObject:encoded];
    }
    NSString *encodedPath = [encodedComponents componentsJoinedByString:@"/"];
    NSString *apiPath = [NSString stringWithFormat:@"/repos/%@/%@/contents/%@", owner, repo, encodedPath];
    [self getJSONFromPath:apiPath completion:completion];
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

- (void)pullRequestsForOwner:(NSString *)owner repo:(NSString *)repo state:(NSString *)state page:(NSInteger)page completion:(GHJSONCompletionBlock)completion {
    NSString *safeState = state.length > 0 ? state : @"open";
    NSInteger safePage = page > 0 ? page : 1;
    NSString *path = [NSString stringWithFormat:@"/repos/%@/%@/pulls?state=%@&per_page=100&page=%ld&sort=created&direction=desc", owner, repo, safeState, (long)safePage];
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

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(0, nil, connectionError);
            return;
        }
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

        NSString *message = nil;
        if (data.length > 0) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]]) {
                id msg = json[@"message"];
                if ([msg isKindOfClass:[NSString class]]) message = msg;
            }
        }

        if (completion) completion(httpResponse.statusCode, message, nil);
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
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:@{@"query": query ?: @""} options:0 error:&encodeError];
    if (encodeError) {
        if (completion) completion(nil, encodeError);
        return;
    }
    request.HTTPBody = bodyData;

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }

        NSError *jsonError = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

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
            if (completion) completion(nil, gqlError);
            return;
        }

        if (completion) completion(jsonObject, jsonError);
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

    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:@{@"content": content ?: @""} options:0 error:nil];
    request.HTTPBody = bodyData;

    [NSURLConnection sendAsynchronousRequest:request
                                        queue:[NSOperationQueue mainQueue]
                            completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 400) {

            NSString *githubMessage = nil;
            id errorJSON = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
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
            if (completion) completion(nil, httpError);
            return;
        }

        id jsonObject = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (completion) completion(jsonObject, nil);
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
