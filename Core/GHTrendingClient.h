#import <Foundation/Foundation.h>

@interface GHTrendingRepo : NSObject
@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;
@property (nonatomic, copy) NSString *repoDescription;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *totalStarsText;
@property (nonatomic, copy) NSString *starsThisWeekText;
@end

@interface GHTrendingClient : NSObject

+ (instancetype)sharedClient;

- (void)trendingRepositoriesSince:(NSString *)since
                       completion:(void (^)(NSArray *repos, NSError *error))completion;

@end
