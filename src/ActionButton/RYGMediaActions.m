#import "RYGMediaActions.h"
#import "RYGMediaViewer.h"
#import "RYGRepostSheet.h"
#import "RYGActionMenuConfig.h"
#import "RYGActionCatalog.h"
#import "../RYGDashParser.h"
#import "../RYGFFmpeg.h"
#import "../RYGQualityPicker.h"
#import "../Utils.h"
#import "../Networking/RYGInstagramAPI.h"
#import "../Downloader/Download.h"
#import "../Downloader/RYGDownloadCenter.h"
#import "../Downloader/RYGDownloadLedger.h"
#import "../PhotoAlbum.h"
#import "../Gallery/RYGGalleryFile.h"
#import "../Gallery/RYGGallerySaveMetadata.h"
#import "../Gallery/RYGGalleryOriginController.h"
#import "../Features/StoriesAndMessages/RYGExcludedStoryUsers.h"
#import "../Features/StoriesAndMessages/OverlayHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Stamp/consume serialized — bulk actions queue several in quick succession.
static RYGGallerySaveMetadata *rygPendingGalleryMetadata = nil;
// Survives the consume above so muxing and bulk legs still get a name.
static RYGGallerySaveMetadata *rygNamingGalleryMetadata = nil;

static dispatch_queue_t rygPendingMetadataQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.pendingmeta", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static void rygSetPendingMetadata(RYGGallerySaveMetadata *m) {
    dispatch_sync(rygPendingMetadataQueue(), ^{
        rygPendingGalleryMetadata = m;
        if (m) rygNamingGalleryMetadata = m;
    });
}

static RYGGallerySaveMetadata *rygConsumePendingMetadata(void) {
    __block RYGGallerySaveMetadata *m = nil;
    dispatch_sync(rygPendingMetadataQueue(), ^{
        m = rygPendingGalleryMetadata;
        rygPendingGalleryMetadata = nil;
    });
    return m;
}

extern void rygToggleStoryAudio(void);
extern BOOL rygIsStoryAudioEnabled(void);

#pragma mark - Small helpers

static RYGGallerySource rygGallerySourceFromContext(RYGActionContext ctx) {
	switch (ctx) {
		case RYGActionContextFeed: return RYGGallerySourceFeed;
		case RYGActionContextReels: return RYGGallerySourceReels;
		case RYGActionContextStories: return RYGGallerySourceStories;
	}
	return RYGGallerySourceOther;
}

static RYGActionSource rygSourceFromContext(RYGActionContext ctx) {
	switch (ctx) {
		case RYGActionContextFeed: return RYGActionSourceFeed;
		case RYGActionContextReels: return RYGActionSourceReels;
		case RYGActionContextStories: return RYGActionSourceStories;
	}
	return RYGActionSourceFeed;
}

static NSString *rygSettingsTitleForContext(RYGActionContext ctx) {
	switch (ctx) {
		case RYGActionContextFeed: return RYGLocalized(@"Feed");
		case RYGActionContextReels: return RYGLocalized(@"Reels");
		case RYGActionContextStories: return RYGLocalized(@"Stories");
	}
	return RYGLocalized(@"General");
}

static NSString *rygDatePrefKeyForContext(RYGActionContext ctx) {
	switch (ctx) {
		case RYGActionContextFeed: return @"menu_date_feed";
		case RYGActionContextReels: return @"menu_date_reels";
		case RYGActionContextStories: return @"menu_date_stories";
	}
	return nil;
}

static id rygSendObj(id obj, NSString *selName) {
	if (!obj || !selName.length) return nil;
	SEL sel = NSSelectorFromString(selName);
	if (![obj respondsToSelector:sel]) return nil;
	@try { return ((id(*)(id, SEL))objc_msgSend)(obj, sel); }
	@catch (__unused id e) { return nil; }
}

static id rygKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try { return [obj valueForKey:key]; }
	@catch (__unused id e) { return nil; }
}

static id rygIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
	if (!ivar) ivar = class_getInstanceVariable([obj class], name);
	if (!ivar) return nil;
	@try { return object_getIvar(obj, ivar); }
	@catch (__unused id e) { return nil; }
}

static NSDictionary *rygMediaFieldCache(id obj) {
	if (!obj) return nil;
	if ([obj isKindOfClass:NSDictionary.class]) return obj;

	Class storable = NSClassFromString(@"IGAPIStorableObject");
	if (storable && ![obj isKindOfClass:storable]) return nil;

	id value = rygIvar(obj, "_fieldCache");
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static id rygFieldCache(id obj, NSString *key) {
	id value = rygMediaFieldCache(obj)[key];
	return (!value || [value isKindOfClass:NSNull.class]) ? nil : value;
}

static NSString *rygStringValue(id value) {
	if (!value || [value isKindOfClass:NSNull.class]) return nil;
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value respondsToSelector:@selector(stringValue)]) {
		NSString *s = [value stringValue];
		return s.length ? s : nil;
	}
	NSString *s = [value description];
	return s.length ? s : nil;
}

static NSString *rygStringFromObject(id obj, NSString *key) {
	return rygStringValue(rygSendObj(obj, key) ?: rygKVC(obj, key) ?: rygFieldCache(obj, key));
}

static NSURL *rygURLFromString(NSString *s) {
	return s.length ? [NSURL URLWithString:s] : nil;
}

static NSString *rygUsernameForMedia(id media) {
	id user = rygSendObj(media, @"user") ?: rygKVC(media, @"user") ?: rygFieldCache(media, @"user");
	NSString *username = rygStringFromObject(user, @"username");
	if (!username.length && [user isKindOfClass:NSDictionary.class]) username = ((NSDictionary *)user)[@"username"];
	return username.length ? username : nil;
}

static void rygConfirmThen(NSString *title, void(^block)(void)) {
	if (!block) return;
	if ([RYGUtils getBoolPref:@"dw_confirm"]) [RYGUtils showConfirmation:block title:title];
	else block();
}

static RYGDownloadDelegate *rygMakeDownloader(DownloadAction action, BOOL progress) {
	RYGDownloadDelegate *d = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:progress];
	RYGGallerySaveMetadata *m = rygConsumePendingMetadata();
	if (m) d.pendingGallerySaveMetadata = m;
	return d;
}

static RYGGallerySaveMetadata *rygMakeGalleryMetadata(RYGGallerySource source, id media, BOOL skipDedup) {
	RYGGallerySaveMetadata *m = RYGGallerySaveMetadata.new;
	m.source = (int16_t)source;
	m.skipDedup = skipDedup;
	if (media) {
		@try { [RYGGalleryOriginController populateMetadata:m fromMedia:media]; }
		@catch (__unused id e) {}
	}
	return m;
}

static void rygStampGalleryMetadataForMedia(id media, RYGActionContext ctx) {
	rygSetPendingMetadata(rygMakeGalleryMetadata(rygGallerySourceFromContext(ctx), media, NO));
}

static NSTimeInterval rygCoerceTimestamp(id value) {
	double d = 0.0;
	if ([value isKindOfClass:NSNumber.class]) d = [value doubleValue];
	else if ([value isKindOfClass:NSString.class]) d = [(NSString *)value doubleValue];
	if (d <= 0.0) return 0.0;
	if (d > 1e15) d /= 1e6;
	else if (d > 1e12) d /= 1e3;
	return d;
}

static NSDate *rygExtractDateFromMedia(id media) {
	NSDictionary *fc = rygMediaFieldCache(media);
	if (!fc) return nil;

	for (NSString *key in @[@"taken_at", @"device_timestamp", @"created_at", @"upload_time", @"published_time"]) {
		NSTimeInterval t = rygCoerceTimestamp(fc[key]);
		if (t > 0.0) return [NSDate dateWithTimeIntervalSince1970:t];
	}
	return nil;
}

static NSString *rygFormatDateHeader(NSDate *date) {
	if (!date) return nil;

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = NSDateFormatter.new;
		fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt.dateFormat = @"MMM d, yyyy 'at' h:mma";
		fmt.AMSymbol = @"am";
		fmt.PMSymbol = @"pm";
	});

	fmt.timeZone = NSTimeZone.localTimeZone;
	return [fmt stringFromDate:date];
}

static BOOL rygIsVideoURL(NSURL *url) {
	NSString *ext = url.pathExtension.lowercaseString;
	return [@[@"mp4", @"mov", @"m4v", @"webm"] containsObject:ext];
}

static void rygPresentActivity(NSArray *items) {
	if (!items.count) return;

	UIViewController *top = topMostController();
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];

	if (is_iPad()) {
		vc.popoverPresentationController.sourceView = top.view;
		vc.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width / 2.0, top.view.bounds.size.height / 2.0, 1.0, 1.0);
	}

	[RYGPhotoAlbum armWatcherIfEnabled];
	[top presentViewController:vc animated:YES completion:nil];
}

static NSArray<NSURL *> *rygURLsForMedias(NSArray *medias) {
	NSMutableArray<NSURL *> *urls = NSMutableArray.array;
	for (id media in medias) {
		NSURL *url = [RYGMediaActions bestURLForMedia:media];
		if (url) [urls addObject:url];
	}
	return urls.copy;
}

#pragma mark - Download helpers

static RYGGallerySaveMetadata *rygPeekPendingMetadata(void) {
	__block RYGGallerySaveMetadata *m = nil;
	dispatch_sync(rygPendingMetadataQueue(), ^{ m = rygPendingGalleryMetadata; });
	return m;
}

// skipDedup marks metadata copied onto carousel children, where the PK is the parent's.
static NSArray<NSString *> *rygDupKeys(NSURL *url, NSString *variant) {
	RYGGallerySaveMetadata *m = rygPeekPendingMetadata();
	return [RYGDownloadLedger keysForURL:url mediaPK:(m.skipDedup ? nil : m.sourceMediaPK) variant:variant];
}

static RYGGalleryFile *rygSaveFileToGalleryURL(NSURL *url, RYGGalleryMediaType type, NSError **error) {
	RYGGallerySaveMetadata *m = rygConsumePendingMetadata();
	RYGGallerySource source = m ? (RYGGallerySource)m.source : RYGGallerySourceOther;

	return [RYGGalleryFile saveFileToGallery:url source:source mediaType:type folderPath:nil metadata:m error:error];
}

#pragma mark - Shared helpers

static NSString *rygExt(NSURL *url, NSString *fallback) {
	return url.pathExtension.length ? url.pathExtension : fallback;
}

static NSArray<NSString *> *rygURLStringsForMedias(NSArray *medias) {
	NSMutableArray<NSString *> *out = NSMutableArray.array;
	for (NSURL *u in rygURLsForMedias(medias)) [out addObject:u.absoluteString];
	return out.copy;
}

static void rygCopyURLStrings(NSArray<NSString *> *urls) {
	if (!urls.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No URLs found")];
		return;
	}
	UIPasteboard.generalPasteboard.string = [urls componentsJoinedByString:@"\n"];
	RYGNotifySuccess(RYG_NOTIF_COPY_URL, [NSString stringWithFormat:RYGLocalized(@"Copied %lu URLs"), (unsigned long)urls.count], nil);
}

static void rygSavePhotosAsset(NSURL *url, PHAssetResourceType type, void(^completion)(BOOL success, NSError *error)) {
	[PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
		PHAssetCreationRequest *req = PHAssetCreationRequest.creationRequestForAsset;
		PHAssetResourceCreationOptions *opts = PHAssetResourceCreationOptions.new;
		opts.shouldMoveFile = YES;
		opts.originalFilename = url.lastPathComponent;
		[req addResourceWithType:type fileURL:url options:opts];
	} completionHandler:completion];
}

static void rygFinishJobWithGallerySave(RYGDownloadJob *job, NSURL *url, RYGGalleryMediaType type) {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSError *error = nil;
	RYGGalleryFile *file = rygSaveFileToGalleryURL(url, type, &error);
	if (file && !error) {
		[job noteGalleryFileID:file.identifier];
		job.successText = RYGLocalized(@"Saved to Gallery");
		[center markJobFinished:job];
	} else {
		[center markJob:job failedWithError:error];
	}
}

static NSArray<RYGMediaViewerItem *> *rygViewerItemsForChildren(NSArray *children, NSString *caption) {
	NSMutableArray<RYGMediaViewerItem *> *items = NSMutableArray.array;
	for (id child in children) {
		NSURL *v = [RYGUtils getVideoUrlForMedia:(IGMedia *)child];
		NSURL *p = [RYGUtils getPhotoUrlForMedia:(IGMedia *)child] ?: (!v ? [RYGMediaActions bestURLForMedia:child] : nil);
		if (v || p) [items addObject:[RYGMediaViewerItem itemWithVideoURL:v photoURL:p caption:caption]];
	}
	return items;
}

static void rygSaveVideoToPhotosURLForJob(NSURL *url, RYGDownloadJob *job) {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Photo library access denied")];
				[center markJob:job failedWithError:nil];
			});
			return;
		}

		BOOL useAlbum = [RYGUtils getBoolPref:@"save_to_ryukgram_album"];
		void (^done)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (ok) {
					job.successText = useAlbum ? RYGLocalized(@"Saved to RyukGram") : RYGLocalized(@"Saved to Photos");
					[center markJobFinished:job];
				} else {
					[center markJob:job failedWithError:error];
				}
			});
		};

		if (useAlbum) {
			[RYGPhotoAlbum saveFileToAlbum:url originalFilename:url.lastPathComponent completion:^(BOOL ok, NSError *error) {
				[NSFileManager.defaultManager removeItemAtURL:url error:nil];
				done(ok, error);
			}];
			return;
		}

		rygSavePhotosAsset(url, PHAssetResourceTypeVideo, done);
	}];
}

static NSString *const kRYGRetryKindDashVideo = @"dash_video";
static NSString *const kRYGRetryKindDashAudio = @"dash_audio";

static NSDictionary *rygRepDict(RYGDashRepresentation *rep) {
	if (!rep.url.absoluteString.length) return nil;
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"url"] = rep.url.absoluteString;
	d[@"bandwidth"] = @(rep.bandwidth);
	d[@"width"] = @(rep.width);
	d[@"height"] = @(rep.height);
	if (rep.contentType) d[@"contentType"] = rep.contentType;
	if (rep.qualityLabel) d[@"qualityLabel"] = rep.qualityLabel;
	d[@"frameRate"] = @(rep.frameRate);
	if (rep.codecs) d[@"codecs"] = rep.codecs;
	return d;
}

static NSDictionary *rygDashRetryInfo(NSString *kind, RYGDashRepresentation *video,
                                     RYGDashRepresentation *audio, DownloadAction action,
                                     RYGGallerySaveMetadata *meta) {
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"kind"] = kind;
	info[@"action"] = @(action);
	if (rygRepDict(video)) info[@"video"] = rygRepDict(video);
	if (rygRepDict(audio)) info[@"audio"] = rygRepDict(audio);
	if (meta) info[@"meta"] = [meta dictionaryRepresentation];
	if (!info[@"video"] && !info[@"audio"]) return nil;
	return info;
}

static RYGDashRepresentation *rygRepFromDict(NSDictionary *d) {
	if (![d isKindOfClass:NSDictionary.class]) return nil;
	NSURL *url = [NSURL URLWithString:d[@"url"] ?: @""];
	if (!url) return nil;
	RYGDashRepresentation *rep = [RYGDashRepresentation new];
	rep.url = url;
	rep.bandwidth = [d[@"bandwidth"] integerValue];
	rep.width = [d[@"width"] integerValue];
	rep.height = [d[@"height"] integerValue];
	rep.contentType = d[@"contentType"];
	rep.qualityLabel = d[@"qualityLabel"];
	rep.frameRate = [d[@"frameRate"] floatValue];
	rep.codecs = d[@"codecs"];
	return rep;
}

@implementation RYGMediaActions

// IG's CDN links are signed and expire, so a redownload only works while one lives.
+ (void)load {
	[RYGDownloadCenter registerRetryBuilder:^(NSDictionary *info) {
		RYGDashRepresentation *video = rygRepFromDict(info[@"video"]);
		RYGDashRepresentation *audio = rygRepFromDict(info[@"audio"]);
		if (!video) return;
		RYGGallerySaveMetadata *meta = [RYGGallerySaveMetadata metadataFromDictionary:info[@"meta"]];
		if (meta) rygSetPendingMetadata(meta);
		[RYGMediaActions downloadDASHVideo:video audio:audio action:(DownloadAction)[info[@"action"] unsignedIntegerValue]];
	} forKind:kRYGRetryKindDashVideo];

	[RYGDownloadCenter registerRetryBuilder:^(NSDictionary *info) {
		RYGDashRepresentation *audio = rygRepFromDict(info[@"audio"]);
		if (!audio) return;
		RYGGallerySaveMetadata *meta = [RYGGallerySaveMetadata metadataFromDictionary:info[@"meta"]];
		if (meta) rygSetPendingMetadata(meta);
		[RYGMediaActions downloadAudioRepresentation:audio action:(DownloadAction)[info[@"action"] unsignedIntegerValue]];
	} forKind:kRYGRetryKindDashAudio];
}

#pragma mark - Filename

+ (NSString *)contextLabelForContext:(RYGActionContext)ctx {
	return [RYGFileName contextSlugForSource:rygGallerySourceFromContext(ctx)];
}

+ (NSString *)currentFilenameStem {
	__block RYGGallerySaveMetadata *m = nil;
	dispatch_sync(rygPendingMetadataQueue(), ^{ m = rygNamingGalleryMetadata; });
	return [RYGFileName stemForMetadata:m];
}

#pragma mark - Media extraction

+ (NSString *)captionForMedia:(id)media {
	if (!media) return nil;

	for (NSString *sel in @[@"fullCaptionString", @"captionString", @"caption", @"captionText", @"text"]) {
		id value = rygSendObj(media, sel);
		if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) return value;

		for (NSString *textSel in @[@"text", @"string", @"commentText", @"rawText"]) {
			id text = rygSendObj(value, textSel);
			if ([text respondsToSelector:@selector(string)] && ![text isKindOfClass:NSString.class]) text = rygSendObj(text, @"string");
			if ([text isKindOfClass:NSString.class] && [(NSString *)text length]) return text;
		}

		id fcText = rygFieldCache(value, @"text");
		if ([fcText isKindOfClass:NSString.class] && [(NSString *)fcText length]) return fcText;
	}

	id cap = rygFieldCache(media, @"caption");
	if ([cap isKindOfClass:NSDictionary.class]) {
		NSString *text = ((NSDictionary *)cap)[@"text"];
		if (text.length) return text;
	} else if ([cap isKindOfClass:NSString.class] && [(NSString *)cap length]) {
		return cap;
	}

	NSString *text = rygStringFromObject(cap, @"text") ?: rygStringFromObject(cap, @"string");
	if (text.length) return text;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList(object_getClass(media), &count);
	for (unsigned int i = 0; i < count; i++) {
		const char *name = ivar_getName(ivars[i]);
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!name || !type || type[0] != '@') continue;

		NSString *ivarName = [NSString stringWithUTF8String:name].lowercaseString;
		if (![ivarName containsString:@"caption"]) continue;

		id val = nil;
		@try { val = object_getIvar(media, ivars[i]); }
		@catch (__unused id e) {}

		NSString *out = [val isKindOfClass:NSString.class] ? val : (rygStringFromObject(val, @"text") ?: rygStringFromObject(val, @"string"));
		if (out.length) {
			if (ivars) free(ivars);
			return out;
		}
	}

	if (ivars) free(ivars);
	return nil;
}

+ (BOOL)isCarouselMedia:(id)media {
	if (!media) return NO;

	SEL isCarouselSel = @selector(isCarousel);
	if ([media respondsToSelector:isCarouselSel]) {
		@try {
			if (((BOOL(*)(id, SEL))objc_msgSend)(media, isCarouselSel)) return YES;
		} @catch (__unused id e) {}
	}

	SEL mediaTypeSel = @selector(mediaType);
	if ([media respondsToSelector:mediaTypeSel]) {
		@try {
			if (((NSInteger(*)(id, SEL))objc_msgSend)(media, mediaTypeSel) == 8) return YES;
		} @catch (__unused id e) {}
	}

	return [self carouselChildrenForMedia:media].count > 0;
}

+ (NSArray *)carouselChildrenForMedia:(id)media {
	if (!media) return @[];

	for (NSString *sel in @[@"carouselMedia", @"carouselChildren", @"children"]) {
		id value = rygSendObj(media, sel);
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return value;
	}

	for (NSString *ivarName in @[@"_carouselMedia", @"_carouselChildren"]) {
		id value = rygIvar(media, ivarName.UTF8String);
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return value;
	}

	id fc = rygFieldCache(media, @"carousel_media");
	return [fc isKindOfClass:NSArray.class] ? fc : @[];
}

static const void *kRYGCarouselParentMediaKey = &kRYGCarouselParentMediaKey;

+ (void)stashCarouselParentMedia:(id)parent onView:(UIView *)view {
	if (!view) return;
	objc_setAssociatedObject(view, kRYGCarouselParentMediaKey, parent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (BOOL)mediaHasAudio:(id)media {
	if (!media) return NO;

	id hasAudio = rygFieldCache(media, @"has_audio");
	if ([hasAudio respondsToSelector:@selector(boolValue)] && [hasAudio boolValue]) return YES;

	id video = rygSendObj(media, @"video");
	id detected = rygSendObj(video, @"isAudioDetected");
	if ([detected respondsToSelector:@selector(boolValue)] && [detected boolValue]) return YES;

	for (NSString *key in @[@"music_metadata", @"story_music_stickers", @"is_story_image_with_music", @"story_sound_on", @"spotify_stickers", @"story_music_lyric_stickers"]) {
		id value = rygFieldCache(media, key);
		if (!value || [value isKindOfClass:NSNull.class]) continue;
		if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) return YES;
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return YES;
		if ([value isKindOfClass:NSDictionary.class] && [(NSDictionary *)value count]) return YES;
	}

	return [RYGDashParser dashManifestForMedia:media].length > 0;
}

#pragma mark - Music-on-photo extraction

// Carousels keep the music on the parent media only.
static NSDictionary *rygMusicTrackInfo(id media, id parentMedia) {
	id mm = rygFieldCache(media, @"music_metadata") ?: rygFieldCache(parentMedia, @"music_metadata");
	if (!mm) return nil;

	id mi = rygKVC(mm, @"musicInfo");
	id track = rygKVC(mi, @"musicAssetInfo");
	id ci = rygKVC(mi, @"musicConsumptionInfo");
	id os = rygKVC(mm, @"originalSoundInfo");

	NSString *urlStr = rygStringValue(rygKVC(track, @"progressiveDownloadURLString"))
		?: rygStringValue(rygKVC(track, @"fastStartProgressiveDownloadURLString"))
		?: rygStringValue(rygKVC(os, @"progressiveDownloadURLString"));
	NSURL *url = rygURLFromString(urlStr);

	if (!url) {
		id owner = rygFieldCache(media, @"music_metadata") ? media : parentMedia;
		id sundial = rygKVC(owner, @"sundialMusicAsset");
		id u = rygKVC(sundial, @"audioFileUrl");
		if ([u isKindOfClass:NSURL.class]) url = u;
	}
	if (!url) return nil;

	double startMs = 0, durMs = 0;
	id sv = rygKVC(ci, @"audioAssetStartTimeInMs") ?: rygKVC(os, @"audioAssetStartTimeInMs");
	if ([sv respondsToSelector:@selector(doubleValue)]) startMs = [sv doubleValue];
	id dv = rygKVC(ci, @"overlapDurationInMs") ?: rygKVC(os, @"overlapDurationInMs");
	if ([dv respondsToSelector:@selector(doubleValue)]) durMs = [dv doubleValue];
	if (durMs <= 0) durMs = 15000;

	NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
		@"url": url, @"startMs": @(startMs), @"durMs": @(durMs)
	}];
	NSString *title = rygStringValue(rygKVC(track, @"title"));
	NSString *artist = rygStringValue(rygKVC(track, @"displayArtist"));
	if (title.length) info[@"title"] = title;
	if (artist.length) info[@"artist"] = artist;
	return info;
}

+ (BOOL)mediaHasMusic:(id)media parentMedia:(id)parentMedia {
	return rygMusicTrackInfo(media, parentMedia) != nil;
}

+ (BOOL)mediaIsStillImageWithAudio:(id)media parentMedia:(id)parentMedia {
	if (!media) return NO;

	// IG muxes photo+soundtrack into media_type=2 with video_versions and no distinguishing fieldCache flag; gate on music sticker + still frame, exclude reshared clips.
	if (rygFieldCache(media, @"clips_metadata")) return NO;

	BOOL hasStillURL = [self hdPhotoURLForMedia:media]
		|| [RYGUtils getPhotoUrlForMedia:(IGMedia *)media]
		|| [self fieldCachePhotoURLForMedia:media];
	if (!hasStillURL) return NO;

	if ([self mediaHasMusic:media parentMedia:parentMedia]) return YES;

	id flag = rygFieldCache(media, @"is_story_image_with_music");
	if ([flag respondsToSelector:@selector(boolValue)] && [flag boolValue]) return YES;

	for (NSString *k in @[@"story_music_stickers", @"story_music_lyric_stickers", @"spotify_stickers", @"music_metadata"]) {
		id v = rygFieldCache(media, k);
		if ([v isKindOfClass:NSArray.class] && [(NSArray *)v count]) return YES;
		if ([v isKindOfClass:NSDictionary.class] && [(NSDictionary *)v count]) return YES;
	}
	return NO;
}

+ (NSURL *)fieldCachePhotoURLForMedia:(id)media {
	id candidates = nil;
	id iv2 = rygFieldCache(media, @"image_versions2");
	if ([iv2 isKindOfClass:NSDictionary.class]) candidates = ((NSDictionary *)iv2)[@"candidates"];
	if (!candidates) candidates = rygFieldCache(media, @"candidates");
	if (![candidates isKindOfClass:NSArray.class]) return nil;

	NSDictionary *best = nil;
	NSInteger bestWidth = 0;
	for (NSDictionary *candidate in (NSArray *)candidates) {
		if (![candidate isKindOfClass:NSDictionary.class]) continue;
		id widthObj = candidate[@"width"];
		NSInteger width = [widthObj respondsToSelector:@selector(integerValue)] ? [widthObj integerValue] : 0;
		if (width > bestWidth) {
			bestWidth = width;
			best = candidate;
		}
	}

	return rygURLFromString(best[@"url"]);
}

+ (NSURL *)hdPhotoURLForMedia:(id)media {
	NSURL *url = [self fieldCachePhotoURLForMedia:media];
	if (url) return url;

	id photo = rygSendObj(media, @"photo");
	id versions = rygIvar(photo, "_originalImageVersions");
	if (![versions isKindOfClass:NSArray.class]) return nil;

	NSURL *bestURL = nil;
	NSInteger bestWidth = 0;

	for (id item in (NSArray *)versions) {
		NSURL *u = nil;
		NSInteger w = 0;

		if ([item isKindOfClass:NSDictionary.class]) {
			u = rygURLFromString(((NSDictionary *)item)[@"url"]);
			id widthObj = ((NSDictionary *)item)[@"width"];
			w = [widthObj respondsToSelector:@selector(integerValue)] ? [widthObj integerValue] : 0;
		} else {
			id urlObj = rygSendObj(item, @"url") ?: rygKVC(item, @"url");
			if ([urlObj isKindOfClass:NSURL.class]) u = urlObj;
			else if ([urlObj isKindOfClass:NSString.class]) u = rygURLFromString(urlObj);
			id widthObj = rygSendObj(item, @"width") ?: rygKVC(item, @"width");
			w = [widthObj respondsToSelector:@selector(integerValue)] ? [widthObj integerValue] : 0;
		}

		if (u && w > bestWidth) {
			bestURL = u;
			bestWidth = w;
		}
	}

	return bestURL;
}

+ (NSURL *)bestURLForMedia:(id)media {
	if (!media) return nil;

	NSURL *video = [RYGUtils getVideoUrlForMedia:(IGMedia *)media];
	if (video) return video;

	if ([[RYGUtils getStringPref:@"default_photo_quality"] isEqualToString:@"high"]) {
		NSURL *hd = [self hdPhotoURLForMedia:media];
		if (hd) return hd;
	}

	return [RYGUtils getPhotoUrlForMedia:(IGMedia *)media] ?: [self fieldCachePhotoURLForMedia:media];
}

+ (NSURL *)coverURLForMedia:(id)media {
	return media ? [RYGUtils getPhotoUrlForMedia:(IGMedia *)media] : nil;
}

#pragma mark - Single downloads

+ (void)downloadPhotoOnlyForMedia:(id)media action:(DownloadAction)action {
	NSURL *url = [self hdPhotoURLForMedia:media] ?: [RYGUtils getPhotoUrlForMedia:(IGMedia *)media] ?: [self fieldCachePhotoURLForMedia:media];
	if (!url) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract photo URL")];
		return;
	}

	NSString *ext = rygExt(url, @"jpg");
	[rygMakeDownloader(action, NO) downloadFileWithURL:url fileExtension:ext hudLabel:nil];
}

+ (void)downloadAudioOnlyForMedia:(id)media action:(DownloadAction)action {
	NSString *manifest = [RYGDashParser dashManifestForMedia:media];
	RYGDashRepresentation *audio = [RYGDashParser bestAudioFromRepresentations:[RYGDashParser parseManifest:manifest]];
	[self downloadAudioRepresentation:audio action:action];
}

+ (void)downloadAudioRepresentation:(RYGDashRepresentation *)audio action:(DownloadAction)action {
	if (!audio.url) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No audio track found")];
		return;
	}

	if (![RYGFFmpeg isAvailable]) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"FFmpeg not available")];
		return;
	}

	NSArray<NSString *> *keys = rygDupKeys(audio.url, @"audio");
	[RYGDownloadLedger guardKeys:keys proceed:^{
		[self startAudioRepresentation:audio action:action duplicateKeys:keys];
	}];
}

+ (void)startAudioRepresentation:(RYGDashRepresentation *)audio action:(DownloadAction)action duplicateKeys:(NSArray<NSString *> *)duplicateKeys {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSString *outPath = [RYGTempFiles claimNamedFile:[self.currentFilenameStem stringByAppendingPathExtension:@"m4a"] ttl:900 tag:@"audio"].path;
	NSString *cmd = [NSString stringWithFormat:@"-i \"%@\" -vn -c:a copy -y \"%@\"", audio.url.absoluteString, outPath];

	__block RYGDownloadJob *job = nil;
	void (^start)(void) = ^{
		[center job:job didProgress:0.05f stage:RYGLocalized(@"Downloading audio…")];
		[RYGFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([RYGFFmpeg isCancelled]) {
					[NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
					[center markJobCancelled:job];
					return;
				}
				if (!success) {
					[NSFileManager.defaultManager removeItemAtPath:outPath error:nil];
					[center markJob:job failedWithError:nil];
					return;
				}

				NSURL *fileURL = [NSURL fileURLWithPath:outPath];
				job.resultFileURL = fileURL;

				if (action == saveToGallery) {
					rygFinishJobWithGallerySave(job, fileURL, RYGGalleryMediaTypeAudio);
					return;
				}

				job.successText = RYGLocalized(@"Audio ready");
				[center markJobFinished:job];
				if (action == quickLook) [RYGUtils showQuickLookVC:@[fileURL]];
				else [RYGUtils showShareVC:fileURL];
			});
		}];
	};

	NSString *audioUser = rygPeekPendingMetadata().sourceUsername;
	job = [center enqueueJobWithTitle:(audioUser.length ? [@"@" stringByAppendingString:audioUser] : RYGLocalized(@"Audio"))
	                             kind:RYGDownloadJobKindDashMux
	                            start:start
	                           cancel:^{ [RYGFFmpeg cancelAll]; }];
	job.subtitle = RYGLocalized(@"Audio");
	job.mediaKind = RYGDownloadMediaKindAudio;
	job.duplicateKeys = duplicateKeys;
	job.retryBlock = ^{ [RYGMediaActions downloadAudioRepresentation:audio action:action]; };
	job.retryInfo = rygDashRetryInfo(kRYGRetryKindDashAudio, nil, audio, action, rygPeekPendingMetadata());
}

static NSString *rygMediaIdentifier(id media) {
	NSString *pk = rygStringFromObject(media, @"strong_id__") ?: rygStringFromObject(media, @"pk");
	return pk.length ? pk : nil;
}

static NSMutableDictionary<NSString *, NSURL *> *rygProgressiveURLCache(void) {
	static NSMutableDictionary *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
	return cache;
}

static NSURL *rygProgressiveURLFromVersions(id versions) {
	if (![versions isKindOfClass:NSArray.class]) return nil;

	NSDictionary *best = nil;
	NSInteger bestWidth = -1;

	for (NSDictionary *version in (NSArray *)versions) {
		if (![version isKindOfClass:NSDictionary.class]) continue;
		NSInteger width = [version[@"width"] respondsToSelector:@selector(integerValue)] ? [version[@"width"] integerValue] : 0;
		if (width > bestWidth) {
			bestWidth = width;
			best = version;
		}
	}

	return rygURLFromString(best[@"url"]);
}

static NSMutableDictionary<NSString *, NSMutableArray *> *rygProgressiveURLWaiters(void) {
	static NSMutableDictionary *waiters;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ waiters = [NSMutableDictionary dictionary]; });
	return waiters;
}

+ (NSURL *)cachedProgressiveVideoURLForMedia:(id)media {
	NSString *identifier = rygMediaIdentifier(media);
	return identifier ? rygProgressiveURLCache()[identifier] : nil;
}

+ (void)prefetchProgressiveVideoURLForMedia:(id)media {
	id duration = rygFieldCache(media, @"video_duration");
	if (![duration respondsToSelector:@selector(doubleValue)] || [duration doubleValue] <= 0.0) return;
	if ([RYGUtils getVideoUrlForMedia:(IGMedia *)media]) return;

	[self progressiveVideoURLForMedia:media completion:^(__unused NSURL *url) {}];
}

+ (void)progressiveVideoURLForMedia:(id)media completion:(void(^)(NSURL *url))completion {
	if (!completion) return;

	NSURL *known = [RYGUtils getVideoUrlForMedia:(IGMedia *)media] ?: [self cachedProgressiveVideoURLForMedia:media];
	if (known) { completion(known); return; }

	NSString *identifier = rygMediaIdentifier(media);
	if (!identifier) { completion(nil); return; }

	NSMutableArray *waiters = rygProgressiveURLWaiters()[identifier];
	if (waiters) { [waiters addObject:[completion copy]]; return; }

	rygProgressiveURLWaiters()[identifier] = [NSMutableArray arrayWithObject:[completion copy]];

	[RYGInstagramAPI fetchMediaInfoForMediaId:identifier completion:^(NSDictionary *response, __unused NSError *error) {
		id items = response[@"items"];
		id item = [items isKindOfClass:NSArray.class] ? [(NSArray *)items firstObject] : nil;
		NSURL *url = rygProgressiveURLFromVersions([item isKindOfClass:NSDictionary.class] ? item[@"video_versions"] : nil);

		if (url) rygProgressiveURLCache()[identifier] = url;

		NSArray *pending = rygProgressiveURLWaiters()[identifier];
		[rygProgressiveURLWaiters() removeObjectForKey:identifier];
		for (void (^waiter)(NSURL *) in pending) waiter(url);
	}];
}

+ (BOOL)mediaIsVideo:(id)media {
	if (!media) return NO;

	if ([RYGUtils getVideoUrlForMedia:(IGMedia *)media]) return YES;

	id type = rygFieldCache(media, @"media_type");
	if ([type respondsToSelector:@selector(integerValue)] && [type integerValue] == 2) return YES;

	id duration = rygFieldCache(media, @"video_duration");
	if ([duration respondsToSelector:@selector(doubleValue)] && [duration doubleValue] > 0.0) return YES;

	id video = rygSendObj(media, @"video");
	id manifestData = rygIvar(video, "_dashManifestData");
	if ([manifestData isKindOfClass:NSData.class] && [(NSData *)manifestData length]) return YES;

	return [RYGDashParser dashManifestForMedia:media].length > 0;
}

+ (BOOL)downloadHighestDASHForMedia:(id)media action:(DownloadAction)action {
	NSString *manifest = [RYGDashParser dashManifestForMedia:media];
	if (!manifest.length || [manifest hasPrefix:@"http"]) return NO;

	NSArray<RYGDashRepresentation *> *all = [RYGDashParser parseManifest:manifest];
	RYGDashRepresentation *video = [RYGDashParser representationForQuality:RYGVideoQualityHighest fromRepresentations:all];
	if (!video.url) return NO;

	RYGDashRepresentation *audio = [RYGDashParser audioRepresentations:all].firstObject;
	if (audio.url && [RYGFFmpeg isAvailable]) {
		[self downloadDASHVideo:video audio:audio action:action];
		return YES;
	}

	[rygMakeDownloader(action, YES) downloadFileWithURL:video.url fileExtension:rygExt(video.url, @"mp4") hudLabel:nil];
	return YES;
}

+ (void)downloadHDMedia:(id)media action:(DownloadAction)action fromView:(UIView *)sourceView {
	if (!media) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No media")];
		return;
	}

	if (![self mediaIsVideo:media]) {
		NSURL *url = [self bestURLForMedia:media];
		if (!url) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract photo URL")];
			return;
		}

		[rygMakeDownloader(action, NO) downloadFileWithURL:url fileExtension:rygExt(url, @"jpg") hudLabel:nil];
		return;
	}

	BOOL handled = [RYGQualityPicker pickQualityForMedia:media
												fromView:sourceView
												 action:action
												 picked:^(RYGDashRepresentation *video, RYGDashRepresentation *audio) {
		[self downloadDASHVideo:video audio:audio action:action];
	} fallback:^{
		NSURL *url = [RYGUtils getVideoUrlForMedia:(IGMedia *)media] ?: [self cachedProgressiveVideoURLForMedia:media];
		if (url) {
			[rygMakeDownloader(action, YES) downloadFileWithURL:url fileExtension:rygExt(url, @"mp4") hudLabel:nil];
			return;
		}

		if ([self downloadHighestDASHForMedia:media action:action]) return;

		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")];
	}];

	(void)handled;
}

+ (void)downloadDASHVideo:(RYGDashRepresentation *)videoRep audio:(RYGDashRepresentation *)audioRep action:(DownloadAction)action {
	if (!videoRep.url) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No video URL")];
		return;
	}

	NSArray<NSString *> *keys = rygDupKeys(videoRep.url, @"video");
	[RYGDownloadLedger guardKeys:keys proceed:^{
		[self startDASHVideo:videoRep audio:audioRep action:action duplicateKeys:keys];
	}];
}

+ (void)startDASHVideo:(RYGDashRepresentation *)videoRep audio:(RYGDashRepresentation *)audioRep action:(DownloadAction)action duplicateKeys:(NSArray<NSString *> *)duplicateKeys {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSString *preset = [RYGUtils getStringPref:@"ffmpeg_encoding_speed"];
	if (!preset.length) preset = @"ultrafast";

	RYGGallerySaveMetadata *meta = rygPeekPendingMetadata();
	NSString *user = meta.sourceUsername;
	NSString *title = user.length ? [@"@" stringByAppendingString:user] : RYGLocalized(@"HD video");
	NSString *subtitle = videoRep.qualityLabel.length
		? [NSString stringWithFormat:RYGLocalized(@"Video · %@"), videoRep.qualityLabel]
		: RYGLocalized(@"Video");

	__block RYGDownloadJob *job = nil;
	__block void (^muxCancel)(void) = nil;
	__block BOOL pendingCancel = NO;

	void (^start)(void) = ^{
		[RYGFFmpeg muxVideoURL:videoRep.url audioURL:audioRep.url preset:preset progress:^(float progress, NSString *stage) {
			if (stage && [stage.lowercaseString containsString:@"encod"])
				[center job:job enterEncodingStage:stage];
			[center job:job didProgress:progress stage:stage];
		} completion:^(NSURL *outputURL, NSError *error) {
			if (pendingCancel || (error && error.code == NSUserCancelledError)) {
				[center markJobCancelled:job];
				if (outputURL) [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
				return;
			}
			if (error || !outputURL) {
				[center markJob:job failedWithError:error];
				return;
			}

			job.resultFileURL = outputURL;
			switch (action) {
				case share:
					job.successText = RYGLocalized(@"HD download complete");
					[center markJobFinished:job];
					[RYGUtils showShareVC:outputURL];
					break;
				case quickLook:
					job.successText = RYGLocalized(@"HD download complete");
					[center markJobFinished:job];
					[RYGUtils showQuickLookVC:@[outputURL]];
					break;
				case saveToGallery:
					rygFinishJobWithGallerySave(job, outputURL, RYGGalleryMediaTypeVideo);
					break;
				case saveToPhotos: {
					NSString *galleryMode = [RYGUtils getStringPref:@"gallery_save_mode"];
					if ([galleryMode isEqualToString:@"gallery_only"]) {
						rygFinishJobWithGallerySave(job, outputURL, RYGGalleryMediaTypeVideo);
					} else {
						// Mirror: copy to gallery before the Photos save moves the file.
						if ([galleryMode isEqualToString:@"mirror"]) {
							NSError *e = nil;
							[job noteGalleryFileID:rygSaveFileToGalleryURL(outputURL, RYGGalleryMediaTypeVideo, &e).identifier];
						}
						rygSaveVideoToPhotosURLForJob(outputURL, job);
					}
					break;
				}
			}
		} cancelOut:^(void (^cb)(void)) {
			muxCancel = [cb copy];
			if (pendingCancel && muxCancel) muxCancel();
		}];
	};

	job = [center enqueueJobWithTitle:title
	                             kind:RYGDownloadJobKindDashMux
	                            start:start
	                           cancel:^{
		pendingCancel = YES;
		if (muxCancel) muxCancel();
	}];
	job.subtitle = subtitle;
	job.mediaKind = RYGDownloadMediaKindVideo;
	job.duplicateKeys = duplicateKeys;
	job.retryBlock = ^{
		[RYGMediaActions downloadDASHVideo:videoRep audio:audioRep action:action];
	};
	job.retryInfo = rygDashRetryInfo(kRYGRetryKindDashVideo, videoRep, audioRep, action, meta);
}

+ (BOOL)downloadVisualDMVideo:(id)igVideo action:(DownloadAction)action metadata:(id)metadata {
	if (!igVideo || ![RYGUtils getBoolPref:@"enhance_download_quality"] || ![RYGFFmpeg isAvailable]) return NO;

	Ivar iv = class_getInstanceVariable([igVideo class], "_dashManifestData");
	id manifestData = iv ? object_getIvar(igVideo, iv) : nil;
	if (![manifestData isKindOfClass:NSData.class] || ![(NSData *)manifestData length]) return NO;

	NSString *xml = [[NSString alloc] initWithData:manifestData encoding:NSUTF8StringEncoding];
	if (!xml.length) return NO;

	NSURL *standardURL = [RYGUtils getVideoUrl:igVideo];  // progressive low-bitrate "Standard" option
	RYGGallerySaveMetadata *meta = [metadata isKindOfClass:[RYGGallerySaveMetadata class]] ? metadata : nil;

	return [RYGQualityPicker pickQualityWithManifestXML:xml standardURL:standardURL fromView:nil action:action
		picked:^(RYGDashRepresentation *video, RYGDashRepresentation *audio) {
			if (meta) rygSetPendingMetadata(meta);
			[self downloadDASHVideo:video audio:audio action:action];
		} fallback:^{
			if (!standardURL) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract video URL")]; return; }
			if (meta) rygSetPendingMetadata(meta);
			[rygMakeDownloader(action, YES) downloadFileWithURL:standardURL fileExtension:rygExt(standardURL, @"mp4") hudLabel:nil];
		}];
}

+ (void)downloadPhotoWithMusicForMedia:(id)media parentMedia:(id)parentMedia action:(DownloadAction)action {
	NSDictionary *info = rygMusicTrackInfo(media, parentMedia);
	NSURL *photoURL = [self hdPhotoURLForMedia:media] ?: [RYGUtils getPhotoUrlForMedia:(IGMedia *)media] ?: [self fieldCachePhotoURLForMedia:media];
	if (!info || !photoURL) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract media URL")];
		return;
	}

	NSArray<NSString *> *keys = rygDupKeys(photoURL, @"photomusic");
	[RYGDownloadLedger guardKeys:keys proceed:^{
		[self startPhotoWithMusicForMedia:media parentMedia:parentMedia action:action info:info photoURL:photoURL duplicateKeys:keys];
	}];
}

+ (void)startPhotoWithMusicForMedia:(id)media parentMedia:(id)parentMedia action:(DownloadAction)action info:(NSDictionary *)info photoURL:(NSURL *)photoURL duplicateKeys:(NSArray<NSString *> *)duplicateKeys {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	RYGGallerySaveMetadata *meta = rygPeekPendingMetadata();
	NSString *user = meta.sourceUsername;
	NSString *title = user.length ? [@"@" stringByAppendingString:user] : RYGLocalized(@"Photo with music");
	NSString *trackLabel = info[@"title"];
	if (trackLabel.length && [info[@"artist"] length]) trackLabel = [NSString stringWithFormat:@"%@ — %@", info[@"artist"], info[@"title"]];

	__block RYGDownloadJob *job = nil;
	__block void (^muxCancel)(void) = nil;
	__block BOOL pendingCancel = NO;

	void (^start)(void) = ^{
		[RYGFFmpeg muxPhotoURL:photoURL
		              audioURL:info[@"url"]
		          audioStartMs:[info[@"startMs"] doubleValue]
		            durationMs:[info[@"durMs"] doubleValue]
		              progress:^(float progress, NSString *stage) {
			if (stage && [stage.lowercaseString containsString:@"encod"])
				[center job:job enterEncodingStage:stage];
			[center job:job didProgress:progress stage:stage];
		} completion:^(NSURL *outputURL, NSError *error) {
			if (pendingCancel || (error && error.code == NSUserCancelledError)) {
				[center markJobCancelled:job];
				if (outputURL) [NSFileManager.defaultManager removeItemAtURL:outputURL error:nil];
				return;
			}
			if (error || !outputURL) {
				[center markJob:job failedWithError:error];
				return;
			}

			job.resultFileURL = outputURL;
			if (action == saveToGallery) {
				rygFinishJobWithGallerySave(job, outputURL, RYGGalleryMediaTypeVideo);
				return;
			}
			NSString *galleryMode = [RYGUtils getStringPref:@"gallery_save_mode"];
			if ([galleryMode isEqualToString:@"gallery_only"]) {
				rygFinishJobWithGallerySave(job, outputURL, RYGGalleryMediaTypeVideo);
			} else {
				if ([galleryMode isEqualToString:@"mirror"]) {
					NSError *e = nil;
					[job noteGalleryFileID:rygSaveFileToGalleryURL(outputURL, RYGGalleryMediaTypeVideo, &e).identifier];
				}
				rygSaveVideoToPhotosURLForJob(outputURL, job);
			}
		} cancelOut:^(void (^cb)(void)) {
			muxCancel = [cb copy];
			if (pendingCancel && muxCancel) muxCancel();
		}];
	};

	job = [center enqueueJobWithTitle:title
	                             kind:RYGDownloadJobKindDashMux
	                            start:start
	                           cancel:^{
		pendingCancel = YES;
		if (muxCancel) muxCancel();
	}];
	job.subtitle = trackLabel.length ? trackLabel : RYGLocalized(@"Photo with music");
	job.duplicateKeys = duplicateKeys;
	job.retryBlock = ^{
		[RYGMediaActions downloadPhotoWithMusicForMedia:media parentMedia:parentMedia action:action];
	};
}

#pragma mark - Primary actions

+ (void)expandMedia:(id)media fromView:(UIView *)sourceView caption:(NSString *)caption {
	if (!media) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No media to expand")];
		return;
	}

	NSString *cap = caption ?: [self captionForMedia:media];

	if ([self isCarouselMedia:media]) {
		NSArray<RYGMediaViewerItem *> *items = rygViewerItemsForChildren([self carouselChildrenForMedia:media], cap);
		if (items.count) {
			[RYGMediaViewer showItems:items startIndex:0];
			return;
		}
	}

	NSURL *v = [RYGUtils getVideoUrlForMedia:(IGMedia *)media];
	NSURL *p = [RYGUtils getPhotoUrlForMedia:(IGMedia *)media] ?: (!v ? [self bestURLForMedia:media] : nil);

	if (!v && !p) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract media URL")];
		return;
	}

	[RYGMediaViewer showWithVideoURL:v photoURL:p caption:cap];
}

+ (void)downloadAndShareMedia:(id)media {
	[self downloadAndShareMedia:media fromView:nil];
}

+ (void)downloadAndShareMedia:(id)media fromView:(UIView *)sourceView {
	rygConfirmThen(RYGLocalized(@"Download and share"), ^{
		[self downloadHDMedia:media action:share fromView:sourceView];
	});
}

+ (void)downloadAndSaveMedia:(id)media {
	[self downloadAndSaveMedia:media fromView:nil];
}

+ (void)downloadAndSaveMedia:(id)media fromView:(UIView *)sourceView {
	rygConfirmThen(RYGLocalized(@"Save to Photos"), ^{
		[self downloadHDMedia:media action:saveToPhotos fromView:sourceView];
	});
}

+ (void)downloadAndSaveMediaToGallery:(id)media fromView:(UIView *)sourceView {
	rygConfirmThen([NSString stringWithFormat:@"%@?", RYGLocalized(@"Save to Gallery")], ^{
		[self downloadHDMedia:media action:saveToGallery fromView:sourceView];
	});
}

+ (void)copyURLForMedia:(id)media {
	NSURL *url = [self bestURLForMedia:media];
	if (!url) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract media URL")];
		return;
	}

	UIPasteboard.generalPasteboard.string = url.absoluteString;
	RYGNotifySuccess(RYG_NOTIF_COPY_URL, RYGLocalized(@"Copied download URL"), nil);
}

+ (void)copyCaptionForMedia:(id)media {
	NSString *caption = [self captionForMedia:media];
	if (!caption.length) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No caption on this post")];
		return;
	}

	UIPasteboard.generalPasteboard.string = caption;
	RYGNotifySuccess(RYG_NOTIF_COPY_CAPTION, RYGLocalized(@"Copied caption"), nil);
}

#pragma mark - Bulk helpers

+ (void)bulkDownloadURLs:(NSArray<NSURL *> *)urls title:(NSString *)title username:(NSString *)username done:(void(^)(NSArray<NSURL *> *fileURLs))done {
	if (!urls.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No URLs")];
		return;
	}

	NSMutableArray<NSArray<NSString *> *> *groups = [NSMutableArray array];
	for (NSURL *u in urls) [groups addObject:[RYGDownloadLedger keysForURL:u mediaPK:nil variant:nil]];

	rygConfirmThen(title, ^{
		[RYGDownloadLedger guardKeyGroups:groups proceed:^{
			[self startBulkDownloadURLs:urls title:title username:username duplicateKeyGroups:groups done:done];
		}];
	});
}

+ (void)startBulkDownloadURLs:(NSArray<NSURL *> *)urls title:(NSString *)title username:(NSString *)username duplicateKeyGroups:(NSArray<NSArray<NSString *> *> *)groups done:(void(^)(NSArray<NSURL *> *fileURLs))done {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSString *stem = self.currentFilenameStem;
	NSMutableArray<NSURL *> *files = NSMutableArray.array;
	NSMutableArray<NSURLSessionDownloadTask *> *tasks = NSMutableArray.array;
	NSMutableIndexSet *succeeded = NSMutableIndexSet.indexSet;
	NSLock *lock = NSLock.new;
	__block BOOL cancelled = NO;
	__block NSUInteger completed = 0;
	__block RYGDownloadJob *job = nil;

	void (^start)(void) = ^{
		dispatch_group_t group = dispatch_group_create();
		NSUInteger total = urls.count;
		[center job:job didProgress:0.0f stage:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu"), 0UL, (unsigned long)total]];

		[urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, __unused BOOL *stop) {
			[lock lock]; BOOL shouldSkip = cancelled; [lock unlock];
			if (shouldSkip) return;

			dispatch_group_enter(group);

			NSString *ext = rygExt(url, @"jpg");
			NSString *name = [NSString stringWithFormat:@"%@_%lu", stem, (unsigned long)(idx + 1)];
			NSURL *dst = [RYGTempFiles claimNamedFile:[name stringByAppendingPathExtension:ext] ttl:900 tag:@"bulk"];

			NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *loc, __unused NSURLResponse *resp, NSError *err) {
				[lock lock]; BOOL wasCancelled = cancelled || err.code == NSURLErrorCancelled; [lock unlock];

				if (!err && loc && !wasCancelled) {
					[NSFileManager.defaultManager removeItemAtURL:dst error:nil];
					if ([NSFileManager.defaultManager moveItemAtURL:loc toURL:dst error:nil]) {
						[lock lock]; [files addObject:dst]; [succeeded addIndex:idx]; [lock unlock];
					}
				}

				[lock lock]; completed++; NSUInteger current = completed; [lock unlock];
				if (!wasCancelled)
					[center job:job didProgress:(float)current / (float)total
					        stage:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu"), (unsigned long)current, (unsigned long)total]];

				dispatch_group_leave(group);
			}];

			[lock lock]; [tasks addObject:task]; [lock unlock];
			[task resume];
		}];

		dispatch_group_notify(group, dispatch_get_main_queue(), ^{
			[lock lock]; BOOL wasCancelled = cancelled; [lock unlock];
			if (wasCancelled) { [center markJobCancelled:job]; return; }
			if (!files.count) { [center markJob:job failedWithError:nil]; return; }

			job.successText = [NSString stringWithFormat:RYGLocalized(@"Downloaded %lu items"), (unsigned long)files.count];
			// Only the children that actually landed, so a failed one isn't remembered as saved.
			NSMutableArray<NSString *> *keys = [NSMutableArray array];
			[succeeded enumerateIndexesUsingBlock:^(NSUInteger idx, __unused BOOL *s) {
				if (idx < groups.count) [keys addObjectsFromArray:groups[idx]];
			}];
			job.duplicateKeys = keys;
			[center markJobFinished:job];
			if (done) done(files.copy);
		});
	};

	job = [center enqueueJobWithTitle:(username.length ? [@"@" stringByAppendingString:username] : RYGLocalized(@"Carousel"))
	                             kind:RYGDownloadJobKindSimpleURL
	                            start:start
	                           cancel:^{
		[lock lock]; cancelled = YES; NSArray *snapshot = tasks.copy; [lock unlock];
		for (NSURLSessionDownloadTask *task in snapshot) [task cancel];
	}];
	job.itemCount = urls.count;
	job.subtitle = username.length
		? [NSString stringWithFormat:RYGLocalized(@"Carousel · %lu items"), (unsigned long)urls.count]
		: [NSString stringWithFormat:RYGLocalized(@"%lu items"), (unsigned long)urls.count];
}

+ (void)downloadAllChildrenOfMedia:(id)media progressTitle:(NSString *)title done:(void(^)(NSArray<NSURL *> *fileURLs))done {
	NSArray *children = [self carouselChildrenForMedia:media];
	if (!children.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No carousel children")];
		return;
	}

	NSArray<NSURL *> *urls = rygURLsForMedias(children);
	if (!urls.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not extract any URLs")];
		return;
	}

	[self bulkDownloadURLs:urls title:title username:rygUsernameForMedia(media) done:done];
}

+ (void)bulkSaveFiles:(NSArray<NSURL *> *)files {
	if (!files.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Nothing to save")];
		return;
	}

	NSString *galleryMode = [RYGUtils getStringPref:@"gallery_save_mode"];
	if ([galleryMode isEqualToString:@"gallery_only"]) {
		RYGGallerySaveMetadata *md = rygMakeGalleryMetadata(RYGGallerySourceOther, nil, YES);
		[self bulkSaveFilesToGallery:files perFileMetadata:nil defaultMetadata:md];
		return;
	}
	BOOL mirror = [galleryMode isEqualToString:@"mirror"];

	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSUInteger total = files.count;
	__block RYGDownloadJob *job = nil;

	void (^start)(void) = ^{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Photo library access denied")];
					[center markJob:job failedWithError:nil];
				});
				return;
			}

			BOOL useAlbum = [RYGUtils getBoolPref:@"save_to_ryukgram_album"];
			__block NSUInteger saved = 0;
			__block NSUInteger index = 0;
			__block void (^saveNext)(void) = nil;

			saveNext = ^{
				if (index >= total) {
					dispatch_async(dispatch_get_main_queue(), ^{
						job.successText = [NSString stringWithFormat:RYGLocalized(@"Saved %lu items"), (unsigned long)saved];
						[center markJobFinished:job];
					});
					saveNext = nil;
					return;
				}

				NSURL *file = files[index++];
				[center job:job didProgress:(float)index / (float)total
				        stage:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu"), (unsigned long)index, (unsigned long)total]];

				void (^step)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
					if (ok) saved++;
					if (saveNext) saveNext();
				};

				// Mirror: copy to gallery before the Photos save moves the file.
				if (mirror) {
					RYGGallerySaveMetadata *md = rygMakeGalleryMetadata(RYGGallerySourceOther, nil, YES);
					NSError *ge = nil;
					[RYGGalleryFile saveFileToGallery:file
											   source:RYGGallerySourceOther
											mediaType:(rygIsVideoURL(file) ? RYGGalleryMediaTypeVideo : RYGGalleryMediaTypeImage)
										   folderPath:nil
											 metadata:md
												error:&ge];
				}

				if (useAlbum) {
					[RYGPhotoAlbum saveFileToAlbum:file originalFilename:file.lastPathComponent completion:step];
					return;
				}

				rygSavePhotosAsset(file, (rygIsVideoURL(file) ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto), step);
			};

			saveNext();
		}];
	};

	job = [center enqueueJobWithTitle:RYGLocalized(@"Saving to Photos") kind:RYGDownloadJobKindSimpleURL start:start cancel:nil];
	job.itemCount = total;
	job.continuationPhase = YES;
	job.subtitle = [NSString stringWithFormat:RYGLocalized(@"%lu items"), (unsigned long)total];
}

+ (void)bulkSaveFilesToGallery:(NSArray<NSURL *> *)files perFileMetadata:(NSArray<RYGGallerySaveMetadata *> *)perFile defaultMetadata:(RYGGallerySaveMetadata *)defaultMetadata {
	if (!files.count) return;

	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	__block RYGDownloadJob *job = nil;
	void (^start)(void) = ^{
		[self _bulkGallerySaveStep:files index:0 success:0 perFileMetadata:perFile defaultMetadata:defaultMetadata job:job];
	};
	job = [center enqueueJobWithTitle:RYGLocalized(@"Saving to Gallery") kind:RYGDownloadJobKindSimpleURL start:start cancel:nil];
	job.itemCount = files.count;
	job.continuationPhase = YES;
	job.subtitle = [NSString stringWithFormat:RYGLocalized(@"%lu items"), (unsigned long)files.count];
}

+ (void)_bulkGallerySaveStep:(NSArray<NSURL *> *)files index:(NSUInteger)idx success:(NSUInteger)success perFileMetadata:(NSArray<RYGGallerySaveMetadata *> *)perFile defaultMetadata:(RYGGallerySaveMetadata *)defaultMetadata job:(RYGDownloadJob *)job {
	RYGDownloadCenter *center = [RYGDownloadCenter shared];
	NSUInteger total = files.count;
	if (idx >= total) {
		job.successText = [NSString stringWithFormat:RYGLocalized(@"Saved %lu items to Gallery"), (unsigned long)success];
		[center markJobFinished:job];
		return;
	}

	[center job:job didProgress:(float)idx / (float)total
	        stage:[NSString stringWithFormat:RYGLocalized(@"%lu of %lu"), (unsigned long)idx, (unsigned long)total]];

	NSURL *url = files[idx];
	RYGGallerySaveMetadata *m = (perFile && idx < perFile.count) ? perFile[idx] : defaultMetadata;
	NSError *error = nil;

	RYGGalleryFile *file = [RYGGalleryFile saveFileToGallery:url
													 source:(RYGGallerySource)m.source
												  mediaType:(rygIsVideoURL(url) ? RYGGalleryMediaTypeVideo : RYGGalleryMediaTypeImage)
												 folderPath:nil
												   metadata:m
													  error:&error];

	if (error) NSLog(@"[RyukGram][Gallery] Bulk save error: %@", error);

	dispatch_async(dispatch_get_main_queue(), ^{
		[self _bulkGallerySaveStep:files
							 index:idx + 1
						   success:success + ((file && !error) ? 1 : 0)
				   perFileMetadata:perFile
				   defaultMetadata:defaultMetadata
							   job:job];
	});
}

+ (void)downloadAllAndShareMedia:(id)carouselMedia {
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:RYGLocalized(@"Download all and share?") done:^(NSArray<NSURL *> *files) {
		if (!files.count) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Nothing to share")];
			return;
		}
		rygPresentActivity(files);
	}];
}

+ (void)downloadAllAndSaveMedia:(id)carouselMedia {
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:[NSString stringWithFormat:@"%@?", RYGLocalized(@"Save all to Photos")] done:^(NSArray<NSURL *> *files) {
		[self bulkSaveFiles:files];
	}];
}

+ (void)downloadAllAndSaveMediaToGallery:(id)carouselMedia context:(RYGActionContext)ctx {
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:[NSString stringWithFormat:@"%@?", RYGLocalized(@"Save all to Gallery")] done:^(NSArray<NSURL *> *files) {
		if (!files.count) {
			[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Nothing to save")];
			return;
		}

		RYGGallerySaveMetadata *metadata = rygMakeGalleryMetadata(rygGallerySourceFromContext(ctx), carouselMedia, YES);
		[self bulkSaveFilesToGallery:files perFileMetadata:nil defaultMetadata:metadata];
	}];
}

+ (void)copyAllURLsForMedia:(id)carouselMedia {
	NSArray *children = [self carouselChildrenForMedia:carouselMedia];
	if (!children.count) {
		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Not a carousel")];
		return;
	}

	rygCopyURLStrings(rygURLStringsForMedias(children));
}

#pragma mark - Discovery helpers

static UIView *rygFindSubviewOfClass(UIView *root, NSString *className, NSUInteger maxViews) {
	Class cls = NSClassFromString(className);
	if (!cls || !root) return nil;

	NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
	NSUInteger scanned = 0;

	while (queue.count && scanned++ < maxViews) {
		UIView *view = queue.firstObject;
		[queue removeObjectAtIndex:0];

		if ([view isKindOfClass:cls]) return view;
		for (UIView *sub in view.subviews) [queue addObject:sub];
	}

	return nil;
}

static NSArray *rygStoryReelMedias(UIView *sourceView) {
	if (!sourceView) return @[];

	UIViewController *storyVC = [RYGUtils nearestViewControllerForView:sourceView];
	if (!storyVC) {
		UIResponder *r = sourceView;
		while (r) {
			if ([NSStringFromClass(r.class) containsString:@"StoryViewer"]) {
				storyVC = (UIViewController *)r;
				break;
			}
			r = r.nextResponder;
		}
	}

	if (!storyVC) return @[];

	UIResponder *r = storyVC;
	Class viewerClass = NSClassFromString(@"IGStoryViewerViewController");
	while (r && !(viewerClass && [r isKindOfClass:viewerClass])) r = r.nextResponder;
	if (!r) r = (UIResponder *)storyVC;

	id vm = rygSendObj(r, @"currentViewModel");
	if (!vm) return @[];

	NSArray *items = nil;
	for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
		id val = rygSendObj(vm, sel);
		if ([val isKindOfClass:NSArray.class] && [(NSArray *)val count] > 1) {
			items = val;
			break;
		}
	}

	if (!items) {
		unsigned int count = 0;
		Ivar *ivars = class_copyIvarList(object_getClass(vm), &count);
		Class mediaClass = NSClassFromString(@"IGMedia");

		for (unsigned int i = 0; i < count; i++) {
			const char *type = ivar_getTypeEncoding(ivars[i]);
			if (!type || type[0] != '@') continue;

			id val = nil;
			@try { val = object_getIvar(vm, ivars[i]); }
			@catch (__unused id e) {}

			if (![val isKindOfClass:NSArray.class] || [(NSArray *)val count] <= 1) continue;

			id first = [(NSArray *)val firstObject];
			if ((mediaClass && [first isKindOfClass:mediaClass]) || [first respondsToSelector:@selector(media)]) {
				items = val;
				break;
			}
		}

		if (ivars) free(ivars);
	}

	if (items.count <= 1) return @[];

	NSMutableArray *medias = NSMutableArray.array;
	Class mediaClass = NSClassFromString(@"IGMedia");

	for (id item in items) {
		if (mediaClass && [item isKindOfClass:mediaClass]) {
			[medias addObject:item];
			continue;
		}

		for (NSString *sel in @[@"media", @"storyItem", @"item", @"mediaItem"]) {
			id media = rygSendObj(item, sel);
			if (media && mediaClass && [media isKindOfClass:mediaClass]) {
				[medias addObject:media];
				break;
			}
		}
	}

	return medias.count > 1 ? medias.copy : @[];
}

static id rygCarouselParentMedia(id media, UIView *sourceView) {
	if (!media || [RYGMediaActions isCarouselMedia:media]) return media;

	for (UIView *v = sourceView; v; v = v.superview) {
		id stashed = objc_getAssociatedObject(v, kRYGCarouselParentMediaKey);
		if (stashed && [RYGMediaActions isCarouselMedia:stashed]) return stashed;

		id passthrough = rygIvar(v, "_mediaPassthrough");
		if (passthrough && [RYGMediaActions isCarouselMedia:passthrough]) return passthrough;
	}

	UICollectionViewCell *ufiCell = nil;
	UICollectionView *collectionView = nil;

	for (UIView *v = sourceView; v; v = v.superview) {
		if (!ufiCell && [v isKindOfClass:UICollectionViewCell.class]) ufiCell = (UICollectionViewCell *)v;
		if ([v isKindOfClass:UICollectionView.class]) {
			collectionView = (UICollectionView *)v;
			break;
		}
	}

	NSIndexPath *ufiPath = ufiCell ? [collectionView indexPathForCell:ufiCell] : nil;
	if (!ufiPath) return media;

	Class mediaClass = NSClassFromString(@"IGMedia");

	for (UICollectionViewCell *cell in collectionView.visibleCells) {
		NSIndexPath *path = [collectionView indexPathForCell:cell];
		if (!path || path.section != ufiPath.section || cell == ufiCell) continue;
		if (![NSStringFromClass(cell.class) containsString:@"Page"]) continue;

		id parent = rygIvar(cell, "_media");
		if (parent && mediaClass && [parent isKindOfClass:mediaClass] && [RYGMediaActions isCarouselMedia:parent]) return parent;
	}

	return media;
}

#pragma mark - Repost / Settings

+ (void)triggerRepostForContext:(RYGActionContext)ctx sourceView:(UIView *)sourceView {
	if (ctx == RYGActionContextReels) {
		Class cellClass = NSClassFromString(@"IGSundialViewerVideoCell") ?: NSClassFromString(@"IGSundialViewerPhotoView");
		UIView *cell = sourceView;

		while (cell && cellClass && ![cell isKindOfClass:cellClass]) cell = cell.superview;

		UIView *ufi = cell ? rygFindSubviewOfClass(cell, @"_TtC26IGSundialViewerVerticalUFI26IGSundialViewerVerticalUFI", 200) : nil;
		if (ufi) {
			SEL noArg = NSSelectorFromString(@"didTapRepostButton");
			SEL oldNoArg = NSSelectorFromString(@"_didTapRepostButton");

			if ([ufi respondsToSelector:noArg]) {
				((void(*)(id, SEL))objc_msgSend)(ufi, noArg);
				return;
			}

			if ([ufi respondsToSelector:oldNoArg]) {
				((void(*)(id, SEL))objc_msgSend)(ufi, oldNoArg);
				return;
			}
		}

		[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Repost unavailable")];
		return;
	}

	UIResponder *r = sourceView;
	Class feedCell = NSClassFromString(@"IGFeedItemUFICell");

	while (r) {
		if (feedCell && [r isKindOfClass:feedCell]) break;
		r = r.nextResponder;
	}

	SEL sel = @selector(UFIButtonBarDidTapOnRepost:);
	if (r && [r respondsToSelector:sel]) {
		((void(*)(id, SEL, id))objc_msgSend)(r, sel, nil);
		return;
	}

	[RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Repost unavailable")];
}

+ (void)openSettingsForContext:(RYGActionContext)ctx fromView:(UIView *)sourceView {
	UIWindow *window = sourceView.window ?: UIApplication.sharedApplication.keyWindow;

	if (!window) {
		for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
			if (![scene isKindOfClass:UIWindowScene.class]) continue;
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				if (w.isKeyWindow) {
					window = w;
					break;
				}
			}
			if (window) break;
		}
	}

	if (window) [RYGUtils showSettingsVC:window atTopLevelEntry:rygSettingsTitleForContext(ctx)];
}

#pragma mark - Menu builder

+ (NSArray<RYGAction *> *)actionsForContext:(RYGActionContext)ctx media:(id)media fromView:(UIView *)sourceView {
	return [self actionsForContext:ctx media:media fromView:sourceView includeDisabled:NO];
}

+ (NSArray<RYGAction *> *)actionsForContext:(RYGActionContext)ctx media:(id)media fromView:(UIView *)sourceView includeDisabled:(BOOL)includeDisabled {
	RYGActionMenuConfig *config = [RYGActionMenuConfig configForSource:rygSourceFromContext(ctx)];
	NSString *dateHeader = config.showDate ? rygFormatDateHeader(rygExtractDateFromMedia(media)) : nil;
	NSString *ctxLabel = [self contextLabelForContext:ctx];

	[self prefetchProgressiveVideoURLForMedia:media];

	id parentMedia = rygCarouselParentMedia(media, sourceView);
	BOOL isCarousel = parentMedia && [self isCarouselMedia:parentMedia];
	NSString *caption = parentMedia ? [self captionForMedia:parentMedia] : nil;
	NSArray *storyMedias = (ctx == RYGActionContextStories && !isCarousel) ? rygStoryReelMedias(sourceView) : @[];
	BOOL hasBulk = isCarousel || storyMedias.count > 1;
	__weak UIView *weakSource = sourceView;

	__weak id weakParent = parentMedia;
	void (^stamp)(id) = ^(id targetMedia) {
		// Carousel children carry no user info — populate from the parent first, then layer the child's identifiers on top.
		id parent = weakParent;
		RYGGallerySaveMetadata *m = rygMakeGalleryMetadata(rygGallerySourceFromContext(ctx),
		                                                   (parent && parent != targetMedia) ? parent : nil, NO);
		@try { [RYGGalleryOriginController populateMetadata:m fromMedia:targetMedia]; }
		@catch (__unused id e) {}
		m.contextLabel = ctxLabel;
		rygSetPendingMetadata(m);
	};

	RYGAction *(^resolve)(NSString *) = ^RYGAction *(NSString *aid) {
		if ([aid isEqualToString:RYGAID_Expand]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Expand") icon:@"bcn_arrow-expand_outline_24" handler:^{
				if (isCarousel) {
					NSArray *children = [RYGMediaActions carouselChildrenForMedia:parentMedia];
					NSArray<RYGMediaViewerItem *> *items = rygViewerItemsForChildren(children, caption);

					NSUInteger start = 0;
					if (media != parentMedia) {
						NSUInteger idx = [children indexOfObjectIdenticalTo:media];
						if (idx != NSNotFound) start = idx;
					}

					if (items.count) [RYGMediaViewer showItems:items startIndex:start];
					else [RYGMediaActions expandMedia:media fromView:weakSource caption:caption];
					return;
				}

				[RYGMediaActions expandMedia:media fromView:weakSource caption:caption];
			}];
		}

		if ([aid isEqualToString:RYGAID_ViewCover]) {
			BOOL hasCover = ctx == RYGActionContextReels || (ctx == RYGActionContextFeed && [RYGUtils getVideoUrlForMedia:(IGMedia *)media]);
			if (!hasCover) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"View cover") icon:@"bcn_image_outline_24" handler:^{
				NSURL *cover = [RYGMediaActions coverURLForMedia:media];
				if (cover) [RYGMediaViewer showWithVideoURL:nil photoURL:cover caption:nil];
				else [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"No cover image")];
			}];
		}

		if ([aid isEqualToString:RYGAID_Repost]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Repost") icon:@"bcn_repost-squircle_outline_24" handler:^{
				[RYGRepostSheet repostWithVideoURL:[RYGUtils getVideoUrlForMedia:(IGMedia *)media] photoURL:[RYGUtils getPhotoUrlForMedia:(IGMedia *)media]];
			}];
		}

		if ([aid isEqualToString:RYGAID_ViewMentions]) {
			if (ctx != RYGActionContextStories || ![RYGUtils getBoolPref:@"view_story_mentions"]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"View mentions") icon:@"at" handler:^{
				UIViewController *host = [RYGUtils nearestViewControllerForView:weakSource];
				if (host) rygShowStoryMentions(host, weakSource);
			}];
		}

		if ([aid isEqualToString:RYGAID_ToggleAudio]) {
			if (ctx != RYGActionContextStories || ![RYGUtils getBoolPref:@"story_audio_toggle"]) return nil;

			BOOL on = rygIsStoryAudioEnabled();
			return [RYGAction actionWithTitle:(on ? RYGLocalized(@"Mute audio") : RYGLocalized(@"Unmute audio"))
										 icon:(on ? @"speaker.wave.2" : @"speaker.slash")
									  handler:^{ rygToggleStoryAudio(); }];
		}

		if ([aid isEqualToString:RYGAID_ExcludeUser]) {
			if (ctx != RYGActionContextStories || ![RYGUtils getBoolPref:@"enable_story_user_exclusions"]) return nil;

			extern NSDictionary *rygOwnerInfoForView(UIView *);
			extern void rygRefreshAllVisibleOverlays(UIViewController *);
			extern __weak UIViewController *rygActiveStoryViewerVC;

			NSDictionary *info = weakSource ? rygOwnerInfoForView(weakSource) : nil;
			NSString *pk = info[@"pk"];
			if (!pk.length) return nil;

			BOOL inList = [RYGExcludedStoryUsers isInList:pk];
			BOOL blockMode = [RYGExcludedStoryUsers isBlockSelectedMode];

			NSString *title = inList
				? (blockMode ? RYGLocalized(@"Remove from block list") : RYGLocalized(@"Remove from exclude list"))
				: (blockMode ? RYGLocalized(@"Add to block list") : RYGLocalized(@"Exclude from seen"));

			NSString *capturedPK = pk.copy;
			NSString *capturedUser = [info[@"username"] ?: @"" copy];
			NSString *capturedName = [info[@"fullName"] ?: @"" copy];

			return [RYGAction actionWithTitle:title icon:(inList ? @"ig_icon_eye_filled_24" : @"ig_icon_eye_off_pano_outline_24") handler:^{
				if (inList) {
					[RYGExcludedStoryUsers removePK:capturedPK];
					RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY, blockMode ? RYGLocalized(@"Unblocked") : RYGLocalized(@"Removed from list"), nil);
				} else {
					[RYGExcludedStoryUsers addOrUpdateEntry:@{@"pk": capturedPK, @"username": capturedUser, @"fullName": capturedName}];
					RYGNotifySuccess(blockMode ? RYG_NOTIF_BLOCK_TOGGLE : RYG_NOTIF_EXCLUDE_STORY, blockMode ? RYGLocalized(@"Added to block list") : RYGLocalized(@"Added to exclude list"), nil);
				}
				rygRefreshAllVisibleOverlays(rygActiveStoryViewerVC);
			}];
		}

		if ([aid isEqualToString:RYGAID_CopyCaption]) {
			if (ctx == RYGActionContextStories) return nil;
			return [RYGAction actionWithTitle:RYGLocalized(@"Copy caption") icon:@"ig_icon_closed_captions_enabled_outline_24" handler:^{
				[RYGMediaActions copyCaptionForMedia:parentMedia];
			}];
		}

		if ([aid isEqualToString:RYGAID_CopyURL]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Copy media URL") icon:@"bcn_copy_outline_24" handler:^{
				[RYGMediaActions copyURLForMedia:media];
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadShare]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Download and share") icon:@"square.and.arrow.up" handler:^{
				stamp(media);
				[RYGMediaActions downloadAndShareMedia:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadSave]) {
			return [RYGAction actionWithTitle:RYGLocalized(@"Download to Photos") icon:@"square.and.arrow.down" handler:^{
				stamp(media);
				[RYGMediaActions downloadAndSaveMedia:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadWithMusic]) {
			if ([RYGMediaActions mediaIsVideo:media]) return nil;
			if (![RYGMediaActions mediaHasMusic:media parentMedia:parentMedia]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Save with music") icon:@"ig_icon_music_import_outline_24" handler:^{
				stamp(media);
				rygConfirmThen(RYGLocalized(@"Save with music"), ^{
					[RYGMediaActions downloadPhotoWithMusicForMedia:media parentMedia:parentMedia action:saveToPhotos];
				});
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadWithMusicGallery]) {
			if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;
			if ([RYGMediaActions mediaIsVideo:media]) return nil;
			if (![RYGMediaActions mediaHasMusic:media parentMedia:parentMedia]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Gallery with music") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
				stamp(media);
				rygConfirmThen(RYGLocalized(@"Gallery with music"), ^{
					[RYGMediaActions downloadPhotoWithMusicForMedia:media parentMedia:parentMedia action:saveToGallery];
				});
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadImageOnly]) {
			if (![RYGMediaActions mediaIsStillImageWithAudio:media parentMedia:parentMedia]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Save image (no music)") icon:@"bcn_image_outline_24" handler:^{
				stamp(media);
				[RYGMediaActions downloadPhotoOnlyForMedia:media action:saveToPhotos];
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadImageOnlyGallery]) {
			if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;
			if (![RYGMediaActions mediaIsStillImageWithAudio:media parentMedia:parentMedia]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Gallery image (no music)") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
				stamp(media);
				[RYGMediaActions downloadPhotoOnlyForMedia:media action:saveToGallery];
			}];
		}

		if ([aid isEqualToString:RYGAID_DownloadGallery]) {
			if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Download to Gallery") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
				stamp(media);
				[RYGMediaActions downloadAndSaveMediaToGallery:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:RYGAID_BulkCopyURLs]) {
			if (!hasBulk) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Copy all URLs") icon:@"bcn_copy_outline_24" handler:^{
				NSArray<NSString *> *urls = rygURLStringsForMedias(isCarousel ? [RYGMediaActions carouselChildrenForMedia:parentMedia] : storyMedias);
				rygCopyURLStrings(urls);
			}];
		}

		if ([aid isEqualToString:RYGAID_BulkDownloadShare]) {
			if (!hasBulk) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Download and share all") icon:@"square.and.arrow.up.on.square" handler:^{
				if (isCarousel) {
					stamp(parentMedia);
					[RYGMediaActions downloadAllAndShareMedia:parentMedia];
					return;
				}

				stamp(storyMedias.firstObject);
				[RYGMediaActions bulkDownloadURLs:rygURLsForMedias(storyMedias) title:RYGLocalized(@"Download all stories and share?") username:rygUsernameForMedia(storyMedias.firstObject) done:^(NSArray<NSURL *> *files) {
					rygPresentActivity(files);
				}];
			}];
		}

		if ([aid isEqualToString:RYGAID_BulkDownloadSave]) {
			if (!hasBulk) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Download all to Photos") icon:@"square.and.arrow.down.on.square" handler:^{
				if (isCarousel) {
					stamp(parentMedia);
					[RYGMediaActions downloadAllAndSaveMedia:parentMedia];
					return;
				}

				stamp(storyMedias.firstObject);
				[RYGMediaActions bulkDownloadURLs:rygURLsForMedias(storyMedias) title:RYGLocalized(@"Download all to Photos") username:rygUsernameForMedia(storyMedias.firstObject) done:^(NSArray<NSURL *> *files) {
					[RYGMediaActions bulkSaveFiles:files];
				}];
			}];
		}

		if ([aid isEqualToString:RYGAID_BulkDownloadGallery]) {
			if (!hasBulk || ![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;

			return [RYGAction actionWithTitle:RYGLocalized(@"Download all to Gallery") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
				if (isCarousel) {
					stamp(parentMedia);
					[RYGMediaActions downloadAllAndSaveMediaToGallery:parentMedia context:ctx];
					return;
				}

				NSArray *medias = storyMedias;
				stamp(medias.firstObject);
				[RYGMediaActions bulkDownloadURLs:rygURLsForMedias(medias) title:RYGLocalized(@"Download all to Gallery") username:rygUsernameForMedia(medias.firstObject) done:^(NSArray<NSURL *> *files) {
					if (!files.count) return;

					NSMutableArray<RYGGallerySaveMetadata *> *metadata = [NSMutableArray arrayWithCapacity:files.count];
					for (NSUInteger i = 0; i < files.count; i++) {
						RYGGallerySaveMetadata *m = rygMakeGalleryMetadata(rygGallerySourceFromContext(ctx),
						                                       (i < medias.count ? medias[i] : nil), YES);
						m.contextLabel = ctxLabel;
						m.sequenceIndex = (NSInteger)(i + 1);
						[metadata addObject:m];
					}

					[RYGMediaActions bulkSaveFilesToGallery:files perFileMetadata:metadata defaultMetadata:metadata.firstObject];
				}];
			}];
		}

		if ([aid isEqualToString:RYGAID_Settings]) {
			return [RYGAction actionWithTitle:[NSString stringWithFormat:RYGLocalized(@"%@ settings"), rygSettingsTitleForContext(ctx)]
										 icon:@"ig_icon_settings_outline_24"
									  handler:^{
				[RYGMediaActions openSettingsForContext:ctx fromView:weakSource];
			}];
		}

		return nil;
	};

	NSArray<RYGAction *> *items = [RYGActionMenu actionsForConfig:config dateHeader:dateHeader resolver:resolve includeDisabled:includeDisabled];

	if (hasBulk) {
		NSUInteger bulkCount = isCarousel ? [self carouselChildrenForMedia:parentMedia].count : storyMedias.count;
		if (bulkCount > 1) {
			NSMutableArray<RYGAction *> *patched = [items mutableCopy];
			for (NSUInteger i = 0; i < patched.count; i++) {
				RYGAction *group = patched[i];
				if (!group.children.count) continue;
				BOOL isBulkGroup = NO;
				for (RYGAction *child in group.children) {
					if ([child.actionID hasPrefix:@"bulk_"]) { isBulkGroup = YES; break; }
				}
				if (!isBulkGroup) continue;
				NSString *title = [NSString stringWithFormat:@"%@ (%lu)", group.title, (unsigned long)bulkCount];
				patched[i] = [RYGAction actionWithTitle:title icon:group.systemIconName children:group.children];
				break;
			}
			items = patched;
		}
	}

	return items;
}

static BOOL rygFireActionWithIDInList(NSArray<RYGAction *> *items, NSString *aid) {
	for (RYGAction *action in items) {
		if (action.isSeparator) continue;
		if (action.children.count && rygFireActionWithIDInList(action.children, aid)) return YES;
		if (action.actionID.length && [action.actionID isEqualToString:aid] && action.handler) {
			action.handler();
			return YES;
		}
	}
	return NO;
}

+ (BOOL)executeActionForContext:(RYGActionContext)ctx actionID:(NSString *)aid media:(id)media fromView:(UIView *)sourceView {
	if (!aid.length || [aid isEqualToString:@"menu"]) return NO;
	return rygFireActionWithIDInList([self actionsForContext:ctx media:media fromView:sourceView includeDisabled:YES], aid);
}

@end