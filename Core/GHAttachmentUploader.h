#import <Foundation/Foundation.h>

extern NSString * const GHAttachmentUploaderErrorDomain;

typedef NS_ENUM(NSInteger, GHAttachmentUploaderErrorCode) {
    GHAttachmentUploaderErrorFailed = 0,
    GHAttachmentUploaderErrorSignInRequired = 401
};

@interface GHAttachmentUploader : NSObject

+ (NSString *)contentTypeForFileName:(NSString *)fileName;
+ (unsigned long long)maximumSizeForContentType:(NSString *)contentType;
+ (NSString *)supportedExtensionsDescription;
+ (NSString *)markdownForFileName:(NSString *)fileName url:(NSString *)url contentType:(NSString *)contentType;

+ (instancetype)uploadData:(NSData *)data
                  fileName:(NSString *)fileName
               contentType:(NSString *)contentType
                     owner:(NSString *)owner
                      repo:(NSString *)repo
              repositoryID:(long long)repositoryID
                  progress:(void (^)(float progress))progress
                completion:(void (^)(NSString *url, NSError *error))completion;

- (void)cancel;

@end
