#import "Download.h"
#import "RYGDownloadCenter.h"
#import "RYGDownloadLedger.h"
#import "../PhotoAlbum.h"
#import "../Gallery/RYGGalleryFile.h"
#import "../Gallery/RYGGallerySaveMetadata.h"
#import "../RYGFileNaming.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Compat shim — forwards the legacy ticket / non-ticket API to RYGNotificationCenter.
// Each ticket gets its own RYGNotificationHandle; the non-ticket API drives one
// shared ad-hoc handle. New code should call RYGNotifyProgress directly.

static inline float RYGClamp(float v) {
	return MAX(0.0f, MIN(v, 1.0f));
}

static NSString *rygDownloadKindWord(NSString *ext) {
	NSString *e = ext.lowercaseString;
	if ([@[@"mp4", @"mov", @"m4v"] containsObject:e]) return RYGLocalized(@"Video");
	if ([@[@"m4a", @"mp3", @"aac", @"wav"] containsObject:e]) return RYGLocalized(@"Audio");
	if ([@[@"jpg", @"jpeg", @"png", @"heic", @"webp", @"gif"] containsObject:e]) return RYGLocalized(@"Photo");
	return RYGLocalized(@"File");
}

// Manager card labels: "@username" + kind, or just the kind word when anonymous.
static NSString *rygJobTitle(id meta, NSString *ext, NSString **outSubtitle) {
	RYGGallerySaveMetadata *gm = [meta isKindOfClass:[RYGGallerySaveMetadata class]] ? meta : nil;
	NSString *kindWord = rygDownloadKindWord(ext);
	if (outSubtitle) *outSubtitle = kindWord;
	return gm.sourceUsername.length ? [@"@" stringByAppendingString:gm.sourceUsername] : kindWord;
}

static NSString *const kRYGRetryKindURL = @"url";

static NSDictionary *rygURLRetryInfo(NSURL *url, NSString *ext, NSString *label,
                                     DownloadAction action, BOOL showProgress, id meta) {
	if (!url.absoluteString.length) return nil;
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"kind"] = kRYGRetryKindURL;
	info[@"url"] = url.absoluteString;
	info[@"action"] = @(action);
	info[@"showProgress"] = @(showProgress);
	if (ext.length) info[@"ext"] = ext;
	if (label.length) info[@"label"] = label;
	RYGGallerySaveMetadata *gm = [meta isKindOfClass:[RYGGallerySaveMetadata class]] ? meta : nil;
	if (gm) info[@"meta"] = [gm dictionaryRepresentation];
	return info;
}

@interface RYGDownloadPillView ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, RYGNotificationHandle *> *ticketHandles;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *ticketTitles;
@property (nonatomic, strong) RYGNotificationHandle *adHocHandle;
@property (nonatomic, copy)   NSString *adHocTitle;
@property (nonatomic, copy)   NSString *adHocSubtitle;
@end

@implementation RYGDownloadPillView

+ (instancetype)shared {
	static RYGDownloadPillView *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [RYGDownloadPillView new]; });
	return shared;
}

- (instancetype)init {
	self = [super initWithFrame:CGRectZero];
	if (!self) return nil;
	_ticketHandles = [NSMutableDictionary new];
	_ticketTitles = [NSMutableDictionary new];
	return self;
}

- (void)rygOnMain:(dispatch_block_t)block {
	if (!block) return;
	NSThread.isMainThread ? block() : dispatch_async(dispatch_get_main_queue(), block);
}

- (void)rygEnsureAdHocStarted {
	if (self.adHocHandle && !self.adHocHandle.isFinished) return;
	__weak typeof(self) weakSelf = self;
	self.adHocHandle = RYGNotifyProgress(RYG_NOTIF_DOWNLOAD,
	                                     self.adHocTitle ?: RYGLocalized(@"Downloading…"),
	                                     ^{
		void (^cb)(void) = weakSelf.onCancel;
		weakSelf.onCancel = nil;
		if (cb) cb();
	});
}

#pragma mark - Legacy non-ticket API (forwards to a single ad-hoc handle)

- (void)resetState {
	[self rygOnMain:^{
		[self.adHocHandle dismiss];
		self.adHocHandle = nil;
		self.adHocTitle = RYGLocalized(@"Downloading…");
		self.adHocSubtitle = nil;
	}];
}

- (void)showInView:(UIView *)view {
	(void)view; // Center handles host view internally.
	[self rygOnMain:^{ [self rygEnsureAdHocStarted]; }];
}

- (void)dismiss {
	[self rygOnMain:^{
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
	[self rygOnMain:^{
		[self rygEnsureAdHocStarted];
		[self.adHocHandle setProgress:RYGClamp(progress)];
	}];
}

- (void)setText:(NSString *)text {
	[self rygOnMain:^{
		self.adHocTitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setTitle:text ?: @""];
		}
	}];
}

- (void)setSubtitle:(NSString *)text {
	[self rygOnMain:^{
		self.adHocSubtitle = text;
		if (self.adHocHandle && !self.adHocHandle.isFinished) {
			[self.adHocHandle setSubtitle:text];
		}
	}];
}

- (void)showSuccess:(NSString *)text {
	[self rygOnMain:^{
		[self rygEnsureAdHocStarted];
		[self.adHocHandle success:text ?: RYGLocalized(@"Done")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

- (void)showError:(NSString *)text {
	[self rygOnMain:^{
		[self rygEnsureAdHocStarted];
		[self.adHocHandle error:text ?: RYGLocalized(@"Failed")];
		self.adHocHandle = nil;
		self.onCancel = nil;
	}];
}

#pragma mark - Ticket API (one handle per ticket)

- (NSString *)beginTicketWithTitle:(NSString *)title onCancel:(void (^)(void))cancel {
	NSString *ticketId = NSUUID.UUID.UUIDString;
	NSString *resolvedTitle = title ?: RYGLocalized(@"Downloading…");
	void (^cancelCopy)(void) = [cancel copy];
	[self rygOnMain:^{
		RYGNotificationHandle *h = RYGNotifyProgress(RYG_NOTIF_DOWNLOAD, resolvedTitle, cancelCopy);
		if (h) self.ticketHandles[ticketId] = h;
		self.ticketTitles[ticketId] = resolvedTitle;
	}];
	return ticketId;
}

- (void)updateTicket:(NSString *)ticketId progress:(float)progress {
	if (!ticketId.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] setProgress:RYGClamp(progress)];
	}];
}

- (void)updateTicket:(NSString *)ticketId text:(NSString *)text {
	if (!ticketId.length || !text.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] setTitle:text];
		self.ticketTitles[ticketId] = text;
	}];
}

- (void)finishTicket:(NSString *)ticketId successMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] success:message ?: RYGLocalized(@"Done")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId errorMessage:(NSString *)message {
	if (!ticketId.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] error:message ?: RYGLocalized(@"Failed")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)finishTicket:(NSString *)ticketId cancelled:(NSString *)message {
	if (!ticketId.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] cancelled:message ?: RYGLocalized(@"Cancelled")];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

- (void)dismissTicket:(NSString *)ticketId {
	if (!ticketId.length) return;
	[self rygOnMain:^{
		[self.ticketHandles[ticketId] dismiss];
		[self.ticketHandles removeObjectForKey:ticketId];
		[self.ticketTitles removeObjectForKey:ticketId];
	}];
}

@end

@implementation RYGDownloadDelegate

+ (void)load {
	[RYGDownloadCenter registerRetryBuilder:^(NSDictionary *info) {
		NSURL *url = [NSURL URLWithString:info[@"url"] ?: @""];
		if (!url) return;
		RYGDownloadDelegate *fresh = [[RYGDownloadDelegate alloc] initWithAction:(DownloadAction)[info[@"action"] unsignedIntegerValue]
		                                                            showProgress:[info[@"showProgress"] boolValue]];
		fresh.pendingGallerySaveMetadata = [RYGGallerySaveMetadata metadataFromDictionary:info[@"meta"]];
		fresh.skipDuplicateCheck = YES;
		[fresh downloadFileWithURL:url fileExtension:info[@"ext"] hudLabel:info[@"label"]];
	} forKind:kRYGRetryKindURL];
}

// RYGDownloadManager.delegate is weak — self-pin while a download is in flight.
+ (NSMutableSet *)rygActiveSet {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

- (void)rygPin {
	NSMutableSet *s = [RYGDownloadDelegate rygActiveSet];
	@synchronized (s) { [s addObject:self]; }
}

- (void)rygUnpin {
	NSMutableSet *s = [RYGDownloadDelegate rygActiveSet];
	dispatch_async(dispatch_get_main_queue(), ^{
		@synchronized (s) { [s removeObject:self]; }
	});
}

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
	self = [super init];

	if (self) {
		_action = action;
		_showProgress = showProgress;
		self.downloadManager = [[RYGDownloadManager alloc] initWithDelegate:self];
	}

	return self;
}

- (NSArray<NSString *> *)rygDuplicateKeysForURL:(NSURL *)url extension:(NSString *)ext {
	RYGGallerySaveMetadata *gm = [self.pendingGallerySaveMetadata isKindOfClass:[RYGGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata : nil;
	RYGDownloadMediaKind kind = RYGDownloadMediaKindForExtension(ext);
	return [RYGDownloadLedger keysForURL:url
	                             mediaPK:(gm.skipDedup ? nil : gm.sourceMediaPK)
	                             variant:[RYGDownloadLedger variantForMediaKind:kind]];
}

- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
	NSArray<NSString *> *keys = [self rygDuplicateKeysForURL:url extension:fileExtension];
	void (^begin)(void) = ^{ [self rygBeginDownloadWithURL:url fileExtension:fileExtension hudLabel:hudLabel keys:keys]; };

	if (self.skipDuplicateCheck) { begin(); return; }
	[RYGDownloadLedger guardKeys:keys proceed:begin];
}

- (void)rygBeginDownloadWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel keys:(NSArray<NSString *> *)keys {
	__weak typeof(self) weakSelf = self;

	[self rygPin];

	// Capture inputs so a failed/finished job can be rebuilt from scratch.
	NSString *ext = fileExtension;
	NSString *label = hudLabel ?: RYGLocalized(@"Downloading…");
	DownloadAction act = self.action;
	BOOL prog = self.showProgress;
	id meta = self.pendingGallerySaveMetadata;

	NSString *subtitle = nil;
	NSString *jobTitle = rygJobTitle(meta, ext, &subtitle);

	RYGDownloadJob *job = [[RYGDownloadCenter shared] enqueueJobWithTitle:jobTitle
	                                                                kind:RYGDownloadJobKindSimpleURL
	                                                               start:^{
		[weakSelf.downloadManager downloadFileWithURL:url fileExtension:ext];
	}
	                                                              cancel:^{
		[weakSelf.downloadManager cancelDownload];
	}];
	job.subtitle = subtitle;
	job.mediaKind = RYGDownloadMediaKindForExtension(ext);
	job.duplicateKeys = keys;
	job.retryBlock = ^{
		RYGDownloadDelegate *fresh = [[RYGDownloadDelegate alloc] initWithAction:act showProgress:prog];
		fresh.pendingGallerySaveMetadata = meta;
		fresh.skipDuplicateCheck = YES;
		[fresh downloadFileWithURL:url fileExtension:ext hudLabel:label];
	};
	job.retryInfo = rygURLRetryInfo(url, ext, label, act, prog, meta);
	self.job = job;
}

// Already-on-disk file (e.g. cached media): no network step, just run the save
// through a center job so it surfaces in the pill + manager like any download.
- (void)saveLocalFileURL:(NSURL *)fileURL hudLabel:(NSString *)hudLabel {
	// A scratch path is unique every time, so identity comes from the origin media.
	RYGGallerySaveMetadata *gm = [self.pendingGallerySaveMetadata isKindOfClass:[RYGGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata : nil;
	NSURL *originURL = gm.sourceMediaURLString.length ? [NSURL URLWithString:gm.sourceMediaURLString] : nil;
	NSArray<NSString *> *keys = originURL ? [self rygDuplicateKeysForURL:originURL extension:fileURL.pathExtension] : @[];

	void (^begin)(void) = ^{ [self rygBeginLocalSaveWithFileURL:fileURL hudLabel:hudLabel keys:keys]; };
	if (self.skipDuplicateCheck) { begin(); return; }
	[RYGDownloadLedger guardKeys:keys proceed:begin];
}

- (void)rygBeginLocalSaveWithFileURL:(NSURL *)fileURL hudLabel:(NSString *)hudLabel keys:(NSArray<NSString *> *)keys {
	(void)hudLabel;
	__weak typeof(self) weakSelf = self;
	[self rygPin];

	NSString *subtitle = nil;
	NSString *jobTitle = rygJobTitle(self.pendingGallerySaveMetadata, fileURL.pathExtension, &subtitle);

	RYGDownloadJob *job = [[RYGDownloadCenter shared] enqueueJobWithTitle:jobTitle
	                                                                kind:RYGDownloadJobKindSimpleURL
	                                                               start:^{
		[weakSelf downloadDidFinishWithFileURL:fileURL];
	}
	                                                              cancel:nil];
	job.subtitle = subtitle;
	job.mediaKind = RYGDownloadMediaKindForExtension(fileURL.pathExtension);
	job.duplicateKeys = keys;
	self.job = job;
}

- (void)downloadDidStart {
}

- (void)downloadDidCancel {
	[[RYGDownloadCenter shared] markJobCancelled:self.job];
	[self rygUnpin];
}

- (void)downloadDidProgress:(float)progress {
	[self downloadDidProgress:progress received:0 total:0];
}

- (void)downloadDidProgress:(float)progress received:(int64_t)received total:(int64_t)total {
	float safeProgress = RYGClamp(progress);
	NSString *text = [NSString stringWithFormat:RYGLocalized(@"Downloading %d%%"), (int)(safeProgress * 100.0f)];
	[[RYGDownloadCenter shared] job:self.job didProgress:safeProgress received:received total:total stage:text];
}

- (void)downloadDidFinishWithError:(NSError *)error {
	if (!error || error.code == NSURLErrorCancelled) {
		[self rygUnpin];
		return;
	}

	NSLog(@"[RyukGram] Download: Download failed with error: \"%@\"", error);

	[[RYGDownloadCenter shared] markJob:self.job failedWithError:error];
	[self rygUnpin];
}

- (void)downloadDidFinishWithFileURL:(NSURL *)inputFileURL {
	NSURL *fileURL = [RYGUtils photoSafeImageFileURL:inputFileURL];
	dispatch_async(dispatch_get_main_queue(), ^{
		self.job.resultFileURL = fileURL;

		NSString *galleryMode = [RYGUtils getStringPref:@"gallery_save_mode"];
		BOOL isAudio = RYGGalleryExtensionIsAudio(fileURL.pathExtension);

		switch (self.action) {
			case share:
				self.job.successText = RYGLocalized(@"Done");
				[RYGUtils showShareVC:[self rygShareReadyURL:fileURL]];
				if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
					[self logFileToGalleryQuiet:fileURL];
				}
				[[RYGDownloadCenter shared] markJobFinished:self.job];
				break;

			case quickLook:
				self.job.successText = RYGLocalized(@"Done");
				[RYGUtils showQuickLookVC:@[fileURL]];
				[[RYGDownloadCenter shared] markJobFinished:self.job];
				break;

			case saveToPhotos:
				// Photos library rejects audio — fall back to gallery / share.
				if (isAudio) {
					if ([galleryMode isEqualToString:@"off"] || galleryMode.length == 0) {
						self.job.successText = RYGLocalized(@"Done");
						[[RYGDownloadCenter shared] markJobFinished:self.job];
						[RYGUtils showShareVC:fileURL];
					} else {
						[self saveFileToGallery:fileURL];
					}
					break;
				}
				if ([galleryMode isEqualToString:@"gallery_only"]) {
					[self saveFileToGallery:fileURL];
				} else {
					// Mirror first: the Photos save can move the file out from under it.
					if ([galleryMode isEqualToString:@"mirror"] && self.pendingGallerySaveMetadata) {
						[self logFileToGalleryQuiet:fileURL];
					}
					[self saveFileToPhotos:fileURL];
				}
				break;

			case saveToGallery:
				[self saveFileToGallery:fileURL];
				break;
		}
		[self rygUnpin];
	});
}

- (void)saveFileToGallery:(NSURL *)fileURL {
	NSError *err = nil;
	RYGGalleryFile *file = [self saveFileURL:fileURL toGalleryWithError:&err];
	if (file && !err) {
		[self.job noteGalleryFileID:file.identifier];
		self.job.successText = RYGLocalized(@"Saved to Gallery");
		[[RYGDownloadCenter shared] markJobFinished:self.job];
	} else {
		NSLog(@"[RyukGram] Gallery save failed: %@", err);
		[[RYGDownloadCenter shared] markJob:self.job failedWithError:err];
	}
}

// Mirror mode: fire-and-forget gallery log alongside the Photos save.
- (void)logFileToGalleryQuiet:(NSURL *)fileURL {
	NSError *err = nil;
	RYGGalleryFile *file = [self saveFileURL:fileURL toGalleryWithError:&err];
	[self.job noteGalleryFileID:file.identifier];
	if (err) NSLog(@"[RyukGram] Gallery mirror log failed: %@", err);
}

// Copies (not moves) so share/Photos flow can still use the source file.
- (RYGGalleryFile *)saveFileURL:(NSURL *)fileURL toGalleryWithError:(NSError **)error {
	RYGGalleryMediaType mediaType = RYGGalleryMediaTypeForExtension(fileURL.pathExtension);
	RYGGallerySaveMetadata *metadata = [self rygMetadata];
	RYGGallerySource source = metadata ? (RYGGallerySource)metadata.source : RYGGallerySourceOther;
	return [RYGGalleryFile saveFileToGallery:fileURL
	                                  source:source
	                               mediaType:mediaType
	                              folderPath:nil
	                                metadata:metadata
	                                   error:error];
}
- (RYGGallerySaveMetadata *)rygMetadata {
	return [self.pendingGallerySaveMetadata isKindOfClass:[RYGGallerySaveMetadata class]]
		? self.pendingGallerySaveMetadata : nil;
}

- (NSString *)rygCleanFilenameForURL:(NSURL *)fileURL {
	return [RYGFileName exportNameForURL:fileURL metadata:[self rygMetadata]];
}

- (NSString *)rygFilenameStem {
	return [RYGFileName stemForMetadata:[self rygMetadata]];
}

// Scratch files get a clean-named hardlink for share (no data copy); clean names pass through.
- (NSURL *)rygShareReadyURL:(NSURL *)fileURL {
	NSString *name = fileURL.lastPathComponent;
	if (![name hasPrefix:@"ryuk_tmp_"] && ![name hasPrefix:@"ryg_tmp_"]) return fileURL;
	NSURL *dst = [RYGTempFiles claimNamedFile:[self rygCleanFilenameForURL:fileURL] ttl:600 tag:@"share"];
	NSFileManager *fm = NSFileManager.defaultManager;
	if ([fm linkItemAtURL:fileURL toURL:dst error:nil] || [fm copyItemAtURL:fileURL toURL:dst error:nil]) return dst;
	[RYGTempFiles releaseURL:dst];
	return fileURL;
}

- (void)saveFileToPhotos:(NSURL *)fileURL {
	NSString *cleanName = [self rygCleanFilenameForURL:fileURL];
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Photo library access denied")];
				[[RYGDownloadCenter shared] markJob:self.job failedWithError:nil];
			});

			return;
		}
		BOOL useAlbum = [RYGUtils getBoolPref:@"save_to_ryukgram_album"];
		void (^done)(BOOL, NSError *) = ^(BOOL success, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					self.job.successText = useAlbum ? RYGLocalized(@"Saved to RyukGram") : RYGLocalized(@"Saved to Photos");
					[[RYGDownloadCenter shared] markJobFinished:self.job];
				} else {
					NSLog(@"[RyukGram] Download: Save to Photos failed: %@", error);
					[[RYGDownloadCenter shared] markJob:self.job failedWithError:error];
				}
			});
		};
		if (useAlbum) {
			[RYGPhotoAlbum saveFileToAlbum:fileURL originalFilename:cleanName completion:done];
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
