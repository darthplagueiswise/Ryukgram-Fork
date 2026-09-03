#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#import "../InstagramHeaders.h"
#import "../Utils.h"

#import "Manager.h"

@class RYGDownloadJob;

@interface RYGDownloadPillView : UIView
@property (nonatomic, copy) void (^onCancel)(void);

- (void)resetState;
- (void)showInView:(UIView *)view;
- (void)dismiss;
- (void)dismissAfterDelay:(NSTimeInterval)delay;
- (void)setProgress:(float)progress;
- (void)setText:(NSString *)text;
- (void)setSubtitle:(NSString *)text;
- (void)showSuccess:(NSString *)text;
- (void)showError:(NSString *)text;

// Multi-download ticket API. All methods are safe from any thread.
// Tap-to-cancel pops the most recently pushed ticket.
- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel;
- (void)updateTicket:(NSString *)ticketId progress:(float)progress;
- (void)updateTicket:(NSString *)ticketId text:(NSString *)text;
- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message;
- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message;
- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message;
- (void)dismissTicket:(NSString *)ticketId;

/// Shared singleton pill — reused across all downloads so only one shows at a time.
+ (instancetype)shared;
@end

@interface RYGDownloadDelegate : NSObject <RYGDownloadDelegateProtocol>

typedef NS_ENUM(NSUInteger, DownloadAction) {
    share,
    quickLook,
    saveToPhotos,
    saveToGallery
};
@property (nonatomic, readonly) DownloadAction action;
@property (nonatomic, readonly) BOOL showProgress;
/// Optional gallery metadata. When set + the global save mode includes the
/// gallery, the download is also (or instead) logged into the RyukGram gallery.
@property (nonatomic, strong, nullable) id pendingGallerySaveMetadata;

@property (nonatomic, strong) RYGDownloadManager *downloadManager;
@property (nonatomic, strong) RYGDownloadJob *job;
/// Set by retries and batch callers that already passed the duplicate check.
@property (nonatomic, assign) BOOL skipDuplicateCheck;

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress;

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel;

/// For files already on disk — runs the configured action (save/share) and reports
/// through the download center, no network fetch.
- (void)saveLocalFileURL:(NSURL *)fileURL hudLabel:(NSString *)hudLabel;

@end
