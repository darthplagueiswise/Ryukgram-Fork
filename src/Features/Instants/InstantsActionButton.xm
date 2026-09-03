// Instants action button on the consumption header — Expand / Save / Gallery /
// Share / bulk, plus auto-save. Handles photo and video instants. Actions wired
// through RYGActionMenuConfig (source = Instants) for reorder/hide/default-tap.

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import "../../Downloader/Manager.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "../../RYGChrome.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../ActionButton/RYGActionMenu.h"
#import "../../ActionButton/RYGActionMenuConfig.h"
#import "../../ActionButton/RYGActionCatalog.h"
#import "../../ActionButton/RYGActionIcon.h"

static char kRYGInstantsDLBtnKey;
static char kRYGInstantsDLHitKey;
static char kRYGInstantsDLTargetKey;
static char kRYGInstantsDLWireKey;
static char kRYGInstantsCCBtnKey;
static char kRYGInstantsCCHitKey;
static NSInteger rygInstantsConfigVersion;

typedef NS_ENUM(NSInteger, RYGInstantTarget) {
	RYGInstantTargetPhotos = 0,
	RYGInstantTargetGallery,
	RYGInstantTargetShare,
};

typedef struct {
	NSString *username;
	NSString *userPK;
	NSString *mediaPK;
} RYGInstantContext;

static UIImageView *rygFindIGImageViewIn(UIView *root);
static NSURL *rygIGImageViewURL(UIImageView *iv);
static BOOL rygSnapIsVideo(UIView *snap);

#pragma mark - Header / view helpers

static UIView *rygIvarView(id obj, const char *name) {
	Ivar ivar = class_getInstanceVariable([obj class], name);
	id value = ivar ? object_getIvar(obj, ivar) : nil;
	return [value isKindOfClass:UIView.class] ? value : nil;
}

static BOOL rygVisibleView(UIView *view) {
	return view && !view.hidden && view.alpha > 0.01 && !CGRectIsEmpty(view.frame);
}

static UIView *rygInstantsHeaderAnchor(UIView *header) {
	UIView *archive = rygIvarView(header, "archiveButton");
	if (rygVisibleView(archive)) return archive;

	UIView *consumption = rygIvarView(header, "consumptionButtonView");
	if (rygVisibleView(consumption)) return consumption;

	return nil;
}

#pragma mark - Snap discovery

static NSArray<UIView *> *rygAllSnapViewsIn(UIWindow *window) {
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

static BOOL rygSnapIsUsable(UIView *snap) {
	if (!snap || snap.hidden || snap.alpha < 0.5) return NO;

	CGAffineTransform t = snap.transform;
	CGFloat rotated = fabs(t.a - 1.0) + fabs(t.b) + fabs(t.c) + fabs(t.d - 1.0);
	if (rotated > 0.1) return NO;

	if (rygSnapIsVideo(snap)) return YES;

	UIImageView *iv = rygFindIGImageViewIn(snap);
	return iv && (iv.image || rygIGImageViewURL(iv));
}

static BOOL rygInstantsHasVisibleSnap(UIView *header) {
	for (UIView *snap in rygAllSnapViewsIn(header.window)) {
		if (rygSnapIsUsable(snap)) return YES;
	}

	return NO;
}

static UIView *rygActiveSnapInWindow(UIWindow *window) {
	UIView *best = nil;
	NSUInteger bestIndex = 0;

	for (UIView *snap in rygAllSnapViewsIn(window)) {
		if (!rygSnapIsUsable(snap)) continue;

		NSUInteger index = snap.superview ? [snap.superview.subviews indexOfObject:snap] : 0;
		if (!best || index >= bestIndex) {
			best = snap;
			bestIndex = index;
		}
	}

	return best;
}

static UIView *rygActiveSnapView(UIView *fromView) {
	return rygActiveSnapInWindow(fromView.window);
}

#pragma mark - Context

static UIView *rygConsumptionVCView(UIView *fromView) {
	for (UIView *view = fromView; view; view = view.superview) {
		UIResponder *responder = view.nextResponder;
		if (![responder isKindOfClass:UIViewController.class]) continue;

		if ([NSStringFromClass(responder.class) containsString:@"QuickSnap"]) {
			return ((UIViewController *)responder).view;
		}
	}

	return nil;
}

static NSString *rygScrapeUsernameForSnap(UIView *snap) {
	UIView *root = rygConsumptionVCView(snap) ?: snap.window;
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

static NSString *rygStringViaSel(id obj, SEL sel) {
	if (!obj || ![obj respondsToSelector:sel]) return nil;
	id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
	id v = msg(obj, sel);
	return [v isKindOfClass:NSString.class] && [(NSString *)v length] ? v : nil;
}

static id rygIvarObj(id obj, const char *name) {
	if (!obj) return nil;
	Ivar iv = nil;
	for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
	return iv ? object_getIvar(obj, iv) : nil;
}

static NSString *rygIDString(id v) {
	if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
	if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
	return nil;
}

static id rygCallID(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

// The stack state keeps currentImages (snap views) and viewModel (their IGMedia) in
// parallel order; the header label only tracks the fronted reel. Match by index.
static id rygMediaForSnap(UIView *snap) {
	UIView *stack = snap.superview;
	while (stack && ![NSStringFromClass(stack.class) containsString:@"SnapStackView"]) stack = stack.superview;
	id state = rygIvarObj(stack, "state") ?: rygIvarObj(snap, "delegate");
	if (!state) return nil;

	id images = rygIvarObj(state, "currentImages");
	id model = rygIvarObj(state, "viewModel");
	if (![images isKindOfClass:NSArray.class] || ![model isKindOfClass:NSArray.class]) return nil;

	NSUInteger i = [(NSArray *)images indexOfObjectIdenticalTo:snap];
	if (i == NSNotFound || i >= [(NSArray *)model count]) return nil;
	return ((NSArray *)model)[i];
}

static void rygFillContextFromMedia(id media, RYGInstantContext *ctx) {
	if (!media) return;
	id user = rygCallID(media, @selector(user));
	ctx->username = rygStringViaSel(user, @selector(username));
	ctx->userPK = rygIDString(rygCallID(user, @selector(pk)));
	ctx->mediaPK = rygIDString(rygCallID(media, @selector(pk))) ?: rygIDString(rygCallID(media, @selector(mediaID)));
}

static RYGInstantContext rygContextForSnap(UIView *snap) {
	RYGInstantContext ctx = {0};
	id media = rygMediaForSnap(snap);
	rygFillContextFromMedia(media, &ctx);
	if (!ctx.username.length) ctx.username = rygScrapeUsernameForSnap(snap);
	return ctx;
}

static NSString *rygInstantHudLabel(RYGInstantContext ctx) {
	return ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : RYGLocalized(@"Instant");
}

static RYGGallerySaveMetadata *rygInstantMetadata(RYGInstantContext ctx, BOOL bulk) {
	RYGGallerySaveMetadata *metadata = [RYGGallerySaveMetadata new];
	metadata.source = RYGGallerySourceInstants;
	metadata.sourceUsername = ctx.username;
	metadata.sourceUserPK = ctx.userPK;
	metadata.sourceMediaPK = ctx.mediaPK;
	metadata.skipDedup = bulk;
	return metadata;
}

#pragma mark - Media discovery

static UIImageView *rygFindIGImageViewIn(UIView *root) {
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
			if (iv.image || rygIGImageViewURL(iv)) return iv;
			if (!fallback) fallback = iv;
		}

		for (UIView *subview in view.subviews) {
			[queue addObject:subview];
		}
	}

	return fallback;
}

static NSURL *rygIGImageViewURL(UIImageView *iv) {
	if (!iv) return nil;

	id spec = nil;
	@try { spec = [iv valueForKey:@"imageSpecifier"]; } @catch (__unused id e) {}
	if (!spec) return nil;

	id url = nil;
	@try { url = [spec valueForKey:@"url"]; } @catch (__unused id e) {}

	return [url isKindOfClass:NSURL.class] ? url : nil;
}

#pragma mark - Video discovery

static id rygSnapIvarObject(UIView *snap, const char *name) {
	Ivar iv = snap ? class_getInstanceVariable([snap class], name) : NULL;
	return iv ? object_getIvar(snap, iv) : nil;
}

static IGAssetPlayerView *rygSnapVideoView(UIView *snap) {
	id v = rygSnapIvarObject(snap, "videoView");
	return [v isKindOfClass:NSClassFromString(@"IGAssetPlayerView")] ? v : nil;
}

static BOOL rygSnapIsVideo(UIView *snap) {
	return rygSnapVideoView(snap) != nil;
}

static AVAsset *rygAssetFromPlayerView(IGAssetPlayerView *videoView) {
	if (!videoView) return nil;

	AVAsset *asset = nil;
	@try { asset = videoView.asset; } @catch (__unused id e) {}
	if ([asset isKindOfClass:AVAsset.class]) return asset;

	AVPlayerItem *item = rygSnapIvarObject(videoView, "_currentItem");
	if ([item isKindOfClass:AVPlayerItem.class] && [item.asset isKindOfClass:AVAsset.class]) return item.asset;

	AVPlayer *player = rygSnapIvarObject(videoView, "_player");
	if ([player isKindOfClass:AVPlayer.class] && [player.currentItem.asset isKindOfClass:AVAsset.class]) return player.currentItem.asset;

	return nil;
}

static NSURL *rygVideoURLFromAsset(AVAsset *asset) {
	if ([asset isKindOfClass:AVURLAsset.class]) return ((AVURLAsset *)asset).URL;
	return nil;
}


#pragma mark - Save / share

static DownloadAction rygDLActionForTarget(RYGInstantTarget target) {
	switch (target) {
		case RYGInstantTargetPhotos: return saveToPhotos;
		case RYGInstantTargetGallery: return saveToGallery;
		case RYGInstantTargetShare: return share;
	}
}

static NSString *rygInstantFilenameTag(RYGInstantContext ctx) {
	if (!ctx.username.length) return @"instant";

	NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
	NSString *username = [[ctx.username componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@""];

	if (username.length > 30) username = [username substringToIndex:30];
	return username.length ? [NSString stringWithFormat:@"instant-@%@", username] : @"instant";
}

static void rygSaveImageViaDelegate(UIImage *image, RYGInstantTarget target, RYGInstantContext ctx, BOOL bulk) {
	if (!image) {
		RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), RYGLocalized(@"Nothing to save"));
		return;
	}

	NSData *jpg = UIImageJPEGRepresentation(image, 1.0);
	if (!jpg) {
		RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), RYGLocalized(@"Failed to save"));
		return;
	}

	NSURL *tmp = [RYGTempFiles claimWithExt:@"jpg" ttl:600 tag:rygInstantFilenameTag(ctx)];
	NSError *error = nil;

	if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:&error]) {
		[RYGTempFiles releaseURL:tmp];
		RYGNotifyError(RYG_NOTIF_GALLERY_SAVE, RYGLocalized(@"Save failed"), error.localizedDescription ?: RYGLocalized(@"Failed to save"));
		return;
	}

	RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:NO];
	delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, bulk);
	[delegate saveLocalFileURL:tmp hudLabel:rygInstantHudLabel(ctx)];
}

static void rygExportAssetThenSave(AVAsset *asset, RYGInstantTarget target, RYGInstantContext ctx, BOOL bulk) {
	NSURL *out = [RYGTempFiles claimWithExt:@"mp4" ttl:600 tag:rygInstantFilenameTag(ctx)];

	AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
	session.outputURL = out;
	session.outputFileType = AVFileTypeMPEG4;
	session.shouldOptimizeForNetworkUse = YES;

	RYGNotificationHandle *hud = RYGNotifyProgress(RYG_NOTIF_DOWNLOAD, rygInstantHudLabel(ctx), nil);

	[session exportAsynchronouslyWithCompletionHandler:^{
		dispatch_async(dispatch_get_main_queue(), ^{
			if (session.status != AVAssetExportSessionStatusCompleted) {
				NSLog(@"[RyukGram][InstantsVideo] export failed status=%ld err=%@", (long)session.status, session.error);
				[RYGTempFiles releaseURL:out];
				[hud error:RYGLocalized(@"Failed to save")];
				return;
			}
			[hud dismiss];
			RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:NO];
			delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, bulk);
			[delegate saveLocalFileURL:out hudLabel:rygInstantHudLabel(ctx)];
		});
	}];
}

static BOOL rygSaveVideoSnap(UIView *snap, RYGInstantTarget target, BOOL bulk) {
	IGAssetPlayerView *videoView = rygSnapVideoView(snap);
	if (!videoView) return NO;

	AVAsset *asset = rygAssetFromPlayerView(videoView);
	if (!asset) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"No media available to save"));
		return YES;
	}

	RYGInstantContext ctx = rygContextForSnap(snap);
	NSURL *url = rygVideoURLFromAsset(asset);

	if (url && url.isFileURL) {
		NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"mp4";
		NSURL *copy = [RYGTempFiles claimWithExt:ext ttl:600 tag:rygInstantFilenameTag(ctx)];
		NSError *copyErr = nil;
		[NSFileManager.defaultManager removeItemAtURL:copy error:nil];
		if (![NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:&copyErr]) {
			NSLog(@"[RyukGram][InstantsVideo] cache copy failed %@ -> %@ err=%@", url, copy, copyErr);
			[RYGTempFiles releaseURL:copy];
			rygExportAssetThenSave(asset, target, ctx, bulk);
			return YES;
		}
		RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:NO];
		delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, bulk);
		[delegate saveLocalFileURL:copy hudLabel:rygInstantHudLabel(ctx)];
		return YES;
	}

	if (url) {
		RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:YES];
		delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, bulk);
		[delegate downloadFileWithURL:url fileExtension:@"mp4" hudLabel:rygInstantHudLabel(ctx)];
		return YES;
	}

	rygExportAssetThenSave(asset, target, ctx, bulk);
	return YES;
}

static void rygSaveSnapView(UIView *snap, RYGInstantTarget target, BOOL bulk) {
	if (!snap) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"Could not locate the instant on screen"));
		return;
	}

	if (rygSaveVideoSnap(snap, target, bulk)) return;

	RYGInstantContext ctx = rygContextForSnap(snap);
	UIImageView *iv = rygFindIGImageViewIn(snap);

	if (iv.image) {
		rygSaveImageViaDelegate(iv.image, target, ctx, bulk);
		return;
	}

	NSURL *url = rygIGImageViewURL(iv);
	if (url) {
		NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"jpg";
		RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:YES];
		delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, bulk);
		[delegate downloadFileWithURL:url fileExtension:ext hudLabel:rygInstantHudLabel(ctx)];
		return;
	}

	RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"No media available to save"));
}

static void rygSaveAllInstants(UIView *fromView, RYGInstantTarget target) {
	NSUInteger queued = 0;

	for (UIView *snap in rygAllSnapViewsIn(fromView.window)) {
		if (!rygSnapIsVideo(snap)) {
			UIImageView *iv = rygFindIGImageViewIn(snap);
			if (!iv || (!iv.image && !rygIGImageViewURL(iv))) continue;
		}

		rygSaveSnapView(snap, target, YES);
		queued++;
	}

	if (!queued) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD_BULK, RYGLocalized(@"Download failed"), RYGLocalized(@"No instants currently loaded"));
		return;
	}

	RYGNotifyInfo(RYG_NOTIF_DOWNLOAD_BULK, [NSString stringWithFormat:RYGLocalized(@"Queued %lu instants"), (unsigned long)queued], nil);
}

#pragma mark - Auto-save

static char kRYGInstantsImageHashKey;
static NSTimer *rygAutoSaveTimer;

static NSString *rygAutoSaveStorePath(void) {
	NSString *root = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	NSString *dir = [root stringByAppendingPathComponent:@"RyukGram/InstantsAutoSave"];
	[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	return [dir stringByAppendingPathComponent:@"saved.json"];
}

// Already-saved keys: CDN URL path (query is an expiring signature), or an
// image-bytes hash when no specifier URL exists.
static NSMutableOrderedSet<NSString *> *rygAutoSaveSeen(void) {
	static NSMutableOrderedSet *seen;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		NSData *data = [NSData dataWithContentsOfFile:rygAutoSaveStorePath()];
		NSArray *keys = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		seen = [NSMutableOrderedSet orderedSetWithArray:[keys isKindOfClass:NSArray.class] ? keys : @[]];
	});

	return seen;
}

static void rygAutoSavePersist(void) {
	static dispatch_queue_t queue;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ queue = dispatch_queue_create("com.ryukgram.instants.autosave", DISPATCH_QUEUE_SERIAL); });

	NSMutableOrderedSet *seen = rygAutoSaveSeen();
	while (seen.count > 1000) [seen removeObjectAtIndex:0];

	NSData *data = [NSJSONSerialization dataWithJSONObject:seen.array options:0 error:nil];
	NSString *path = rygAutoSaveStorePath();
	dispatch_async(queue, ^{ [data writeToFile:path atomically:YES]; });
}

static NSString *rygAutoSaveKey(UIImageView *iv, NSURL *url) {
	if (url.path.length) return url.path;

	UIImage *image = iv.image;
	if (!image) return nil;

	NSString *cached = objc_getAssociatedObject(image, &kRYGInstantsImageHashKey);
	if (cached) return cached;

	NSData *jpg = UIImageJPEGRepresentation(image, 0.9);
	if (!jpg) return nil;

	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(jpg.bytes, (CC_LONG)jpg.length, digest);

	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];

	objc_setAssociatedObject(image, &kRYGInstantsImageHashKey, hex, OBJC_ASSOCIATION_COPY_NONATOMIC);
	return hex;
}

static UIWindow *rygWindowWithSnaps(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (rygAllSnapViewsIn(window).count) return window;
		}
	}

	return nil;
}

static void rygAutoSaveStopTimer(void) {
	[rygAutoSaveTimer invalidate];
	rygAutoSaveTimer = nil;
}

static void rygAutoSaveTick(void) {
	NSString *mode = [RYGUtils getStringPref:@"instants_auto_save"];
	BOOL on = [mode isEqualToString:@"photos"] || [mode isEqualToString:@"gallery"];

	UIWindow *window = on ? rygWindowWithSnaps() : nil;
	if (!window) {
		rygAutoSaveStopTimer();
		return;
	}

	UIView *snap = rygActiveSnapInWindow(window);
	if (!snap) return;

	BOOL gallery = [mode isEqualToString:@"gallery"] && [RYGUtils getBoolPref:@"ryg_gallery_enabled"];
	RYGInstantTarget target = gallery ? RYGInstantTargetGallery : RYGInstantTargetPhotos;

	if (rygSnapIsVideo(snap)) {
		AVAsset *asset = rygAssetFromPlayerView(rygSnapVideoView(snap));
		NSURL *videoURL = rygVideoURLFromAsset(asset);
		NSString *key = videoURL.path.length ? videoURL.path : nil;
		if (!asset || !key || [rygAutoSaveSeen() containsObject:key]) return;

		[rygAutoSaveSeen() addObject:key];
		rygAutoSavePersist();
		rygSaveVideoSnap(snap, target, NO);
		return;
	}

	UIImageView *iv = rygFindIGImageViewIn(snap);
	NSURL *url = rygIGImageViewURL(iv);
	if (!iv || (!iv.image && !url)) return;

	NSString *key = rygAutoSaveKey(iv, url);
	if (!key || [rygAutoSaveSeen() containsObject:key]) return;

	[rygAutoSaveSeen() addObject:key];
	rygAutoSavePersist();

	RYGInstantContext ctx = rygContextForSnap(snap);

	if (iv.image) {
		rygSaveImageViaDelegate(iv.image, target, ctx, NO);
		return;
	}

	NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"jpg";
	RYGDownloadDelegate *delegate = [[RYGDownloadDelegate alloc] initWithAction:rygDLActionForTarget(target) showProgress:NO];
	delegate.pendingGallerySaveMetadata = rygInstantMetadata(ctx, NO);
	[delegate downloadFileWithURL:url fileExtension:ext hudLabel:rygInstantHudLabel(ctx)];
}

// Specifiers resolve async and swipes don't reliably trigger layout — poll
// while the viewer is up; the tick self-stops once no snap views remain.
static void rygAutoSaveEnsureTimer(void) {
	NSString *mode = [RYGUtils getStringPref:@"instants_auto_save"];
	if (![mode isEqualToString:@"photos"] && ![mode isEqualToString:@"gallery"]) return;
	if (rygAutoSaveTimer) return;

	rygAutoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:YES block:^(__unused NSTimer *timer) {
		rygAutoSaveTick();
	}];
}

static void rygExpandSnapView(UIView *snap) {
	if (!snap) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"Could not locate the instant on screen"));
		return;
	}

	if (rygSnapIsVideo(snap)) {
		AVAsset *asset = rygAssetFromPlayerView(rygSnapVideoView(snap));
		NSURL *url = rygVideoURLFromAsset(asset);
		if (url) {
			RYGInstantContext ctx = rygContextForSnap(snap);
			RYGMediaViewerItem *item = [RYGMediaViewerItem itemWithVideoURL:url
																   photoURL:nil
																	caption:ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : nil];
			item.metadata = rygInstantMetadata(ctx, NO);
			[RYGMediaViewer showItem:item];
			return;
		}
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"No media available to save"));
		return;
	}

	UIImageView *iv = rygFindIGImageViewIn(snap);
	UIImage *image = iv.image;

	if (!image) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"No media available to save"));
		return;
	}

	NSData *jpg = UIImageJPEGRepresentation(image, 1.0);
	if (!jpg) {
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"Failed to save"));
		return;
	}

	NSURL *tmp = [RYGTempFiles claimWithExt:@"jpg" ttl:900 tag:@"instant-expand"];
	if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:nil]) {
		[RYGTempFiles releaseURL:tmp];
		RYGNotifyError(RYG_NOTIF_DOWNLOAD, RYGLocalized(@"Download failed"), RYGLocalized(@"Failed to save"));
		return;
	}

	RYGInstantContext ctx = rygContextForSnap(snap);
	RYGMediaViewerItem *item = [RYGMediaViewerItem itemWithVideoURL:nil
														   photoURL:tmp
															caption:ctx.username.length ? [@"@" stringByAppendingString:ctx.username] : nil];
	item.metadata = rygInstantMetadata(ctx, NO);

	[RYGMediaViewer showItem:item];
}

#pragma mark - Action menu

static RYGAction *rygInstantsAction(NSString *title, NSString *icon, __weak UIView *headerRef, void (^block)(UIView *header)) {
	return [RYGAction actionWithTitle:title icon:icon handler:^{
		UIView *header = headerRef;
		if (header && block) block(header);
	}];
}

static RYGAction *rygInstantsLeafForAID(NSString *aid, __weak UIView *headerRef) {
	RYGActionDescriptor *desc = [RYGActionCatalog descriptorForActionID:aid source:RYGActionSourceInstants];
	if (!desc) return nil;

	if ([aid isEqualToString:RYGAID_Expand]) {
		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygExpandSnapView(rygActiveSnapView(header));
		});
	}

	if ([aid isEqualToString:RYGAID_DownloadSave]) {
		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygSaveSnapView(rygActiveSnapView(header), RYGInstantTargetPhotos, NO);
		});
	}

	if ([aid isEqualToString:RYGAID_DownloadGallery]) {
		if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;

		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygSaveSnapView(rygActiveSnapView(header), RYGInstantTargetGallery, NO);
		});
	}

	if ([aid isEqualToString:RYGAID_DownloadShare]) {
		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygSaveSnapView(rygActiveSnapView(header), RYGInstantTargetShare, NO);
		});
	}

	if ([aid isEqualToString:RYGAID_BulkDownloadSave]) {
		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygSaveAllInstants(header, RYGInstantTargetPhotos);
		});
	}

	if ([aid isEqualToString:RYGAID_BulkDownloadGallery]) {
		if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;

		return rygInstantsAction(desc.title, desc.iconSF, headerRef, ^(UIView *header) {
			rygSaveAllInstants(header, RYGInstantTargetGallery);
		});
	}

	return nil;
}

static UIMenu *rygInstantsBuildMenu(UIView *header) {
	if (!header) return [UIMenu menuWithTitle:@"" children:@[]];

	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceInstants];
	__weak UIView *weakHeader = header;

	NSArray<RYGAction *> *actions = [RYGActionMenu actionsForConfig:cfg dateHeader:nil resolver:^RYGAction *(NSString *aid) {
		return rygInstantsLeafForAID(aid, weakHeader);
	}];

	NSUInteger count = rygAllSnapViewsIn(header.window).count;
	if (count > 1) {
		NSMutableArray<RYGAction *> *patched = actions.mutableCopy;

		for (NSUInteger i = 0; i < patched.count; i++) {
			RYGAction *group = patched[i];
			if (!group.children.count) continue;

			BOOL bulk = NO;
			for (RYGAction *child in group.children) {
				if ([child.actionID hasPrefix:@"bulk_"]) {
					bulk = YES;
					break;
				}
			}

			if (bulk) {
				NSString *title = [NSString stringWithFormat:RYGLocalized(@"%@ (%lu)"), group.title, (unsigned long)count];
				patched[i] = [RYGAction actionWithTitle:title icon:group.systemIconName children:group.children];
				break;
			}
		}

		actions = patched;
	}

	return [RYGActionMenu buildMenuWithActions:actions];
}

static void rygInstantsExecuteDefaultTap(UIView *header) {
	if (!header) return;

	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceInstants];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";

	if ([tap isEqualToString:@"menu"]) return;

	RYGAction *action = rygInstantsLeafForAID(tap, header);
	if (action.handler) action.handler();
}

static void rygApplyConfirmIcon(RYGChromeButton *chrome, BOOL on) {
	[chrome setIconResource:on ? @"ig_icon_circle_check_outline_24" : @"ig_icon_circle_outline_24" pointSize:22];
	chrome.iconTint = UIColor.whiteColor;
}

@interface RYGInstantsActionTarget : NSObject
+ (instancetype)shared;
- (void)tap:(UIButton *)sender;
- (void)toggleConfirm:(UIButton *)sender;
@end

@implementation RYGInstantsActionTarget

+ (instancetype)shared {
	static RYGInstantsActionTarget *target;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ target = [RYGInstantsActionTarget new]; });
	return target;
}

- (void)tap:(UIButton *)sender {
	UIView *header = objc_getAssociatedObject(sender, &kRYGInstantsDLTargetKey);
	rygInstantsExecuteDefaultTap(header);
}

- (void)toggleConfirm:(UIButton *)sender {
	RYGChromeButton *chrome = objc_getAssociatedObject(sender, &kRYGInstantsCCBtnKey);

	BOOL on = ![RYGUtils getBoolPref:@"instants_advance_confirm"];
	[RYGUtils setPref:@(on) forKey:@"instants_advance_confirm"];

	rygApplyConfirmIcon(chrome, on);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

	RYGNotifyInfo(RYG_NOTIF_GENERIC,
				  on ? RYGLocalized(@"Switching confirmation on") : RYGLocalized(@"Switching confirmation off"),
				  nil);
}

@end

#pragma mark - Button

// slot 0 sits just left of the anchor; each further slot steps one button left.
static CGRect rygInstantsSlotFrame(UIView *anchor, UIView *header, NSInteger slot) {
	CGFloat side = 40.0;
	CGFloat gap = 8.0;

	if (anchor) {
		return CGRectMake(CGRectGetMinX(anchor.frame) - (side + gap) * (slot + 1),
						  CGRectGetMidY(anchor.frame) - side * 0.5,
						  side,
						  side);
	}

	CGFloat margin = 12.0;
	CGRect b = header.bounds;
	return CGRectMake(CGRectGetMaxX(b) - side - margin - (side + gap) * slot,
					  CGRectGetMinY(b) + header.safeAreaInsets.top + margin,
					  side,
					  side);
}

static void rygInstantsRemoveConfirmButton(UIView *header) {
	RYGChromeButton *chrome = objc_getAssociatedObject(header, &kRYGInstantsCCBtnKey);
	UIButton *hit = objc_getAssociatedObject(header, &kRYGInstantsCCHitKey);

	[chrome removeFromSuperview];
	[hit removeFromSuperview];

	objc_setAssociatedObject(header, &kRYGInstantsCCBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, &kRYGInstantsCCHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygInstantsRemoveButton(UIView *header) {
	RYGChromeButton *chrome = objc_getAssociatedObject(header, &kRYGInstantsDLBtnKey);
	UIButton *hit = objc_getAssociatedObject(header, &kRYGInstantsDLHitKey);

	[chrome removeFromSuperview];
	[hit removeFromSuperview];

	objc_setAssociatedObject(header, &kRYGInstantsDLBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, &kRYGInstantsDLHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, &kRYGInstantsDLWireKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static void rygInstantsWireButton(UIButton *hit, UIView *header) {
	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceInstants];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	NSString *wireKey = [NSString stringWithFormat:@"%@|%ld", tap, (long)rygInstantsConfigVersion];

	objc_setAssociatedObject(hit, &kRYGInstantsDLTargetKey, header, OBJC_ASSOCIATION_ASSIGN);

	NSString *old = objc_getAssociatedObject(hit, &kRYGInstantsDLWireKey);
	if ([old isEqualToString:wireKey]) return;

	[hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	__weak UIView *weakHeader = header;
	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *elements)) {
		UIMenu *menu = rygInstantsBuildMenu(weakHeader);
		completion(menu.children ?: @[]);
	}];

	hit.menu = [UIMenu menuWithChildren:@[deferred]];

	if ([tap isEqualToString:@"menu"]) {
		hit.showsMenuAsPrimaryAction = YES;
	} else {
		hit.showsMenuAsPrimaryAction = NO;
		[hit addTarget:RYGInstantsActionTarget.shared action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
	}

	objc_setAssociatedObject(hit, &kRYGInstantsDLWireKey, wireKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Hook

%hook _TtC40IGQuickSnapImmersiveViewerSingleSnapView40IGQuickSnapImmersiveViewerSingleSnapView

- (void)didMoveToWindow {
	%orig;
	if (((UIView *)self).window) rygAutoSaveEnsureTimer();
}

%end

%hook _TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	char *keys[] = { &kRYGInstantsDLHitKey, &kRYGInstantsCCHitKey };
	for (int i = 0; i < 2; i++) {
		UIButton *hit = objc_getAssociatedObject(self, keys[i]);
		if (hit && !hit.hidden && hit.alpha > 0.01) {
			CGPoint p = [hit convertPoint:point fromView:(UIView *)self];
			if ([hit pointInside:p withEvent:event]) return hit;
		}
	}

	return %orig;
}

- (void)layoutSubviews {
	%orig;

	UIView *header = (UIView *)self;
	BOOL hasSnap = rygInstantsHasVisibleSnap(header);
	BOOL wantDL = [RYGUtils getBoolPref:@"instants_download_btn"] && hasSnap;
	BOOL wantCC = [RYGUtils getBoolPref:@"instants_confirm_toggle_btn"] && hasSnap;

	if (!wantDL) rygInstantsRemoveButton(header);
	if (!wantCC) rygInstantsRemoveConfirmButton(header);
	if (!wantDL && !wantCC) return;

	UIView *anchor = rygInstantsHeaderAnchor(header);

	if (wantDL) {
		RYGChromeButton *chrome = objc_getAssociatedObject(header, &kRYGInstantsDLBtnKey);
		UIButton *hit = objc_getAssociatedObject(header, &kRYGInstantsDLHitKey);

		if (!chrome || !hit) {
			chrome = [[RYGChromeButton alloc] initWithSymbol:@"arrow.down" pointSize:18 diameter:40];
			chrome.bubbleColor = [UIColor colorWithWhite:0 alpha:0.45];
			chrome.iconTint = UIColor.whiteColor;
			chrome.userInteractionEnabled = NO;
			chrome.translatesAutoresizingMaskIntoConstraints = YES;
			[RYGActionIcon attachAutoUpdate:chrome source:RYGActionSourceInstants pointSize:18 style:RYGActionIconStylePlain];
			[header addSubview:chrome];

			hit = [UIButton buttonWithType:UIButtonTypeCustom];
			hit.backgroundColor = UIColor.clearColor;
			hit.translatesAutoresizingMaskIntoConstraints = YES;
			[header addSubview:hit];

			objc_setAssociatedObject(header, &kRYGInstantsDLBtnKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(header, &kRYGInstantsDLHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		rygInstantsWireButton(hit, header);

		CGRect frame = rygInstantsSlotFrame(anchor, header, 0);
		chrome.frame = frame;
		hit.frame = frame;
		chrome.hidden = hit.hidden = NO;
		chrome.alpha = hit.alpha = 1.0;

		[header bringSubviewToFront:chrome];
		[header bringSubviewToFront:hit];
	}

	if (wantCC) {
		RYGChromeButton *chrome = objc_getAssociatedObject(header, &kRYGInstantsCCBtnKey);
		UIButton *hit = objc_getAssociatedObject(header, &kRYGInstantsCCHitKey);

		if (!chrome || !hit) {
			chrome = [[RYGChromeButton alloc] initWithSymbol:@"circle" pointSize:22 diameter:40];
			chrome.bubbleColor = [UIColor colorWithWhite:0 alpha:0.45];
			chrome.userInteractionEnabled = NO;
			chrome.translatesAutoresizingMaskIntoConstraints = YES;
			[header addSubview:chrome];

			hit = [UIButton buttonWithType:UIButtonTypeCustom];
			hit.backgroundColor = UIColor.clearColor;
			hit.translatesAutoresizingMaskIntoConstraints = YES;
			[hit addTarget:RYGInstantsActionTarget.shared action:@selector(toggleConfirm:) forControlEvents:UIControlEventTouchUpInside];
			[header addSubview:hit];

			objc_setAssociatedObject(hit, &kRYGInstantsCCBtnKey, chrome, OBJC_ASSOCIATION_ASSIGN);
			objc_setAssociatedObject(header, &kRYGInstantsCCBtnKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			objc_setAssociatedObject(header, &kRYGInstantsCCHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}

		rygApplyConfirmIcon(chrome, [RYGUtils getBoolPref:@"instants_advance_confirm"]);

		CGRect frame = rygInstantsSlotFrame(anchor, header, wantDL ? 1 : 0);
		chrome.frame = frame;
		hit.frame = frame;
		chrome.hidden = hit.hidden = NO;
		chrome.alpha = hit.alpha = 1.0;

		[header bringSubviewToFront:chrome];
		[header bringSubviewToFront:hit];
	}
}

%end

%ctor {
	[[NSNotificationCenter defaultCenter] addObserverForName:RYGActionMenuConfigDidChangeNotification
													  object:nil
													   queue:NSOperationQueue.mainQueue
												  usingBlock:^(__unused NSNotification *notification) {
		NSNumber *source = notification.userInfo[@"source"];
		if (source.integerValue == RYGActionSourceInstants) rygInstantsConfigVersion++;
	}];
}