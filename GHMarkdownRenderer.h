#import <Foundation/Foundation.h>

@interface GHMarkdownRenderer : NSObject

+ (NSString *)htmlDocumentFromMarkdown:(NSString *)markdown;

+ (NSString *)htmlDocumentFromMarkdown:(NSString *)markdown pixelWidth:(CGFloat)pixelWidth;

+ (NSString *)escapeHTML:(NSString *)text;

+ (NSString *)escapeHTMLAttribute:(NSString *)text;

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                            progress:(void (^)(NSString *stepName))progressBlock;

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown;

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                          repoOwner:(NSString *)repoOwner
                           repoName:(NSString *)repoName;
+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                          repoOwner:(NSString *)repoOwner
                           repoName:(NSString *)repoName
                           progress:(void (^)(NSString *stepName))progressBlock;

+ (NSString *)bodyHTMLFromMarkdown:(NSString *)markdown
                          repoOwner:(NSString *)repoOwner
                           repoName:(NSString *)repoName
                  repoDefaultBranch:(NSString *)repoDefaultBranch
                           progress:(void (^)(NSString *stepName))progressBlock;

+ (NSString *)htmlDocumentWrappingBody:(NSString *)bodyHTML;

+ (NSString *)inlineUserAttachmentImagesInHTML:(NSString *)html
                                     ownerLogin:(NSString *)ownerLogin
                                       repoName:(NSString *)repoName;

+ (NSString *)htmlDocumentWrappingBody:(NSString *)bodyHTML pixelWidth:(CGFloat)pixelWidth;

+ (NSString *)autoCloseUnclosedTagsInHTML:(NSString *)html;

+ (NSString *)plainTextHTMLDocument:(NSString *)text;

+ (NSString *)themeToggleScriptForDarkModeEnabled:(BOOL)darkModeEnabled;

@end
