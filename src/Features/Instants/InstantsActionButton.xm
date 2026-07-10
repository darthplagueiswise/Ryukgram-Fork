// Instants action button on the consumption header — Expand / Save / Gallery /
// Share / bulk, plus auto-save. Handles photo and video instants. Actions wired
// through SCIActionMenuConfig (source = Instants) for reorder/hide/default-tap.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import "../../Downloader/Manager.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../ActionButton/SCIActionCatalog.h"

static char kSCIInstantsDLBtnKey;
static char kSCIInstantsDLHitKey;
static char kSCIInstantsDLTargetKey;
static char kSCIInstantsDLWireKey;
static NSInteger sciInstantsConfigVersion;

typedef NS_ENUM(NSInteger, SCIInstantTarget) {
	SCIInstantTargetPhotos = 0,
	SCIInstantTargetGallery,
	SCIInstantTargetShare,
};

typedef struct {
	NSString *username;
	NSString *userPK;
	NSString *mediaPK;
} SCIInstantContext;

static UIImageView *sciFindIGImageViewIn(UIView *root);
static NSURL *sciIGImageViewURL(UIImageView *iv);
static BOOL sciSnapIsVideo(UIView *snap);

#pragma mark - Header / view helpers

static UIView *sciIvarView(id obj, const char *name) {
	Ivar ivar = class_getInstanceVariable([obj class], name);
	id value = ivar ? object_getIvar(obj, ivar) : nil;
	return [value isKindOfClass:UIView.class] ? value : nil;
}

static BOOL sciVisibleView(UIView *view) {
	return view && !view.hidden && view.alpha > 0.01 && !CGRectIsEmpty(view.frame);
}

static UIView *sciInstantsHeaderAnchor(UIView *header) {
	UIView *archive = sciIvarView(header, "archiveButton");
	if (sciVisibleView(archive)) return archive;

	UIView *consumption = sciIvarView(header, "consumptionButtonView");
	if (sciVisibleView(consumption)) return consumption;

	return nil;
}

#pragma mark - Snap discovery

static NSArray<UIView *> *sciAllSnapViewsIn(UIWindow *window) {
	if (!window) return @[];

	NSMutableArray<UIView *> *out = [NSMutableArray array];
	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];

	while (queue.count) {
		UIView *view = queue.firstObject;
		[queue removeObjectAtIndex:0];

		if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
			[out addObject:view];
		}

		for (UIView *subview in view.subviews) {
			[queue addObject:subview];
		}
	}

	return out;
}

static BOOL sciSnapIsUsable(UIView *snap) {
	if (!snap || snap.hidden || snap.alpha < 0.5) return NO;

	CGAffineTransform t = snap.transform;
	CGFloat rotated = fabs(t.a - 1.0) + fabs(t.b) + fabs(t.c) + fabs(t.d - 1.0);
	if (rotated > 0.1) return NO;

	if (sciSnapIsVideo(snap)) return YES;

	UIImageView *iv = sciFindIGImageViewIn(snap);
	return iv && (iv.image || sciIGImageViewURL(iv));
}

static BOOL sciInstantsHasVisibleSnap(UIView *header) {
	for (UIView *snap in sciAllSnapViewsIn(header.window)) {
		if (sciSnapIsUsable(snap)) return YES;
	}

	return NO;
}

static UIView *sciActiveSnapInWindow(UIWindow *window) {
	UIView *best = nil;
	NSUInteger bestIndex = 0;

	for (UIView *snap in sciAllSnapViewsIn(window)) {
		if (!sciSnapIsUsable(snap)) continue;

		NSUInteger index = snap.superview ? [snap.superview.subviews indexOfObject:snap] : 0;
		if (!best || index >= bestIndex) {
			best = snap;
			bestIndex = index;
		}
	}

	return best;
}

static UIView *sciActiveSnapView(UIView *fromView) {
	return sciActiveSnapInWindow(fromView.window);
}

#pragma mark - Context

static UIView *sciConsumptionVCView(UIView *fromView) {
	for (UIView *view = fromView; view; view = view.superview) {
		UIResponder *responder = view.nextResponder;
		if (![responder isKindOfClass:UIViewController.class]) continue;

		if ([NSStringFromClass(responder.class) containsString:@"QuickSnap"]) {
			return ((UIViewController *)responder).view;
		}
	}

	return nil;
}

static NSString *sciScrapeUsernameForSnap(UIView *snap) {
	UIView *root = sciConsumptionVCView(snap) ?: snap.window;
	if (!root) return nil;

	static NSRegularExpression *regex;
	static NSRegularExpression *timeRegex;
	static NSSet<NSString *> *skip;
	static NSCharacterSet *seps;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"^@?[a-z0-9](?:[a-z0-9._]{0,28}[a-z0-9])?$" options:0 error:nil];
		timeRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d+(s|m|h|d|w|mo|y)$" options:0 error:nil];
		skip = [NSSet setWithArray:@[@"now", @"just now", @"send", @"reply", @"share"]];
		seps = [NSCharacterSet characterSetWithCharactersInString:@"·•|—–-"];
	});

	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];

	while (queue.count) {
		UIView *view = queue.firstObject;
		[queue removeObjectAtIndex:0];

		if (view.hidden || view.alpha < 0.1) continue;

		if ([view isKindOfClass:UILabel.class]) {
			NSString *text = [((UILabel *)view).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

			if (text.length && text.length <= 31) {
				NSRange sep = [text rangeOfCharacterFromSet:seps];
				if (sep.location != NSNotFound) {
					text = [[text substringToIndex:sep.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
				}

				if ([text hasPrefix:@"@"]) text = [text substringFromIndex:1];

				NSString *lower = text.lowercaseString;
				BOOL isTime = [timeRegex numberOfMatchesInString:lower options:0 range:NSMakeRange(0, lower.length)] > 0;
				if (!isTime && ![skip containsObject:lower] &&
					[regex numberOfMatchesInString:lower options:0 range:NSMakeRange(0, lower.length)] > 0) {
					return text;
				}
			}
		}

		for (UIView *subview in view.subviews) {
			[queue addObject:subview];
		}
	}

	return nil;
}

static SCIInstantContext sciContextForSnap(UIView *snap) {
	SCIInstantContext ctx = {0};
	ctx.username = sciScrapeUsernameForSnap(snap);
	return ctx;
}

static NSString *sciInstantHudLabel(SCIInstantContext ctx) {
	return ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : SCILocalized(@"Instant");
}

static SCIGallerySaveMetadata *sciInstantMetadata(SCIInstantContext ctx, BOOL bulk) {
	SCIGallerySaveMetadata *metadata = [SCIGallerySaveMetadata new];
	metadata.source = SCIGallerySourceInstants;
	metadata.sourceUsername = ctx.username;
	metadata.sourceUserPK = ctx.userPK;
	metadata.sourceMediaPK = ctx.mediaPK;
	metadata.skipDedup = bulk;
	return metadata;
}

#pragma mark - Media discovery

static UIImageView *sciFindIGImageViewIn(UIView *root) {
	if (!root) return nil;

	Class igImageView = NSClassFromString(@"IGImageView");
	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
	UIImageView *fallback = nil;

	while (queue.count) {
		UIView *view = queue.firstObject;
		[queue removeObjectAtIndex:0];

		if (view.hidden || view.alpha < 0.05) continue;

		if (view.bounds.size.width < 8.0 || view.bounds.size.height < 8.0) {
			for (UIView *subview in view.subviews) {
				[queue addObject:subview];
			}
			continue;
		}

		BOOL imageView = (igImageView && [view isKindOfClass:igImageView]) || [view isKindOfClass:UIImageView.class];
		if (imageView) {
			UIImageView *iv = (UIImageView *)view;
			if (iv.image || sciIGImageViewURL(iv)) return iv;
			if (!fallback) fallback = iv;
		}

		for (UIView *subview in view.subviews) {
			[queue addObject:subview];
		}
	}

	return fallback;
}

static NSURL *sciIGImageViewURL(UIImageView *iv) {
	if (!iv) return nil;

	id spec = nil;
	@try { spec = [iv valueForKey:@"imageSpecifier"]; } @catch (__unused id e) {}
	if (!spec) return nil;

	id url = nil;
	@try { url = [spec valueForKey:@"url"]; } @catch (__unused id e) {}

	return [url isKindOfClass:NSURL.class] ? url : nil;
}

#pragma mark - Video discovery

static id sciSnapIvarObject(UIView *snap, const char *name) {
	Ivar iv = snap ? class_getInstanceVariable([snap class], name) : NULL;
	return iv ? object_getIvar(snap, iv) : nil;
}

static IGAssetPlayerView *sciSnapVideoView(UIView *snap) {
	id v = sciSnapIvarObject(snap, "videoView");
	return [v isKindOfClass:NSClassFromString(@"IGAssetPlayerView")] ? v : nil;
}

static BOOL sciSnapIsVideo(UIView *snap) {
	return sciSnapVideoView(snap) != nil;
}

static AVAsset *sciAssetFromPlayerView(IGAssetPlayerView *videoView) {
	if (!videoView) return nil;

	AVAsset *asset = nil;
	@try { asset = videoView.asset; } @catch (__unused id e) {}
	if ([asset isKindOfClass:AVAsset.class]) return asset;

	AVPlayerItem *item = sciSnapIvarObject(videoView, "_currentItem");
	if ([item isKindOfClass:AVPlayerItem.class] && [item.asset isKindOfClass:AVAsset.class]) return item.asset;

	AVPlayer *player = sciSnapIvarObject(videoView, "_player");
	if ([player isKindOfClass:AVPlayer.class] && [player.currentItem.asset isKindOfClass:AVAsset.class]) return player.currentItem.asset;

	return nil;
}

static NSURL *sciVideoURLFromAsset(AVAsset *asset) {
	if ([asset isKindOfClass:AVURLAsset.class]) return ((AVURLAsset *)asset).URL;
	return nil;
}


#pragma mark - Save / share

static DownloadAction sciDLActionForTarget(SCIInstantTarget target) {
	switch (target) {
		case SCIInstantTargetPhotos: return saveToPhotos;
		case SCIInstantTargetGallery: return saveToGallery;
		case SCIInstantTargetShare: return share;
	}
}

static NSString *sciInstantFilenameTag(SCIInstantContext ctx) {
	if (!ctx.username.length) return @"instant";

	NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
	NSString *username = [[ctx.username componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@""];

	if (username.length > 30) username = [username substringToIndex:30];
	return username.length ? [NSString stringWithFormat:@"instant-@%@", username] : @"instant";
}

static void sciSaveImageViaDelegate(UIImage *image, SCIInstantTarget target, SCIInstantContext ctx, BOOL bulk) {
	if (!image) {
		SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"), SCILocalized(@"Nothing to save"));
		return;
	}

	NSData *jpg = UIImageJPEGRepresentation(image, 1.0);
	if (!jpg) {
		SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"), SCILocalized(@"Failed to save"));
		return;
	}

	NSURL *tmp = [SCITempFiles claimWithExt:@"jpg" ttl:600 tag:sciInstantFilenameTag(ctx)];
	NSError *error = nil;

	if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:&error]) {
		[SCITempFiles releaseURL:tmp];
		SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"), error.localizedDescription ?: SCILocalized(@"Failed to save"));
		return;
	}

	SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:NO];
	delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
	[delegate saveLocalFileURL:tmp hudLabel:sciInstantHudLabel(ctx)];
}

static void sciExportAssetThenSave(AVAsset *asset, SCIInstantTarget target, SCIInstantContext ctx, BOOL bulk) {
	NSURL *out = [SCITempFiles claimWithExt:@"mp4" ttl:600 tag:sciInstantFilenameTag(ctx)];

	AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
	session.outputURL = out;
	session.outputFileType = AVFileTypeMPEG4;
	session.shouldOptimizeForNetworkUse = YES;

	SCINotificationHandle *hud = SCINotifyProgress(SCI_NOTIF_DOWNLOAD, sciInstantHudLabel(ctx), nil);

	[session exportAsynchronouslyWithCompletionHandler:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			if (session.status != AVAssetExportSessionStatusCompleted) {
				NSLog(@"[SCInsta][InstantsVideo] export failed status=%ld err=%@", (long)session.status, session.error);
				[SCITempFiles releaseURL:out];
				[hud error:SCILocalized(@"Failed to save")];
				return;
			}
			[hud dismiss];
			SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:NO];
			delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
			[delegate saveLocalFileURL:out hudLabel:sciInstantHudLabel(ctx)];
		});
	}];
}

static BOOL sciSaveVideoSnap(UIView *snap, SCIInstantTarget target, BOOL bulk) {
	IGAssetPlayerView *videoView = sciSnapVideoView(snap);
	if (!videoView) return NO;

	AVAsset *asset = sciAssetFromPlayerView(videoView);
	if (!asset) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"No media available to save"));
		return YES;
	}

	SCIInstantContext ctx = sciContextForSnap(snap);
	NSURL *url = sciVideoURLFromAsset(asset);

	if (url && url.isFileURL) {
		NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"mp4";
		NSURL *copy = [SCITempFiles claimWithExt:ext ttl:600 tag:sciInstantFilenameTag(ctx)];
		NSError *copyErr = nil;
		[NSFileManager.defaultManager removeItemAtURL:copy error:nil];
		if (![NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:&copyErr]) {
			NSLog(@"[SCInsta][InstantsVideo] cache copy failed %@ -> %@ err=%@", url, copy, copyErr);
			[SCITempFiles releaseURL:copy];
			sciExportAssetThenSave(asset, target, ctx, bulk);
			return YES;
		}
		SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:NO];
		delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
		[delegate saveLocalFileURL:copy hudLabel:sciInstantHudLabel(ctx)];
		return YES;
	}

	if (url) {
		SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:YES];
		delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
		[delegate downloadFileWithURL:url fileExtension:@"mp4" hudLabel:sciInstantHudLabel(ctx)];
		return YES;
	}

	sciExportAssetThenSave(asset, target, ctx, bulk);
	return YES;
}

static void sciSaveSnapView(UIView *snap, SCIInstantTarget target, BOOL bulk) {
	if (!snap) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"Could not locate the instant on screen"));
		return;
	}

	if (sciSaveVideoSnap(snap, target, bulk)) return;

	SCIInstantContext ctx = sciContextForSnap(snap);
	UIImageView *iv = sciFindIGImageViewIn(snap);

	if (iv.image) {
		sciSaveImageViaDelegate(iv.image, target, ctx, bulk);
		return;
	}

	NSURL *url = sciIGImageViewURL(iv);
	if (url) {
		NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"jpg";
		SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:YES];
		delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
		[delegate downloadFileWithURL:url fileExtension:ext hudLabel:sciInstantHudLabel(ctx)];
		return;
	}

	SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"No media available to save"));
}

static void sciSaveAllInstants(UIView *fromView, SCIInstantTarget target) {
	NSUInteger queued = 0;

	for (UIView *snap in sciAllSnapViewsIn(fromView.window)) {
		if (!sciSnapIsVideo(snap)) {
			UIImageView *iv = sciFindIGImageViewIn(snap);
			if (!iv || (!iv.image && !sciIGImageViewURL(iv))) continue;
		}

		sciSaveSnapView(snap, target, YES);
		queued++;
	}

	if (!queued) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD_BULK, SCILocalized(@"Download failed"), SCILocalized(@"No instants currently loaded"));
		return;
	}

	SCINotifyInfo(SCI_NOTIF_DOWNLOAD_BULK, [NSString stringWithFormat:SCILocalized(@"Queued %lu instants"), (unsigned long)queued], nil);
}

#pragma mark - Auto-save

static char kSCIInstantsImageHashKey;
static NSTimer *sciAutoSaveTimer;

static NSString *sciAutoSaveStorePath(void) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [root stringByAppendingPathComponent:@"RyukGram/InstantsAutoSave"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:@"saved.json"];
}

// Already-saved keys: CDN URL path (query is an expiring signature), or an
// image-bytes hash when no specifier URL exists.
static NSMutableOrderedSet<NSString *> *sciAutoSaveSeen(void) {
	static NSMutableOrderedSet *seen;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		NSData *data = [NSData dataWithContentsOfFile:sciAutoSaveStorePath()];
		NSArray *keys = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		seen = [NSMutableOrderedSet orderedSetWithArray:[keys isKindOfClass:NSArray.class] ? keys : @[]];
	});

	return seen;
}

static void sciAutoSavePersist(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.ryukgram.instants.autosave", DISPATCH_QUEUE_SERIAL); });

	NSMutableOrderedSet *seen = sciAutoSaveSeen();
	while (seen.count > 1000) [seen removeObjectAtIndex:0];

	NSData *data = [NSJSONSerialization dataWithJSONObject:seen.array options:0 error:nil];
	NSString *path = sciAutoSaveStorePath();
	dispatch_async(queue, ^{ [data writeToFile:path atomically:YES]; });
}

static NSString *sciAutoSaveKey(UIImageView *iv, NSURL *url) {
	if (url.path.length) return url.path;

	UIImage *image = iv.image;
	if (!image) return nil;

	NSString *cached = objc_getAssociatedObject(image, &kSCIInstantsImageHashKey);
	if (cached) return cached;

	NSData *jpg = UIImageJPEGRepresentation(image, 0.9);
	if (!jpg) return nil;

	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(jpg.bytes, (CC_LONG)jpg.length, digest);

	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];

	objc_setAssociatedObject(image, &kSCIInstantsImageHashKey, hex, OBJC_ASSOCIATION_COPY_NONATOMIC);
	return hex;
}

static UIWindow *sciWindowWithSnaps(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (sciAllSnapViewsIn(window).count) return window;
		}
	}

	return nil;
}

static void sciAutoSaveStopTimer(void) {
	[sciAutoSaveTimer invalidate];
	sciAutoSaveTimer = nil;
}

static void sciAutoSaveTick(void) {
	NSString *mode = [SCIUtils getStringPref:@"instants_auto_save"];
	BOOL on = [mode isEqualToString:@"photos"] || [mode isEqualToString:@"gallery"];

	UIWindow *window = on ? sciWindowWithSnaps() : nil;
	if (!window) {
		sciAutoSaveStopTimer();
		return;
	}

	UIView *snap = sciActiveSnapInWindow(window);
	if (!snap) return;

	BOOL gallery = [mode isEqualToString:@"gallery"] && [SCIUtils getBoolPref:@"sci_gallery_enabled"];
	SCIInstantTarget target = gallery ? SCIInstantTargetGallery : SCIInstantTargetPhotos;

	if (sciSnapIsVideo(snap)) {
		AVAsset *asset = sciAssetFromPlayerView(sciSnapVideoView(snap));
		NSURL *videoURL = sciVideoURLFromAsset(asset);
		NSString *key = videoURL.path.length ? videoURL.path : nil;
		if (!asset || !key || [sciAutoSaveSeen() containsObject:key]) return;

		[sciAutoSaveSeen() addObject:key];
		sciAutoSavePersist();
		sciSaveVideoSnap(snap, target, NO);
		return;
	}

	UIImageView *iv = sciFindIGImageViewIn(snap);
	NSURL *url = sciIGImageViewURL(iv);
	if (!iv || (!iv.image && !url)) return;

	NSString *key = sciAutoSaveKey(iv, url);
	if (!key || [sciAutoSaveSeen() containsObject:key]) return;

	[sciAutoSaveSeen() addObject:key];
	sciAutoSavePersist();

	SCIInstantContext ctx = sciContextForSnap(snap);

	if (iv.image) {
		sciSaveImageViaDelegate(iv.image, target, ctx, NO);
		return;
	}

	NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"jpg";
	SCIDownloadDelegate *delegate = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target) showProgress:NO];
	delegate.pendingGallerySaveMetadata = sciInstantMetadata(ctx, NO);
	[delegate downloadFileWithURL:url fileExtension:ext hudLabel:sciInstantHudLabel(ctx)];
}

// Specifiers resolve async and swipes don't reliably trigger layout — poll
// while the viewer is up; the tick self-stops once no snap views remain.
static void sciAutoSaveEnsureTimer(void) {
	NSString *mode = [SCIUtils getStringPref:@"instants_auto_save"];
	if (![mode isEqualToString:@"photos"] && ![mode isEqualToString:@"gallery"]) return;
	if (sciAutoSaveTimer) return;

	sciAutoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:YES block:^(__unused NSTimer *timer) {
		sciAutoSaveTick();
	}];
}

static void sciExpandSnapView(UIView *snap) {
	if (!snap) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"Could not locate the instant on screen"));
		return;
	}

	if (sciSnapIsVideo(snap)) {
		AVAsset *asset = sciAssetFromPlayerView(sciSnapVideoView(snap));
		NSURL *url = sciVideoURLFromAsset(asset);
		if (url) {
			SCIInstantContext ctx = sciContextForSnap(snap);
			SCIMediaViewerItem *item = [SCIMediaViewerItem itemWithVideoURL:url
																   photoURL:nil
																	caption:ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : nil];
			item.metadata = sciInstantMetadata(ctx, NO);
			[SCIMediaViewer showItem:item];
			return;
		}
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"No media available to save"));
		return;
	}

	UIImageView *iv = sciFindIGImageViewIn(snap);
	UIImage *image = iv.image;

	if (!image) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"No media available to save"));
		return;
	}

	NSData *jpg = UIImageJPEGRepresentation(image, 1.0);
	if (!jpg) {
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"Failed to save"));
		return;
	}

	NSURL *tmp = [SCITempFiles claimWithExt:@"jpg" ttl:900 tag:@"instant-expand"];
	if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:nil]) {
		[SCITempFiles releaseURL:tmp];
		SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"), SCILocalized(@"Failed to save"));
		return;
	}

	SCIInstantContext ctx = sciContextForSnap(snap);
	SCIMediaViewerItem *item = [SCIMediaViewerItem itemWithVideoURL:nil
														   photoURL:tmp
															caption:ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : nil];
	item.metadata = sciInstantMetadata(ctx, NO);

	[SCIMediaViewer showItem:item];
}

#pragma mark - Action menu

static SCIAction *sciInstantsAction(NSString *title, NSString *icon, __weak UIView *headerRef, void (^block)(UIView *header)) {
	return [SCIAction actionWithTitle:title icon:icon handler:^{
		UIView *header = headerRef;
		if (header && block) block(header);
	}];
}

static SCIAction *sciInstantsLeafForAID(NSString *aid, __weak UIView *headerRef) {
	SCIActionDescriptor *desc = [SCIActionCatalog descriptorForActionID:aid source:SCIActionSourceInstants];
	if (!desc) return nil;

	if ([aid isEqualToString:SCIAID_Expand]) {
		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciExpandSnapView(sciActiveSnapView(header));
		});
	}

	if ([aid isEqualToString:SCIAID_DownloadSave]) {
		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciSaveSnapView(sciActiveSnapView(header), SCIInstantTargetPhotos, NO);
		});
	}

	if ([aid isEqualToString:SCIAID_DownloadGallery]) {
		if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;

		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciSaveSnapView(sciActiveSnapView(header), SCIInstantTargetGallery, NO);
		});
	}

	if ([aid isEqualToString:SCIAID_DownloadShare]) {
		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciSaveSnapView(sciActiveSnapView(header), SCIInstantTargetShare, NO);
		});
	}

	if ([aid isEqualToString:SCIAID_BulkDownloadSave]) {
		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciSaveAllInstants(header, SCIInstantTargetPhotos);
		});
	}

	if ([aid isEqualToString:SCIAID_BulkDownloadGallery]) {
		if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;

		return sciInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			sciSaveAllInstants(header, SCIInstantTargetGallery);
		});
	}

	return nil;
}

static UIMenu *sciInstantsBuildMenu(UIView *header) {
	if (!header) return [UIMenu menuWithTitle:@"" children:@[]];

	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
	__weak UIView *weakHeader = header;

	NSArray<SCIAction *> *actions = [SCIActionMenu actionsForConfig:cfg dateHeader:nil resolver:^SCIAction *(NSString *aid) {
		return sciInstantsLeafForAID(aid, weakHeader);
	}];

	NSUInteger count = sciAllSnapViewsIn(header.window).count;
	if (count > 1) {
		NSMutableArray<SCIAction *> *patched = actions.mutableCopy;

		for (NSUInteger i = 0; i < patched.count; i++) {
			SCIAction *group = patched[i];
			if (!group.children.count) continue;

			BOOL bulk = NO;
			for (SCIAction *child in group.children) {
				if ([child.actionID hasPrefix:@"bulk_"]) {
					bulk = YES;
					break;
				}
			}

			if (bulk) {
				NSString *title = [NSString stringWithFormat:SCILocalized(@"%@ (%lu)"), group.title, (unsigned long)count];
				patched[i] = [SCIAction actionWithTitle:title icon:group.systemIconName children:group.children];
				break;
			}
		}

		actions = patched;
	}

	return [SCIActionMenu buildMenuWithActions:actions];
}

static void sciInstantsExecuteDefaultTap(UIView *header) {
	if (!header) return;

	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";

	if ([tap isEqualToString:@"menu"]) return;

	SCIAction *action = sciInstantsLeafForAID(tap, header);
	if (action.handler) action.handler();
}

@interface SCIInstantsActionTarget : NSObject
+ (instancetype)shared;
- (void)tap:(UIButton *)sender;
@end

@implementation SCIInstantsActionTarget

+ (instancetype)shared {
	static SCIInstantsActionTarget *target;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ target = [SCIInstantsActionTarget new]; });
	return target;
}

- (void)tap:(UIButton *)sender {
	UIView *header = objc_getAssociatedObject(sender, &kSCIInstantsDLTargetKey);
	sciInstantsExecuteDefaultTap(header);
}

@end

#pragma mark - Button

static CGRect sciInstantsButtonFrame(UIView *anchor) {
	CGFloat side = 40.0;
	CGFloat gap = 8.0;

	return CGRectMake(CGRectGetMinX(anchor.frame) - side - gap,
					  CGRectGetMidY(anchor.frame) - side * 0.5,
					  side,
					  side);
}

// Fallback when both anchor ivars are hidden: pin to the header's trailing edge.
static CGRect sciInstantsFallbackFrame(UIView *header) {
	CGFloat side = 40.0;
	CGFloat margin = 12.0;
	CGRect b = header.bounds;

	return CGRectMake(CGRectGetMaxX(b) - side - margin,
					  CGRectGetMinY(b) + header.safeAreaInsets.top + margin,
					  side,
					  side);
}

static void sciInstantsRemoveButton(UIView *header) {
	SCIChromeButton *chrome = objc_getAssociatedObject(header, &kSCIInstantsDLBtnKey);
	UIButton *hit = objc_getAssociatedObject(header, &kSCIInstantsDLHitKey);

	[chrome removeFromSuperview];
	[hit removeFromSuperview];

	objc_setAssociatedObject(header, &kSCIInstantsDLBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, &kSCIInstantsDLHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, &kSCIInstantsDLWireKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void sciInstantsWireButton(UIButton *hit, UIView *header) {
	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	NSString *wireKey = [NSString stringWithFormat:@"%@|%ld", tap, (long)sciInstantsConfigVersion];

	objc_setAssociatedObject(hit, &kSCIInstantsDLTargetKey, header, OBJC_ASSOCIATION_ASSIGN);

	NSString *old = objc_getAssociatedObject(hit, &kSCIInstantsDLWireKey);
	if ([old isEqualToString:wireKey]) return;

	[hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	__weak UIView *weakHeader = header;
	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *elements)) {
		UIMenu *menu = sciInstantsBuildMenu(weakHeader);
		completion(menu.children ?: @[]);
	}];

	hit.menu = [UIMenu menuWithChildren:@[deferred]];

	if ([tap isEqualToString:@"menu"]) {
		hit.showsMenuAsPrimaryAction = YES;
	} else {
		hit.showsMenuAsPrimaryAction = NO;
		[hit addTarget:SCIInstantsActionTarget.shared action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
	}

	objc_setAssociatedObject(hit, &kSCIInstantsDLWireKey, wireKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Hook

%hook _TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) sciAutoSaveEnsureTimer();
}

%end

%hook _TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	UIButton *hit = objc_getAssociatedObject(self, &kSCIInstantsDLHitKey);

	if (hit && !hit.hidden && hit.alpha > 0.01) {
		CGPoint p = [hit convertPoint:point fromView:(UIView *)self];
		if ([hit pointInside:p withEvent:event]) return hit;
	}

	return %orig;
}

- (void)layoutSubviews {
	%orig;

	UIView *header = (UIView *)self;

	if (![SCIUtils getBoolPref:@"instants_download_btn"] || !sciInstantsHasVisibleSnap(header)) {
		sciInstantsRemoveButton(header);
		return;
	}

	UIView *anchor = sciInstantsHeaderAnchor(header);
	SCIChromeButton *chrome = objc_getAssociatedObject(header, &kSCIInstantsDLBtnKey);
	UIButton *hit = objc_getAssociatedObject(header, &kSCIInstantsDLHitKey);

	if (!chrome || !hit) {
		chrome = [[SCIChromeButton alloc] initWithSymbol:@"arrow.down" pointSize:18 diameter:40];
		chrome.bubbleColor = [UIColor colorWithWhite:0 alpha:0.45];
		chrome.iconTint = UIColor.whiteColor;
		chrome.userInteractionEnabled = NO;
		chrome.translatesAutoresizingMaskIntoConstraints = YES;
		[header addSubview:chrome];

		hit = [UIButton buttonWithType:UIButtonTypeCustom];
		hit.backgroundColor = UIColor.clearColor;
		hit.translatesAutoresizingMaskIntoConstraints = YES;
		[header addSubview:hit];

		objc_setAssociatedObject(header, &kSCIInstantsDLBtnKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(header, &kSCIInstantsDLHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	sciInstantsWireButton(hit, header);

	CGRect frame = anchor ? sciInstantsButtonFrame(anchor) : sciInstantsFallbackFrame(header);
	chrome.frame = frame;
	hit.frame = frame;

	chrome.hidden = NO;
	hit.hidden = NO;
	chrome.alpha = 1.0;
	hit.alpha = 1.0;

	[header bringSubviewToFront:chrome];
	[header bringSubviewToFront:hit];
}

%end

%ctor {
	[[NSNotificationCenter defaultCenter] addObserverForName:SCIActionMenuConfigDidChangeNotification
													  object:nil
													   queue:NSOperationQueue.mainQueue
												  usingBlock:^(__unused NSNotification *notification) {
		NSNumber *source = notification.userInfo[@"source"];
		if (source.integerValue == SCIActionSourceInstants) sciInstantsConfigVersion++;
	}];
}