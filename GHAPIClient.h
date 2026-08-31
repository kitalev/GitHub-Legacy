#import <Foundation/Foundation.h>

typedef void (^GHJSONCompletionBlock)(id jsonObject, NSError *error);

typedef void (^GHStatusCompletionBlock)(NSInteger statusCode, NSString *message, NSError *error);

@interface GHAPIClient : NSObject

+ (instancetype)sharedClient;

- (void)searchRepositoriesWithQuery:(NSString *)query
                          completion:(GHJSONCompletionBlock)completion;

- (void)searchIssuesAndPullRequestsWithQuery:(NSString *)query
                                    completion:(GHJSONCompletionBlock)completion;

- (void)searchUsersWithQuery:(NSString *)query
                    completion:(GHJSONCompletionBlock)completion;

- (void)releasesForOwner:(NSString *)owner
                     repo:(NSString *)repo
               completion:(GHJSONCompletionBlock)completion;

- (void)releaseForOwner:(NSString *)owner
                    repo:(NSString *)repo
               releaseID:(long long)releaseID
              completion:(GHJSONCompletionBlock)completion;

- (void)forksForOwner:(NSString *)owner
                   repo:(NSString *)repo
                   sort:(NSString *)sort
                   page:(NSInteger)page
             completion:(GHJSONCompletionBlock)completion;

- (void)currentUserWithCompletion:(GHJSONCompletionBlock)completion;

- (void)repoDetailForOwner:(NSString *)owner
                       repo:(NSString *)repo
                 completion:(GHJSONCompletionBlock)completion;

- (void)starredRepositoriesWithCompletion:(GHJSONCompletionBlock)completion;

- (void)readmeForOwner:(NSString *)owner
                   repo:(NSString *)repo
             completion:(GHJSONCompletionBlock)completion;

- (void)fileContentsForOwner:(NSString *)owner
                          repo:(NSString *)repo
                          path:(NSString *)path
                    completion:(GHJSONCompletionBlock)completion;

- (void)commitsForOwner:(NSString *)owner
                    repo:(NSString *)repo
              completion:(GHJSONCompletionBlock)completion;

- (void)commitsForOwner:(NSString *)owner
                    repo:(NSString *)repo
                    page:(NSInteger)page
              completion:(GHJSONCompletionBlock)completion;

- (void)commitDetailForOwner:(NSString *)owner
                         repo:(NSString *)repo
                          sha:(NSString *)sha
                   completion:(GHJSONCompletionBlock)completion;

- (void)issuesForOwner:(NSString *)owner
                    repo:(NSString *)repo
                   state:(NSString *)state
                    page:(NSInteger)page
              completion:(GHJSONCompletionBlock)completion;

- (void)issueForOwner:(NSString *)owner
                    repo:(NSString *)repo
                  number:(NSInteger)number
              completion:(GHJSONCompletionBlock)completion;

- (void)commentsForOwner:(NSString *)owner
                      repo:(NSString *)repo
                    number:(NSInteger)number
                completion:(GHJSONCompletionBlock)completion;

- (void)repositoriesForCurrentUserWithCompletion:(GHJSONCompletionBlock)completion;

- (void)followersForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion;

- (void)followingForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion;

- (void)checkFollowingUser:(NSString *)login completion:(GHStatusCompletionBlock)completion;

- (void)followUser:(NSString *)login completion:(GHStatusCompletionBlock)completion;

- (void)unfollowUser:(NSString *)login completion:(GHStatusCompletionBlock)completion;

- (void)publicProfileForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion;

- (void)repositoriesForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion;

- (void)starredRepositoriesForUser:(NSString *)login completion:(GHJSONCompletionBlock)completion;

- (void)pullRequestsForOwner:(NSString *)owner
                          repo:(NSString *)repo
                         state:(NSString *)state
                          page:(NSInteger)page
                    completion:(GHJSONCompletionBlock)completion;

- (void)pullRequestForOwner:(NSString *)owner
                        repo:(NSString *)repo
                      number:(NSInteger)number
                  completion:(GHJSONCompletionBlock)completion;

- (void)checkStarredForOwner:(NSString *)owner
                          repo:(NSString *)repo
                    completion:(GHStatusCompletionBlock)completion;

- (void)starRepoForOwner:(NSString *)owner
                     repo:(NSString *)repo
               completion:(GHStatusCompletionBlock)completion;

- (void)unstarRepoForOwner:(NSString *)owner
                       repo:(NSString *)repo
                 completion:(GHStatusCompletionBlock)completion;

- (void)graphQLQuery:(NSString *)query completion:(GHJSONCompletionBlock)completion;

- (void)reactionsForOwner:(NSString *)owner
                      repo:(NSString *)repo
                 releaseID:(long long)releaseID
                completion:(GHJSONCompletionBlock)completion;

- (void)addReactionForOwner:(NSString *)owner
                         repo:(NSString *)repo
                    releaseID:(long long)releaseID
                      content:(NSString *)content
                   completion:(GHJSONCompletionBlock)completion;

- (void)deleteReactionForOwner:(NSString *)owner
                            repo:(NSString *)repo
                       releaseID:(long long)releaseID
                      reactionID:(long long)reactionID
                      completion:(GHStatusCompletionBlock)completion;

@end
