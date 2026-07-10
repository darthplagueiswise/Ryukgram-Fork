#import "Download.h"
#import "SCIDownloadCenter.h"
#import "../PhotoAlbum.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Compat shim — forwards the legacy ticket / non-ticket API to SCINotificationCenter.
// Each ticket gets its own SCINotificationHandle; the non-ticket API drives one
// shared ad-hoc handle. New code should call SCINotifyProgress directly.

static inline float SCIClamp(float v) {
	return MAX(0.0f, MIN(v, 1.0f));
}

static NSString *sciDownloadKindWord(NSString *ext) {
	NSString *e = ext.lowercaseString;
	if ([@[@"mp4", @"mov", @"m4v"] containsObject:e]) return SCILocalized(@"Video");
	if ([@[@"m4a", @"mp3", @"aac", @"wav"] containsObject:e]) return SCILocalized(@"Audio");
	if ([@[@"jpg", @"jpeg", @"png", @"heic", @"webp", @"gif"] containsObject:e]) return SCILocalized(@"Photo");
	return SCILocalized(@"File");
}

// Manager card labels: "@username" + kind, or just the kind word when anonymous.
static NSString *sciJobTitle(id meta, NSString *ext, NSString **outSubtitle) {
	SCIGallerySaveMetadata *gm = [meta isKindOfClass:[SCIGallerySaveMetadata class]] ? meta : nil;
	NSString *kindWord = sciDownloadKindWord(ext);
	if (outSubtitle) *outSubtitle = gm.sourceUsername.length ? kindWord : nil;
	return gm.sourceUsername.length ? [@"@" stringByAppendingString:gm.sourceUsername] : kindWord;
}

@interface SCIDownloadPillView ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCINotificationHandle *> *ticketHandles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ticketTitles;
@property (nonatomic, strong) SCINotificationHandle *adHocHandle;
@property (nonatomic, copy)   NSString *adHocTitle;
@property (nonatomic, copy)   NSString *adHocSubtitle;
@end

@implementation SCIDownloadPillView

+ (instancetype)shared {
	static SCIDownloadPillView *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [SCIDownloadPillView new]; });
	return shared;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;
	_ticketHandles = [NSMutableDictionary new];
	_ticketTitles = [NSMutableDictionary new];
	return self;
}

- (void)sciOnMain:(dispatch_block_t)block {
	if (!block) return;
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)sciEnsureAdHocStarted {
	if (self.adHocHandle && !self.adHocHandle.isFinished) return;
	__weak typeof(self) weakSelf = self;
	self.adHocHandle = SCINotifyProgress(SCI_NOTIF_DOWNLOAD,
	                                     self.adHocTitle ?: SCILocalized(@"Downloading…"),
	                                     ^{
		void (^cb)(void) = weakSelf.onCancel;
		weakSelf.onCancel = nil;
		if (cb) cb();
	});
}

#pragma mark - Legacy non-ticket API (forwards to a single ad-hoc handle)

- (void)resetState {
	[self sciOnMain:^{
		[self.adHocHandle dismiss];
		self.adHocHandle = nil;
		self.adHocTitle = SCILocalized(@"Downloading…");
		self.adHocSubtitle = nil;
	}];
}

- (void)showInView:(UIView *)view {
	(void)view; // Center handles host view internally.
	[self sciOnMain:^{ [self sciEnsureAdHocStarted]; }];
}

- (void)dismiss {
	[self sciOnMain:^{
		[self.adHocHandle dismiss];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)dismissAfterDelay:(NSTimeInterval)delay {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self dismiss];
	});
}

- (void)setProgress:(float)progress {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle setProgress:SCIClamp(progress)];
	}];
}

- (void)setText:(NSString *)text {
	[self sciOnMain:^{
		self.adHocTitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setTitle:text ?: @""];
		}
	}];
}

- (void)setSubtitle:(NSString *)text {
	[self sciOnMain:^{
		self.adHocSubtitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setSubtitle:text];
		}
	}];
}

- (void)showSuccess:(NSString *)text {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle success:text ?: SCILocalized(@"Done")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)showError:(NSString *)text {
	[self sciOnMain:^{
		[self sciEnsureAdHocStarted];
		[self.adHocHandle error:text ?: SCILocalized(@"Failed")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

#pragma mark - Ticket API (one handle per ticket)

- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel {
	NSString *ticketId = NSUUID.UUID.UUIDString;
	NSString *resolvedTitle = title ?: SCILocalized(@"Downloading…");
	void (^cancelCopy)(void) = [cancel copy];
	[self sciOnMain:^{
		SCINotificationHandle *h = SCINotifyProgress(SCI_NOTIF_DOWNLOAD, resolvedTitle, cancelCopy);
		if (h) self.ticketHandles[ticketId] = h;
		self.ticketTitles[ticketId] = resolvedTitle;
	}];
	return ticketId;
}

- (void)updateTicket:(NSString *)ticketId progress:(float)progress {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] setProgress:SCIClamp(progress)];
	}];
}

- (void)updateTicket:(NSString *)ticketId text:(NSString *)text {
	if (!ticketId.length || !text.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] setTitle:text];
		self.ticketTitles[ticketId] = text;
	}];
}

- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] success:message ?: SCILocalized(@"Done")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] error:message ?: SCILocalized(@"Failed")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] cancelled:message ?: SCILocalized(@"Cancelled")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)dismissTicket:(NSString *)ticketId {
	if (!ticketId.length) return;
	[self sciOnMain:^{
		[self.ticketHandles[ticketId] dismiss];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

@end

@implementation SCIDownloadDelegate

// SCIDownloadManager.delegate is weak — self-pin while a download is in flight.
+ (NSMutableSet *)sciActiveSet {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

- (void)sciPin {
	NSMutableSet *s = [SCIDownloadDelegate sciActiveSet];
	@synchronized (s) { [s addObject:self]; }
}

- (void)sciUnpin {
	NSMutableSet *s = [SCIDownloadDelegate sciActiveSet];
	dispatch_async(dispatch_get_main_queue(), ^{
		@synchronized (s) { [s removeObject:self]; }
	});
}

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
	self = [super init];

	if (self) {
		_action = action;
		_showProgress = showProgress;
		self.downloadManager = [[SCIDownloadManager alloc] initWithDelegate:self];
	}

	return self;
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
	__weak typeof(self) weakSelf = self;

	[self sciPin];

	// Capture inputs so a failed/finished job can be rebuilt from scratch.
	NSString *ext = fileExtension;
	NSString *label = hudLabel ?: SCILocalized(@"Downloading…");
	DownloadAction act = self.action;
	BOOL prog = self.showProgress;
	id meta = self.pendingGallerySaveMetadata;

	NSString *subtitle = nil;
	NSString *jobTitle = sciJobTitle(meta, ext, &subtitle);

	SCIDownloadJob *job = [[SCIDownloadCenter shared] enqueueJobWithTitle:jobTitle
	                                                                kind:SCIDownloadJobKindSimpleURL
	                                                               start:^{
		[weakSelf.downloadManager downloadFileWithURL:url fileExtension:ext];
	}
	                                                              cancel:^{
		[weakSelf.downloadManager cancelDownload];
	}];
	job.subtitle = subtitle;
	job.retryBlock = ^{
		SCIDownloadDelegate *fresh = [[SCIDownloadDelegate alloc] initWithAction:act showProgress:prog];
		fresh.pendingGallerySaveMetadata = meta;
		[fresh downloadFileWithURL:url fileExtension:ext hudLabel:label];
	};
	self.job = job;
}

// Already-on-disk file (e.g. cached media): no network step, just run the save
// through a center job so it surfaces in the pill + manager like any download.
- (void)saveLocalFileURL:(NSURL *)fileURL hudLabel:(NSString *)hudLabel {
	(void)hudLabel;
	__weak typeof(self) weakSelf = self;
	[self sciPin];

	NSString *subtitle = nil;
	NSString *jobTitle = sciJobTitle(self.pendingGallerySaveMetadata, fileURL.pathExtension, &subtitle);

	SCIDownloadJob *job = [[SCIDownloadCenter shared] enqueueJobWithTitle:jobTitle
	                                                                kind:SCIDownloadJobKindSimpleURL
	                                                               start:^{
		[weakSelf downloadDidFinishWithFileURL:fileURL];
	}
	                                                              cancel:nil];
	job.subtitle = subtitle;
	self.job = job;
}

- (void)downloadDidStart {
}

- (void)downloadDidCancel {
	[[SCIDownloadCenter shared] markJobCancelled:self.job];
	[self sciUnpin];
}

- (void)downloadDidProgress:(float)progress {
	float safeProgress = SCIClamp(progress);
	NSString *text = [NSString stringWithFormat:SCILocalized(@"Downloading %d%%"), (int)(safeProgress * 100.0f)];
	[[SCIDownloadCenter shared] job:self.job didProgress:safeProgress stage:text];
}

- (void)downloadDidFinishWithError:(NSError *)error {
	if (!error || error.code == NSURLErrorCancelled) {
		[self sciUnpin];
		return;
	}

	NSLog(@"[RyukGram] Download: Download failed with error: \"%@\"", error);

	[[SCIDownloadCenter shared] markJob:self.job failedWithError:error];
	[self sciUnpin];
}

- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.job.resultFileURL = fileURL;

		NSString *galleryMode = [SCIUtils getStringPref:@"gallery_save_mode"];
		BOOL isAudio = SCIGalleryExtensionIsAudio(fileURL.pathExtension);

		switch (self.action) {
			case share:
				self.job.successText = SCILocalized(@"Done");
				[SCIUtils showShareVC:[self sciShareReadyURL:fileURL]];
				if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
					[self logFileToGalleryQuiet:fileURL];
				}
				[[SCIDownloadCenter shared] markJobFinished:self.job];
				break;

			case quickLook:
				self.job.successText = SCILocalized(@"Done");
				[SCIUtils showQuickLookVC:@[fileURL]];
				[[SCIDownloadCenter shared] markJobFinished:self.job];
				break;

			case saveToPhotos:
				// Photos library rejects audio — fall back to gallery / share.
				if (isAudio) {
					if ([galleryMode isEqualToString:@"off"] || galleryMode.length == 0) {
						self.job.successText = SCILocalized(@"Done");
						[[SCIDownloadCenter shared] markJobFinished:self.job];
						[SCIUtils showShareVC:fileURL];
					} else {
						[self saveFileToGallery:fileURL];
					}
					break;
				}
				if ([galleryMode isEqualToString:@"gallery_only"]) {
					[self saveFileToGallery:fileURL];
				} else {
					[self saveFileToPhotos:fileURL];
					if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
						[self logFileToGalleryQuiet:fileURL];
					}
				}
				break;

			case saveToGallery:
				[self saveFileToGallery:fileURL];
				break;
		}
		[self sciUnpin];
	});
}

- (void)saveFileToGallery:(NSURL *)fileURL {
	NSError *err = nil;
	SCIGalleryFile *file = [self saveFileURL:fileURL toGalleryWithError:&err];
	if (file && !err) {
		self.job.successText = SCILocalized(@"Saved to Gallery");
		[[SCIDownloadCenter shared] markJobFinished:self.job];
	} else {
		NSLog(@"[RyukGram] Gallery save failed: %@", err);
		[[SCIDownloadCenter shared] markJob:self.job failedWithError:err];
	}
}

// Mirror mode: fire-and-forget gallery log alongside the Photos save.
- (void)logFileToGalleryQuiet:(NSURL *)fileURL {
	NSError *err = nil;
	[self saveFileURL:fileURL toGalleryWithError:&err];
	if (err) NSLog(@"[RyukGram] Gallery mirror log failed: %@", err);
}

// Copies (not moves) so share/Photos flow can still use the source file.
- (SCIGalleryFile *)saveFileURL:(NSURL *)fileURL toGalleryWithError:(NSError **)error {
	SCIGalleryMediaType mediaType = SCIGalleryMediaTypeForExtension(fileURL.pathExtension);
	SCIGallerySaveMetadata *metadata = [self.pendingGallerySaveMetadata isKindOfClass:[SCIGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata
		: nil;
	SCIGallerySource source = metadata ? (SCIGallerySource)metadata.source : SCIGallerySourceOther;
	return [SCIGalleryFile saveFileToGallery:fileURL
	                                  source:source
	                               mediaType:mediaType
	                              folderPath:nil
	                                metadata:metadata
	                                   error:error];
}
// Gallery-scheme filename with the real extension kept, so a scratch fileURL never leaks its name.
- (NSString *)sciCleanFilenameForURL:(NSURL *)fileURL {
	SCIGallerySaveMetadata *md = [self.pendingGallerySaveMetadata isKindOfClass:[SCIGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata : nil;
	SCIGalleryMediaType mediaType = SCIGalleryMediaTypeForExtension(fileURL.pathExtension);
	NSString *ext = fileURL.pathExtension;
	NSString *name = SCIFileNameForMedia(fileURL, mediaType, md);
	return ext.length ? [[name stringByDeletingPathExtension] stringByAppendingPathExtension:ext] : name;
}

// Scratch files get a clean-named hardlink for share (no data copy); clean names pass through.
- (NSURL *)sciShareReadyURL:(NSURL *)fileURL {
	NSString *name = fileURL.lastPathComponent;
	if (![name hasPrefix:@"ryuk_tmp_"] && ![name hasPrefix:@"sci_tmp_"]) return fileURL;
	NSURL *dst = [SCITempFiles claimNamedFile:[self sciCleanFilenameForURL:fileURL] ttl:600 tag:@"share"];
	NSFileManager *fm = NSFileManager.defaultManager;
	if ([fm linkItemAtURL:fileURL toURL:dst error:nil] || [fm copyItemAtURL:fileURL toURL:dst error:nil]) return dst;
	[SCITempFiles releaseURL:dst];
	return fileURL;
}

- (void)saveFileToPhotos:(NSURL *)fileURL {
	NSString *cleanName = [self sciCleanFilenameForURL:fileURL];
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
				[[SCIDownloadCenter shared] markJob:self.job failedWithError:nil];
			});

			return;
		}
		BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
		void (^done)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					self.job.successText = useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos");
					[[SCIDownloadCenter shared] markJobFinished:self.job];
				} else {
					NSLog(@"[RyukGram] Download: Save to Photos failed: %@", error);
					[[SCIDownloadCenter shared] markJob:self.job failedWithError:error];
				}
			});
		};
		if (useAlbum) {
			[SCIPhotoAlbum saveFileToAlbum:fileURL originalFilename:cleanName completion:done];
			return;
		}
		[[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
			NSString *ext = fileURL.pathExtension.lowercaseString;
			BOOL isVideo = [@[@"mp4", @"mov", @"m4v"] containsObject:ext];
			PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
			PHAssetResourceCreationOptions *options = PHAssetResourceCreationOptions.new;
			options.shouldMoveFile = YES;
			if (cleanName.length) options.originalFilename = cleanName;
			[request addResourceWithType:(isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto) fileURL:fileURL options:options];
			request.creationDate = NSDate.date;
		} completionHandler:done];
	}];
}
@end
