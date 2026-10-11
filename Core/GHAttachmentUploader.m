#import "GHAttachmentUploader.h"
#import "GHAPIClient.h"
#import "GHAuthManager.h"
#import "GHLocalization.h"

static NSString * const kGHAttachmentUploadURL = @"https://uploads.github.com/user-attachments/assets";
static const unsigned long long kGHMaxImageBytes = 10 * 1024 * 1024;
static const unsigned long long kGHMaxVideoBytes = 25 * 1024 * 1024;

static NSArray *GHAttachmentContentTypes(void) {
    return @[@[@"png", @"image/png"],
             @[@"jpg", @"image/jpeg"],
             @[@"jpeg", @"image/jpeg"],
             @[@"gif", @"image/gif"],
             @[@"webp", @"image/webp"],
             @[@"svg", @"image/svg+xml"],
             @[@"mp4", @"video/mp4"],
             @[@"mov", @"video/quicktime"],
             @[@"webm", @"video/webm"]];
}

static NSString *GHAttachmentQueryEscape(NSString *string) {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                               (__bridge CFStringRef)(string ?: @""),
                                                                               NULL,
                                                                               CFSTR("!*'();:@&=+$,/?%#[]\" "),
                                                                               kCFStringEncodingUTF8);
}

@interface GHAttachmentUploader () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSHTTPURLResponse *response;
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic, copy) void (^progressBlock)(float progress);
@property (nonatomic, copy) void (^completionBlock)(NSString *url, NSError *error);
@end

@implementation GHAttachmentUploader

+ (NSString *)contentTypeForFileName:(NSString *)fileName {
    NSString *extension = [[fileName pathExtension] lowercaseString];
    for (NSArray *entry in GHAttachmentContentTypes()) {
        if ([entry[0] isEqualToString:extension]) return entry[1];
    }
    return nil;
}

+ (unsigned long long)maximumSizeForContentType:(NSString *)contentType {
    return [contentType hasPrefix:@"video/"] ? kGHMaxVideoBytes : kGHMaxImageBytes;
}

+ (NSString *)supportedExtensionsDescription {
    NSMutableArray *extensions = [NSMutableArray array];
    for (NSArray *entry in GHAttachmentContentTypes()) {
        if (![entry[0] isEqualToString:@"jpeg"]) [extensions addObject:entry[0]];
    }
    return [extensions componentsJoinedByString:@", "];
}

+ (NSString *)markdownForFileName:(NSString *)fileName url:(NSString *)url contentType:(NSString *)contentType {
    if ([contentType hasPrefix:@"video/"]) return url;

    NSString *alt = [[fileName stringByDeletingPathExtension] stringByReplacingOccurrencesOfString:@"." withString:@" "];
    alt = [alt stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    alt = [alt stringByReplacingOccurrencesOfString:@"[" withString:@"\\["];
    alt = [alt stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"];
    alt = [[alt componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return [NSString stringWithFormat:@"![%@](%@)", alt, url];
}

+ (instancetype)uploadData:(NSData *)data
                  fileName:(NSString *)fileName
               contentType:(NSString *)contentType
              repositoryID:(long long)repositoryID
                  progress:(void (^)(float progress))progress
                completion:(void (^)(NSString *url, NSError *error))completion {
    GHAttachmentUploader *uploader = [[GHAttachmentUploader alloc] init];
    uploader.progressBlock = progress;
    uploader.completionBlock = completion;

    NSString *urlString = [NSString stringWithFormat:@"%@?name=%@&content_type=%@&repository_id=%lld",
                           kGHAttachmentUploadURL,
                           GHAttachmentQueryEscape(fileName),
                           GHAttachmentQueryEscape(contentType),
                           repositoryID];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = data;
    request.timeoutInterval = 120.0;
    [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)data.length] forHTTPHeaderField:@"Content-Length"];

    NSString *token = [GHAuthManager sharedManager].accessToken;
    if (token.length > 0) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    uploader.responseData = [NSMutableData data];
    uploader.connection = [[NSURLConnection alloc] initWithRequest:request delegate:uploader startImmediately:NO];
    [uploader.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [uploader.connection start];
    return uploader;
}

- (void)cancel {
    [self.connection cancel];
    self.connection = nil;
    self.progressBlock = nil;
    self.completionBlock = nil;
}

- (void)finishWithURL:(NSString *)url error:(NSError *)error {
    void (^completion)(NSString *, NSError *) = self.completionBlock;
    self.completionBlock = nil;
    self.progressBlock = nil;
    self.connection = nil;
    if (completion) completion(url, error);
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection
   didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalBytesWritten
totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    if (self.progressBlock && totalBytesExpectedToWrite > 0) {
        self.progressBlock(MIN(1.0f, (float)totalBytesWritten / (float)totalBytesExpectedToWrite));
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    self.response = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    [self.responseData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self finishWithURL:nil error:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSInteger status = self.response.statusCode;
    if (status == 404) {
        NSError *error = [NSError errorWithDomain:@"GHAttachmentUploader"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: GHL(@"GitHub не разрешил загрузку: для этого нужно право записи в репозиторий.")}];
        [self finishWithURL:nil error:error];
        return;
    }
    if (status >= 400 || self.response == nil) {
        [self finishWithURL:nil error:[[GHAPIClient sharedClient] errorForHTTPResponse:self.response data:self.responseData]];
        return;
    }

    id json = self.responseData.length > 0 ? [NSJSONSerialization JSONObjectWithData:self.responseData options:0 error:nil] : nil;
    id url = [json isKindOfClass:[NSDictionary class]] ? json[@"url"] : nil;
    if (![url isKindOfClass:[NSString class]] || [url length] == 0) {
        NSError *error = [NSError errorWithDomain:@"GHAttachmentUploader"
                                             code:0
                                         userInfo:@{NSLocalizedDescriptionKey: GHL(@"GitHub не вернул ссылку на загруженный файл.")}];
        [self finishWithURL:nil error:error];
        return;
    }
    [self finishWithURL:url error:nil];
}

@end
