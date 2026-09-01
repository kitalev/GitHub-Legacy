#import "DownloadManager.h"
#import "GHLocalization.h"

@interface GHDownloadContext : NSObject
@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, assign) long long expectedLength;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) GHProgressBlock progressBlock;
@property (nonatomic, copy) GHDownloadCompletionBlock completionBlock;
@end

@implementation GHDownloadContext
@end

@interface DownloadManager ()

@property (nonatomic, strong) NSMutableDictionary *contexts;
@end

@implementation DownloadManager

+ (instancetype)sharedManager {
    static DownloadManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DownloadManager alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        _contexts = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)documentsDirectory {

    NSString *standardPath = @"/var/mobile/Media/Downloads";
    NSFileManager *fm = [NSFileManager defaultManager];

    BOOL isDirectory = NO;
    BOOL exists = [fm fileExistsAtPath:standardPath isDirectory:&isDirectory];
    if (!exists) {
        NSError *createError = nil;
        [fm createDirectoryAtPath:standardPath
       withIntermediateDirectories:YES
                        attributes:nil
                             error:&createError];
        exists = [fm fileExistsAtPath:standardPath isDirectory:&isDirectory];
    }

    if (exists && isDirectory && [fm isWritableFileAtPath:standardPath]) {
        return standardPath;
    }

    NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"];

    isDirectory = NO;
    exists = [fm fileExistsAtPath:downloadsPath isDirectory:&isDirectory];

    if (!exists) {
        NSError *createError = nil;
        [fm createDirectoryAtPath:downloadsPath
       withIntermediateDirectories:YES
                        attributes:nil
                             error:&createError];
    }

    return downloadsPath;
}

- (NSString *)keyForConnection:(NSURLConnection *)connection {

    return [NSString stringWithFormat:@"%p", connection];
}

- (void)downloadFileAtURL:(NSURL *)url
                  fileName:(NSString *)fileName
                  progress:(GHProgressBlock)progressBlock
                completion:(GHDownloadCompletionBlock)completionBlock {

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"GitHubLegacy-iOS6" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:60.0];

    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request
                                                                    delegate:self
                                                            startImmediately:NO];
    if (!connection) {
        if (completionBlock) {
            NSError *err = [NSError errorWithDomain:@"DownloadManager" code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: GHL(@"Не удалось создать соединение")}];
            completionBlock(nil, err);
        }
        return;
    }

    GHDownloadContext *ctx = [[GHDownloadContext alloc] init];
    ctx.receivedData = [NSMutableData data];
    ctx.expectedLength = 0;
    ctx.filePath = [[self documentsDirectory] stringByAppendingPathComponent:fileName];
    ctx.progressBlock = progressBlock;
    ctx.completionBlock = completionBlock;

    self.contexts[[self keyForConnection:connection]] = ctx;

    [connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [connection start];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    GHDownloadContext *ctx = self.contexts[[self keyForConnection:connection]];
    ctx.expectedLength = response.expectedContentLength;
    [ctx.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    GHDownloadContext *ctx = self.contexts[[self keyForConnection:connection]];
    [ctx.receivedData appendData:data];

    if (ctx.progressBlock && ctx.expectedLength > 0) {
        float progress = (float)ctx.receivedData.length / (float)ctx.expectedLength;
        ctx.progressBlock(progress);
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    NSString *key = [self keyForConnection:connection];
    GHDownloadContext *ctx = self.contexts[key];
    if (ctx.completionBlock) {
        ctx.completionBlock(nil, error);
    }
    [self.contexts removeObjectForKey:key];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSString *key = [self keyForConnection:connection];
    GHDownloadContext *ctx = self.contexts[key];

    NSError *writeError = nil;
    BOOL success = [ctx.receivedData writeToFile:ctx.filePath options:NSDataWritingAtomic error:&writeError];

    if (ctx.completionBlock) {
        if (success) {
            ctx.completionBlock(ctx.filePath, nil);
        } else {
            ctx.completionBlock(nil, writeError);
        }
    }
    [self.contexts removeObjectForKey:key];
}

@end
