#import "GHRecentRepos.h"

NSString * const kGHRecentReposDidChangeNotification = @"GHRecentReposDidChangeNotification";

static NSString * const kGHRecentReposDefaultsKey = @"GHRecentRepos";
static const NSUInteger kGHRecentReposMaxCount = 5;

static id GHRecentPlistValue(id value) {
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    return nil;
}

@implementation GHRecentRepos

+ (NSArray *)recentRepos {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kGHRecentReposDefaultsKey];
    if (![saved isKindOfClass:[NSArray class]]) return @[];
    return saved.count > kGHRecentReposMaxCount ? [saved subarrayWithRange:NSMakeRange(0, kGHRecentReposMaxCount)] : saved;
}

+ (void)saveRepos:(NSArray *)repos {
    [[NSUserDefaults standardUserDefaults] setObject:repos forKey:kGHRecentReposDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:kGHRecentReposDidChangeNotification object:nil];
}

+ (void)recordRepo:(NSDictionary *)repo {
    if (![repo isKindOfClass:[NSDictionary class]]) return;
    NSString *fullName = GHRecentPlistValue(repo[@"full_name"]);
    if (![fullName isKindOfClass:[NSString class]] || fullName.length == 0) return;

    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"full_name", @"name", @"description", @"language", @"stargazers_count"]) {
        id value = GHRecentPlistValue(repo[key]);
        if (value) entry[key] = value;
    }
    NSDictionary *owner = [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? repo[@"owner"] : nil;
    NSMutableDictionary *ownerEntry = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"login", @"avatar_url"]) {
        id value = GHRecentPlistValue(owner[key]);
        if (value) ownerEntry[key] = value;
    }
    if (ownerEntry.count > 0) entry[@"owner"] = ownerEntry;

    NSMutableArray *repos = [[self recentRepos] mutableCopy];
    NSUInteger existing = [repos indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        return [item isKindOfClass:[NSDictionary class]] && [item[@"full_name"] caseInsensitiveCompare:fullName] == NSOrderedSame;
    }];
    if (existing != NSNotFound) [repos removeObjectAtIndex:existing];
    [repos insertObject:entry atIndex:0];
    while (repos.count > kGHRecentReposMaxCount) [repos removeLastObject];
    [self saveRepos:repos];
}

+ (void)removeRepoAtIndex:(NSUInteger)index {
    NSMutableArray *repos = [[self recentRepos] mutableCopy];
    if (index >= repos.count) return;
    [repos removeObjectAtIndex:index];
    [self saveRepos:repos];
}

+ (void)clear {
    [self saveRepos:@[]];
}

@end
