#import "Manager.h"
#import "../ActionButton/RYGMediaActions.h"

@implementation RYGDownloadManager

- (instancetype)initWithDelegate:(id<RYGDownloadDelegateProtocol>)delegate {
    if ((self = [super init])) {
        _delegate = delegate;
    }
    return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension {
    self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                delegate:self
                                           delegateQueue:nil];
    self.task = [self.session downloadTaskWithURL:url];
    self.fileExtension = fileExtension.length >= 3 ? fileExtension : @"jpg";
    [self.task resume];
    [self.delegate downloadDidStart];
}

- (void)cancelDownload {
    [self.task cancel];
    [self.delegate downloadDidCancel];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if (totalBytesExpectedToWrite <= 0) return;
    float p = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    if ([self.delegate respondsToSelector:@selector(downloadDidProgress:received:total:)])
        [self.delegate downloadDidProgress:p received:totalBytesWritten total:totalBytesExpectedToWrite];
    else
        [self.delegate downloadDidProgress:p];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    [self.delegate downloadDidFinishWithFileURL:[self moveFileToCacheDir:location]];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) NSLog(@"[RyukGram] Download error: %@", error);
    [self.delegate downloadDidFinishWithError:error];
}

- (NSURL *)moveFileToCacheDir:(NSURL *)oldPath {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *stem = [RYGMediaActions currentFilenameStem] ?: NSUUID.UUID.UUIDString;
    NSString *ext = self.fileExtension.length ? self.fileExtension : @"bin";

    NSURL *(^leaf)(NSString *) = ^NSURL *(NSString *name) {
        return [[NSURL fileURLWithPath:cacheDir] URLByAppendingPathComponent:name];
    };
    NSURL *dst = leaf([NSString stringWithFormat:@"%@.%@", stem, ext]);
    for (NSInteger n = 1; n < 1000 && [fm fileExistsAtPath:dst.path]; n++) {
        dst = leaf([NSString stringWithFormat:@"%@-%ld.%@", stem, (long)n, ext]);
    }

    NSError *moveError = nil;
    if (![fm moveItemAtURL:oldPath toURL:dst error:&moveError]) {
        NSLog(@"[RyukGram] move %@ -> %@ failed: %@", oldPath.absoluteString, dst.absoluteString, moveError);
    }
    return dst;
}

@end
