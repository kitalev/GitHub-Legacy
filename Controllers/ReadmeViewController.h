#import <UIKit/UIKit.h>

@interface ReadmeViewController : UIViewController <UIWebViewDelegate, UIScrollViewDelegate>

@property (nonatomic, copy) NSString *html;
@property (nonatomic, strong) NSURL *baseURL;

@property (nonatomic, copy) NSString *titleTranslationKey;

@property (nonatomic, copy) NSString *ownerLogin;
@property (nonatomic, copy) NSString *repoName;

@property (nonatomic, copy) void (^refreshHandler)(void (^completion)(NSString *html));

@property (nonatomic, assign) CGPoint initialScrollOffset;

@property (nonatomic, copy) NSArray *codeViewerChunkLineCounts;

+ (BOOL)repoTextFileInfoFromURL:(NSURL *)url
                       ownerLogin:(NSString **)ownerLogin
                         repoName:(NSString **)repoName
                             path:(NSString **)path;

+ (BOOL)rootRelativeRawFileNameFromURL:(NSURL *)url fileName:(NSString **)fileName;

+ (void)openRepoFileAtPath:(NSString *)path
                  ownerLogin:(NSString *)ownerLogin
                    repoName:(NSString *)repoName
          fromViewController:(UIViewController *)fromViewController
                 fallbackURL:(NSURL *)fallbackURL;

- (void)evaluateJavaScript:(NSString *)js;

@end
