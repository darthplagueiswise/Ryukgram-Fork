#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@protocol RYGDownloadDelegateProtocol <NSObject>

- (void)downloadDidStart;
- (void)downloadDidCancel;
- (void)downloadDidProgress:(float)progress;
- (void)downloadDidFinishWithError:(NSError *)error;
- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL;

@optional
- (void)downloadDidProgress:(float)progress received:(int64_t)received total:(int64_t)total;
- (NSString *)rygFilenameStem;

@end

@interface RYGDownloadManager : NSObject <NSURLSessionDownloadDelegate>

@property (nonatomic, weak) id<RYGDownloadDelegateProtocol> delegate;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSString *fileExtension;

- (instancetype)initWithDelegate:(id<RYGDownloadDelegateProtocol>)downloadDelegate;

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension;

- (void)cancelDownload;

- (NSURL *)moveFileToCacheDir:(NSURL *)oldPath;

@end
