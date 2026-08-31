#import <Foundation/Foundation.h>

typedef void (^GHProgressBlock)(float progress);
typedef void (^GHDownloadCompletionBlock)(NSString *filePath, NSError *error);

@interface DownloadManager : NSObject <NSURLConnectionDataDelegate>

+ (instancetype)sharedManager;

- (void)downloadFileAtURL:(NSURL *)url
                  fileName:(NSString *)fileName
                  progress:(GHProgressBlock)progress
                completion:(GHDownloadCompletionBlock)completion;

@end
