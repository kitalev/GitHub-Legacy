#import <Foundation/Foundation.h>

@interface GHTimelineRenderer : NSObject

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;
@property (nonatomic, assign) BOOL isPullRequest;

- (id)initWithOwnerLogin:(NSString *)ownerLogin repoName:(NSString *)repoName;

- (NSString *)styleCSS;
- (NSString *)relativeTimeFromISOString:(NSString *)isoString;

- (NSString *)repoLineHTMLWithNumber:(NSNumber *)number;
- (NSString *)titleHTML:(NSString *)title;
- (NSString *)stateRowHTMLWithLabel:(NSString *)label color:(NSString *)color extraHTML:(NSString *)extraHTML;
- (NSString *)labelsHTML:(NSArray *)labels;
- (NSString *)branchHTML:(NSString *)branch;

- (NSString *)postHTMLWithUser:(NSDictionary *)user
                     createdAt:(NSString *)createdAt
                   association:(NSString *)association
                          body:(NSString *)body;

- (NSString *)sectionHeaderHTML:(NSString *)title;
- (NSString *)rowHTMLWithGlyph:(NSString *)glyph
                    glyphColor:(NSString *)glyphColor
               glyphBackground:(NSString *)glyphBackground
                     titleHTML:(NSString *)titleHTML
                  subtitleHTML:(NSString *)subtitleHTML
                  trailingHTML:(NSString *)trailingHTML;

- (NSString *)timelineItemHTML:(NSDictionary *)item;
- (NSString *)errorHTML:(NSString *)text;

- (NSString *)additionsHTML:(NSInteger)additions deletions:(NSInteger)deletions;

@end
