#import "GHAttachmentUploader.h"
#import "GHJSONSerialization.h"
#import "GHWebSession.h"
#import "GHLocalization.h"

NSString * const GHAttachmentUploaderErrorDomain = @"GHAttachmentUploader";

static NSString * const kGHUploadPolicyPath = @"/upload/policies/assets";
static const unsigned long long kGHMaxImageBytes = 10 * 1024 * 1024;
static const unsigned long long kGHMaxVideoBytes = 25 * 1024 * 1024;

typedef NS_ENUM(NSInteger, GHAttachmentUploadStage) {
    GHAttachmentUploadStageToken,
    GHAttachmentUploadStagePolicy,
    GHAttachmentUploadStageStorage,
    GHAttachmentUploadStageFinalize
};

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

static NSString *GHAttachmentString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

static NSData *GHAttachmentMultipartBody(NSArray *fields, NSData *fileData, NSString *fileName,
                                         NSString *contentType, NSString *boundary) {
    NSMutableData *body = [NSMutableData data];
    for (NSArray *field in fields) {
        NSString *part = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
                          boundary, field[0], field[1]];
        [body appendData:[part dataUsingEncoding:NSUTF8StringEncoding]];
    }
    if (fileData) {
        NSString *safeName = [fileName stringByReplacingOccurrencesOfString:@"\"" withString:@"'"];
        NSString *header = [NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: %@\r\n\r\n",
                            boundary, safeName, contentType];
        [body appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:fileData];
        [body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    return body;
}

static NSString *GHAttachmentFirstMatch(NSString *pattern, NSString *text, NSUInteger group) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (match == nil || [match rangeAtIndex:group].location == NSNotFound) return nil;
    return [text substringWithRange:[match rangeAtIndex:group]];
}

static NSString *GHAttachmentUploadToken(NSString *html) {
    NSString *quoted = GHAttachmentFirstMatch(@"\"uploadToken\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\")", html, 1);
    if (quoted.length > 0) {
        NSData *json = [[NSString stringWithFormat:@"[%@]", quoted] dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *decoded = [GHJSONSerialization JSONObjectWithData:json options:0 error:nil];
        NSString *token = [decoded isKindOfClass:[NSArray class]] && decoded.count > 0 ? GHAttachmentString(decoded[0]) : nil;
        if (token.length > 0) return token;
    }

    NSString *input = GHAttachmentFirstMatch(@"<input[^>]*js-data-upload-policy-url-csrf[^>]*>", html, 0);
    NSString *value = input ? GHAttachmentFirstMatch(@"value=\"([^\"]+)\"", input, 1) : nil;
    if (value.length == 0) return nil;
    value = [value stringByReplacingOccurrencesOfString:@"&#x2F;" withString:@"/"];
    value = [value stringByReplacingOccurrencesOfString:@"&#43;" withString:@"+"];
    value = [value stringByReplacingOccurrencesOfString:@"&#x3D;" withString:@"="];
    return [value stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

static NSString *GHAttachmentServerMessage(NSData *data) {
    id json = data.length > 0 ? [GHJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray *messages = [NSMutableArray array];
    id errors = json[@"errors"];
    for (id entry in [errors isKindOfClass:[NSArray class]] ? errors : @[]) {
        NSString *message = [entry isKindOfClass:[NSDictionary class]] ? GHAttachmentString(entry[@"message"]) : GHAttachmentString(entry);
        if (message.length > 0) [messages addObject:message];
    }
    if (messages.count > 0) return [messages componentsJoinedByString:@"; "];
    NSString *message = GHAttachmentString(json[@"message"]) ?: GHAttachmentString(json[@"error"]);
    return message.length > 0 ? message : nil;
}

@interface GHAttachmentUploader () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSData *data;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSString *owner;
@property (nonatomic, copy) NSString *repo;
@property (nonatomic, assign) long long repositoryID;
@property (nonatomic, assign) GHAttachmentUploadStage stage;
@property (nonatomic, strong) NSDictionary *policy;
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
                     owner:(NSString *)owner
                      repo:(NSString *)repo
              repositoryID:(long long)repositoryID
                  progress:(void (^)(float progress))progress
                completion:(void (^)(NSString *url, NSError *error))completion {
    GHAttachmentUploader *uploader = [[GHAttachmentUploader alloc] init];
    uploader.data = data;
    uploader.fileName = fileName;
    uploader.contentType = contentType;
    uploader.owner = owner;
    uploader.repo = repo;
    uploader.repositoryID = repositoryID;
    uploader.progressBlock = progress;
    uploader.completionBlock = completion;
    uploader.responseData = [NSMutableData data];
    [uploader requestUploadToken];
    return uploader;
}

- (void)cancel {
    [self.connection cancel];
    self.connection = nil;
    self.progressBlock = nil;
    self.completionBlock = nil;
}

#pragma mark - Stages

- (NSURL *)issueFormURL {
    NSString *path = [NSString stringWithFormat:@"/%@/%@/issues/new", self.owner, self.repo];
    return [[NSURL URLWithString:path relativeToURL:[GHWebSession baseURL]] absoluteURL];
}

- (NSURL *)gitHubURLForString:(NSString *)string {
    if (string.length == 0) return nil;
    return [[NSURL URLWithString:string relativeToURL:[GHWebSession baseURL]] absoluteURL];
}

- (NSMutableURLRequest *)gitHubRequestWithURL:(NSURL *)url method:(NSString *)method {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.timeoutInterval = 60.0;
    request.HTTPShouldHandleCookies = YES;
    [request setValue:[GHWebSession browserUserAgent] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[[GHWebSession baseURL] absoluteString] forHTTPHeaderField:@"Origin"];
    [request setValue:[[self issueFormURL] absoluteString] forHTTPHeaderField:@"Referer"];
    [request setValue:@"XMLHttpRequest" forHTTPHeaderField:@"X-Requested-With"];
    [request setValue:@"true" forHTTPHeaderField:@"GitHub-Verified-Fetch"];
    return request;
}

- (void)setMultipartFields:(NSArray *)fields file:(BOOL)includeFile onRequest:(NSMutableURLRequest *)request {
    NSString *boundary = [NSString stringWithFormat:@"----GHLegacyBoundary%08X%08X", arc4random(), arc4random()];
    NSData *body = GHAttachmentMultipartBody(fields, includeFile ? self.data : nil, self.fileName, self.contentType, boundary);
    request.HTTPBody = body;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length] forHTTPHeaderField:@"Content-Length"];
}

- (void)startStage:(GHAttachmentUploadStage)stage request:(NSURLRequest *)request {
    self.stage = stage;
    self.response = nil;
    [self.responseData setLength:0];
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
    [self.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.connection start];
}

- (void)requestUploadToken {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self issueFormURL]];
    request.timeoutInterval = 60.0;
    request.HTTPShouldHandleCookies = YES;
    [request setValue:[GHWebSession browserUserAgent] forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"text/html" forHTTPHeaderField:@"Accept"];
    [self startStage:GHAttachmentUploadStageToken request:request];
}

- (void)handleTokenResponse {
    if ([GHWebSession isSignInPageURL:self.response.URL] || ![GHWebSession isSignedIn]) {
        [self failWithCode:GHAttachmentUploaderErrorSignInRequired message:GHL(@"Войдите на github.com, чтобы прикреплять фото и видео.")];
        return;
    }
    NSString *html = [[NSString alloc] initWithData:self.responseData encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithData:self.responseData encoding:NSISOLatin1StringEncoding];
    NSString *token = self.response.statusCode < 400 && html.length > 0 ? GHAttachmentUploadToken(html) : nil;

    NSMutableArray *fields = [NSMutableArray arrayWithObjects:
                              @[@"name", self.fileName],
                              @[@"size", [NSString stringWithFormat:@"%lu", (unsigned long)self.data.length]],
                              @[@"content_type", self.contentType],
                              @[@"repository_id", [NSString stringWithFormat:@"%lld", self.repositoryID]], nil];
    if (token.length > 0) [fields addObject:@[@"authenticity_token", token]];
    NSMutableURLRequest *request = [self gitHubRequestWithURL:[self gitHubURLForString:kGHUploadPolicyPath] method:@"POST"];
    [self setMultipartFields:fields file:NO onRequest:request];
    [self startStage:GHAttachmentUploadStagePolicy request:request];
}

- (void)handlePolicyResponse {
    id json = self.responseData.length > 0 ? [GHJSONSerialization JSONObjectWithData:self.responseData options:0 error:nil] : nil;
    NSDictionary *policy = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSURL *uploadURL = [self gitHubURLForString:GHAttachmentString(policy[@"upload_url"])];
    NSDictionary *form = [policy[@"form"] isKindOfClass:[NSDictionary class]] ? policy[@"form"] : nil;
    if (self.response.statusCode >= 400 || uploadURL == nil || form == nil) {
        if ([GHWebSession isSignInPageURL:self.response.URL]) {
            [self failWithCode:GHAttachmentUploaderErrorSignInRequired message:GHL(@"Войдите на github.com, чтобы прикреплять фото и видео.")];
            return;
        }
        NSString *message = GHAttachmentServerMessage(self.responseData)
            ?: [NSString stringWithFormat:GHL(@"github.com не разрешил загрузку файлов в этот репозиторий (HTTP %ld)."), (long)self.response.statusCode];
        [self failWithCode:GHAttachmentUploaderErrorFailed message:message];
        return;
    }
    self.policy = policy;

    NSMutableArray *fields = [NSMutableArray array];
    for (id key in form) {
        NSString *value = GHAttachmentString(form[key]);
        if ([key isKindOfClass:[NSString class]] && value) [fields addObject:@[key, value]];
    }
    BOOL sameOrigin = [policy[@"same_origin"] boolValue];
    NSString *uploadToken = GHAttachmentString(policy[@"upload_authenticity_token"]);
    if (sameOrigin && uploadToken.length > 0) [fields addObject:@[@"authenticity_token", uploadToken]];

    NSMutableURLRequest *request;
    if (sameOrigin) {
        request = [self gitHubRequestWithURL:uploadURL method:@"POST"];
    } else {
        request = [NSMutableURLRequest requestWithURL:uploadURL];
        request.HTTPMethod = @"POST";
        request.HTTPShouldHandleCookies = NO;
        [request setValue:[GHWebSession browserUserAgent] forHTTPHeaderField:@"User-Agent"];
    }
    request.timeoutInterval = 120.0;
    NSDictionary *headers = [policy[@"header"] isKindOfClass:[NSDictionary class]] ? policy[@"header"] : nil;
    for (id key in headers) {
        NSString *value = GHAttachmentString(headers[key]);
        if ([key isKindOfClass:[NSString class]] && value) [request setValue:value forHTTPHeaderField:key];
    }
    [self setMultipartFields:fields file:YES onRequest:request];
    [self startStage:GHAttachmentUploadStageStorage request:request];
}

- (void)handleStorageResponse {
    if (self.response.statusCode >= 300) {
        [self failWithCode:GHAttachmentUploaderErrorFailed
                   message:[NSString stringWithFormat:GHL(@"Не удалось загрузить файл в хранилище GitHub (HTTP %ld)."), (long)self.response.statusCode]];
        return;
    }

    NSURL *finalizeURL = [self gitHubURLForString:GHAttachmentString(self.policy[@"asset_upload_url"])];
    NSString *finalizeToken = GHAttachmentString(self.policy[@"asset_upload_authenticity_token"]);
    if (finalizeURL == nil || finalizeToken.length == 0) {
        [self finishWithAssetURL:nil];
        return;
    }
    NSMutableURLRequest *request = [self gitHubRequestWithURL:finalizeURL method:@"PUT"];
    [self setMultipartFields:@[@[@"authenticity_token", finalizeToken]] file:NO onRequest:request];
    [self startStage:GHAttachmentUploadStageFinalize request:request];
}

- (void)handleFinalizeResponse {
    if (self.response.statusCode >= 400) {
        [self failWithCode:GHAttachmentUploaderErrorFailed
                   message:GHAttachmentServerMessage(self.responseData)
                               ?: [NSString stringWithFormat:GHL(@"github.com не подтвердил загруженный файл (HTTP %ld)."), (long)self.response.statusCode]];
        return;
    }
    id json = self.responseData.length > 0 ? [GHJSONSerialization JSONObjectWithData:self.responseData options:0 error:nil] : nil;
    [self finishWithAssetURL:[json isKindOfClass:[NSDictionary class]] ? GHAttachmentString(json[@"href"]) : nil];
}

- (void)finishWithAssetURL:(NSString *)href {
    if (href.length == 0) {
        NSDictionary *asset = [self.policy[@"asset"] isKindOfClass:[NSDictionary class]] ? self.policy[@"asset"] : nil;
        href = GHAttachmentString(asset[@"href"]);
    }
    NSString *url = [[self gitHubURLForString:href] absoluteString];
    if (url.length == 0) {
        [self failWithCode:GHAttachmentUploaderErrorFailed message:GHL(@"GitHub не вернул ссылку на загруженный файл.")];
        return;
    }
    [self finishWithURL:url error:nil];
}

- (void)failWithCode:(GHAttachmentUploaderErrorCode)code message:(NSString *)message {
    NSError *error = [NSError errorWithDomain:GHAttachmentUploaderErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: message ?: GHL(@"неизвестная ошибка")}];
    [self finishWithURL:nil error:error];
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
    if (self.stage != GHAttachmentUploadStageStorage) return;
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
    if (self.response == nil) {
        [self failWithCode:GHAttachmentUploaderErrorFailed message:nil];
        return;
    }
    switch (self.stage) {
        case GHAttachmentUploadStageToken:
            [self handleTokenResponse];
            break;
        case GHAttachmentUploadStagePolicy:
            [self handlePolicyResponse];
            break;
        case GHAttachmentUploadStageStorage:
            [self handleStorageResponse];
            break;
        case GHAttachmentUploadStageFinalize:
            [self handleFinalizeResponse];
            break;
    }
}

@end
