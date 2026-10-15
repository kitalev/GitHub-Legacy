#import <Foundation/Foundation.h>

extern NSString * const kGHRecentReposDidChangeNotification;

@interface GHRecentRepos : NSObject

+ (NSArray *)recentRepos;
+ (void)recordRepo:(NSDictionary *)repo;
+ (void)removeRepoAtIndex:(NSUInteger)index;
+ (void)clear;

@end
