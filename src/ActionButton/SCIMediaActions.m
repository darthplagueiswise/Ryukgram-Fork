#import "SCIMediaActions.h"
#import "SCIMediaViewer.h"
#import "SCIRepostSheet.h"
#import "SCIActionMenuConfig.h"
#import "SCIActionCatalog.h"
#import "../SCIDashParser.h"
#import "../SCIFFmpeg.h"
#import "../SCIQualityPicker.h"
#import "../Utils.h"
#import "../Downloader/Download.h"
#import "../Downloader/SCIDownloadCenter.h"
#import "../PhotoAlbum.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../Gallery/SCIGalleryOriginController.h"
#import "../Features/StoriesAndMessages/SCIExcludedStoryUsers.h"
#import "../Features/StoriesAndMessages/OverlayHelpers.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

// Stamp/consume serialized — bulk actions queue several in quick succession.
static SCIGallerySaveMetadata *sciPendingGalleryMetadata = nil;
static NSString *sciCurrentFilenameStem = nil;

static dispatch_queue_t sciPendingMetadataQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.ryukgram.pendingmeta", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static void sciSetPendingMetadata(SCIGallerySaveMetadata *m) {
    dispatch_sync(sciPendingMetadataQueue(), ^{ sciPendingGalleryMetadata = m; });
}

static SCIGallerySaveMetadata *sciConsumePendingMetadata(void) {
    __block SCIGallerySaveMetadata *m = nil;
    dispatch_sync(sciPendingMetadataQueue(), ^{
        m = sciPendingGalleryMetadata;
        sciPendingGalleryMetadata = nil;
    });
    return m;
}

extern void sciToggleStoryAudio(void);
extern BOOL sciIsStoryAudioEnabled(void);

#pragma mark - Small helpers

static SCIGallerySource sciGallerySourceFromContext(SCIActionContext ctx) {
	switch (ctx) {
		case SCIActionContextFeed: return SCIGallerySourceFeed;
		case SCIActionContextReels: return SCIGallerySourceReels;
		case SCIActionContextStories: return SCIGallerySourceStories;
	}
	return SCIGallerySourceOther;
}

static SCIActionSource sciSourceFromContext(SCIActionContext ctx) {
	switch (ctx) {
		case SCIActionContextFeed: return SCIActionSourceFeed;
		case SCIActionContextReels: return SCIActionSourceReels;
		case SCIActionContextStories: return SCIActionSourceStories;
	}
	return SCIActionSourceFeed;
}

static NSString *sciSettingsTitleForContext(SCIActionContext ctx) {
	switch (ctx) {
		case SCIActionContextFeed: return SCILocalized(@"Feed");
		case SCIActionContextReels: return SCILocalized(@"Reels");
		case SCIActionContextStories: return SCILocalized(@"Stories");
	}
	return SCILocalized(@"General");
}

static NSString *sciDatePrefKeyForContext(SCIActionContext ctx) {
	switch (ctx) {
		case SCIActionContextFeed: return @"menu_date_feed";
		case SCIActionContextReels: return @"menu_date_reels";
		case SCIActionContextStories: return @"menu_date_stories";
	}
	return nil;
}

static id sciSendObj(id obj, NSString *selName) {
	if (!obj || !selName.length) return nil;
	SEL sel = NSSelectorFromString(selName);
	if (![obj respondsToSelector:sel]) return nil;
	@try { return ((id(*)(id, SEL))objc_msgSend)(obj, sel); }
	@catch (__unused id e) { return nil; }
}

static id sciKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try { return [obj valueForKey:key]; }
	@catch (__unused id e) { return nil; }
}

static id sciIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
	if (!ivar) ivar = class_getInstanceVariable([obj class], name);
	if (!ivar) return nil;
	@try { return object_getIvar(obj, ivar); }
	@catch (__unused id e) { return nil; }
}

static NSDictionary *sciMediaFieldCache(id obj) {
	if (!obj) return nil;
	if ([obj isKindOfClass:NSDictionary.class]) return obj;

	Class storable = NSClassFromString(@"IGAPIStorableObject");
	if (storable && ![obj isKindOfClass:storable]) return nil;

	id value = sciIvar(obj, "_fieldCache");
	return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static id sciFieldCache(id obj, NSString *key) {
	id value = sciMediaFieldCache(obj)[key];
	return (!value || [value isKindOfClass:NSNull.class]) ? nil : value;
}

static NSString *sciStringValue(id value) {
	if (!value || [value isKindOfClass:NSNull.class]) return nil;
	if ([value isKindOfClass:NSString.class]) return [(NSString *)value length] ? value : nil;
	if ([value respondsToSelector:@selector(stringValue)]) {
		NSString *s = [value stringValue];
		return s.length ? s : nil;
	}
	NSString *s = [value description];
	return s.length ? s : nil;
}

static NSString *sciStringFromObject(id obj, NSString *key) {
	return sciStringValue(sciSendObj(obj, key) ?: sciKVC(obj, key) ?: sciFieldCache(obj, key));
}

static NSURL *sciURLFromString(NSString *s) {
	return s.length ? [NSURL URLWithString:s] : nil;
}

static NSString *sciSanitizeFilenameComponent(NSString *s) {
	if (!s.length) return @"";
	NSMutableCharacterSet *allowed = [NSMutableCharacterSet alphanumericCharacterSet];
	[allowed addCharactersInString:@"._-"];
	NSString *out = [[s componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@""];
	return out.length > 30 ? [out substringToIndex:30] : out;
}

static NSString *sciUsernameForMedia(id media) {
	id user = sciSendObj(media, @"user") ?: sciKVC(media, @"user") ?: sciFieldCache(media, @"user");
	NSString *username = sciStringFromObject(user, @"username");
	if (!username.length && [user isKindOfClass:NSDictionary.class]) username = ((NSDictionary *)user)[@"username"];
	return username.length ? username : nil;
}

static void sciConfirmThen(NSString *title, void(^block)(void)) {
	if (!block) return;
	if ([SCIUtils getBoolPref:@"dw_confirm"]) [SCIUtils showConfirmation:block title:title];
	else block();
}

static SCIDownloadDelegate *sciMakeDownloader(DownloadAction action, BOOL progress) {
	SCIDownloadDelegate *d = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:progress];
	SCIGallerySaveMetadata *m = sciConsumePendingMetadata();
	if (m) d.pendingGallerySaveMetadata = m;
	return d;
}

static SCIGallerySaveMetadata *sciMakeGalleryMetadata(SCIGallerySource source, id media, BOOL skipDedup) {
	SCIGallerySaveMetadata *m = SCIGallerySaveMetadata.new;
	m.source = (int16_t)source;
	m.skipDedup = skipDedup;
	if (media) {
		@try { [SCIGalleryOriginController populateMetadata:m fromMedia:media]; }
		@catch (__unused id e) {}
	}
	return m;
}

static void sciStampGalleryMetadataForMedia(id media, SCIActionContext ctx) {
	sciSetPendingMetadata(sciMakeGalleryMetadata(sciGallerySourceFromContext(ctx), media, NO));
}

static NSTimeInterval sciCoerceTimestamp(id value) {
	double d = 0.0;
	if ([value isKindOfClass:NSNumber.class]) d = [value doubleValue];
	else if ([value isKindOfClass:NSString.class]) d = [(NSString *)value doubleValue];
	if (d <= 0.0) return 0.0;
	if (d > 1e15) d /= 1e6;
	else if (d > 1e12) d /= 1e3;
	return d;
}

static NSDate *sciExtractDateFromMedia(id media) {
	NSDictionary *fc = sciMediaFieldCache(media);
	if (!fc) return nil;

	for (NSString *key in @[@"taken_at", @"device_timestamp", @"created_at", @"upload_time", @"published_time"]) {
		NSTimeInterval t = sciCoerceTimestamp(fc[key]);
		if (t > 0.0) return [NSDate dateWithTimeIntervalSince1970:t];
	}
	return nil;
}

static NSString *sciFormatDateHeader(NSDate *date) {
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

static BOOL sciIsVideoURL(NSURL *url) {
	NSString *ext = url.pathExtension.lowercaseString;
	return [@[@"mp4", @"mov", @"m4v", @"webm"] containsObject:ext];
}

static void sciPresentActivity(NSArray *items) {
	if (!items.count) return;

	UIViewController *top = topMostController();
	UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];

	if (is_iPad()) {
		vc.popoverPresentationController.sourceView = top.view;
		vc.popoverPresentationController.sourceRect = CGRectMake(top.view.bounds.size.width / 2.0, top.view.bounds.size.height / 2.0, 1.0, 1.0);
	}

	[SCIPhotoAlbum armWatcherIfEnabled];
	[top presentViewController:vc animated:YES completion:nil];
}

static NSArray<NSURL *> *sciURLsForMedias(NSArray *medias) {
	NSMutableArray<NSURL *> *urls = NSMutableArray.array;
	for (id media in medias) {
		NSURL *url = [SCIMediaActions bestURLForMedia:media];
		if (url) [urls addObject:url];
	}
	return urls.copy;
}

#pragma mark - Download helpers

// Read the pending metadata without consuming it (for download-manager labels).
static SCIGallerySaveMetadata *sciPeekPendingMetadata(void) {
	__block SCIGallerySaveMetadata *m = nil;
	dispatch_sync(sciPendingMetadataQueue(), ^{ m = sciPendingGalleryMetadata; });
	return m;
}

static SCIGalleryFile *sciSaveFileToGalleryURL(NSURL *url, SCIGalleryMediaType type, NSError **error) {
	SCIGallerySaveMetadata *m = sciConsumePendingMetadata();
	SCIGallerySource source = m ? (SCIGallerySource)m.source : SCIGallerySourceOther;

	return [SCIGalleryFile saveFileToGallery:url source:source mediaType:type folderPath:nil metadata:m error:error];
}

#pragma mark - Shared helpers (refactor)

static NSString *sciExt(NSURL *url, NSString *fallback) {
	return url.pathExtension.length ? url.pathExtension : fallback;
}

static NSArray<NSString *> *sciURLStringsForMedias(NSArray *medias) {
	NSMutableArray<NSString *> *out = NSMutableArray.array;
	for (NSURL *u in sciURLsForMedias(medias)) [out addObject:u.absoluteString];
	return out.copy;
}

static void sciCopyURLStrings(NSArray<NSString *> *urls) {
	if (!urls.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No URLs found")];
		return;
	}
	UIPasteboard.generalPasteboard.string = [urls componentsJoinedByString:@"\n"];
	SCINotifySuccess(SCI_NOTIF_COPY_URL, [NSString stringWithFormat:SCILocalized(@"Copied %lu URLs"), (unsigned long)urls.count], nil);
}

static void sciSavePhotosAsset(NSURL *url, PHAssetResourceType type, void(^completion)(BOOL success, NSError *error)) {
	[PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
		PHAssetCreationRequest *req = PHAssetCreationRequest.creationRequestForAsset;
		PHAssetResourceCreationOptions *opts = PHAssetResourceCreationOptions.new;
		opts.shouldMoveFile = YES;
		[req addResourceWithType:type fileURL:url options:opts];
	} completionHandler:completion];
}

static void sciFinishJobWithGallerySave(SCIDownloadJob *job, NSURL *url, SCIGalleryMediaType type) {
	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSError *error = nil;
	SCIGalleryFile *file = sciSaveFileToGalleryURL(url, type, &error);
	if (file && !error) {
		job.successText = SCILocalized(@"Saved to Gallery");
		[center markJobFinished:job];
	} else {
		[center markJob:job failedWithError:error];
	}
}

static NSArray<SCIMediaViewerItem *> *sciViewerItemsForChildren(NSArray *children, NSString *caption) {
	NSMutableArray<SCIMediaViewerItem *> *items = NSMutableArray.array;
	for (id child in children) {
		NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)child];
		NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)child] ?: (!v ? [SCIMediaActions bestURLForMedia:child] : nil);
		if (v || p) [items addObject:[SCIMediaViewerItem itemWithVideoURL:v photoURL:p caption:caption]];
	}
	return items;
}

static void sciSaveVideoToPhotosURLForJob(NSURL *url, SCIDownloadJob *job) {
	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
		if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
				[center markJob:job failedWithError:nil];
			});
			return;
		}

		BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
		void (^done)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (ok) {
					job.successText = useAlbum ? SCILocalized(@"Saved to RyukGram") : SCILocalized(@"Saved to Photos");
					[center markJobFinished:job];
				} else {
					[center markJob:job failedWithError:error];
				}
			});
		};

		if (useAlbum) {
			[SCIPhotoAlbum saveFileToAlbum:url completion:^(BOOL ok, NSError *error) {
				[NSFileManager.defaultManager removeItemAtURL:url error:nil];
				done(ok, error);
			}];
			return;
		}

		sciSavePhotosAsset(url, PHAssetResourceTypeVideo, done);
	}];
}

@implementation SCIMediaActions

#pragma mark - Filename

+ (NSString *)contextLabelForContext:(SCIActionContext)ctx {
	switch (ctx) {
		case SCIActionContextFeed: return @"feed";
		case SCIActionContextReels: return @"reels";
		case SCIActionContextStories: return @"stories";
	}
	return @"media";
}

+ (NSString *)filenameStemForMedia:(id)media contextLabel:(NSString *)ctxLabel {
	return [self filenameStemForUsername:sciUsernameForMedia(media) contextLabel:ctxLabel];
}

+ (NSString *)filenameStemForUsername:(NSString *)username contextLabel:(NSString *)ctxLabel {
	NSString *user = sciSanitizeFilenameComponent(username);
	NSString *ctx = sciSanitizeFilenameComponent(ctxLabel);
	if (!user.length) user = @"media";
	if (!ctx.length) ctx = @"media";

	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = NSDateFormatter.new;
		fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt.dateFormat = @"yyyyMMdd_HHmmss";
	});

	return [NSString stringWithFormat:@"%@%@_%@_%@", username.length ? @"@" : @"", user, ctx, [fmt stringFromDate:NSDate.date]];
}

+ (NSString *)currentFilenameStem {
	return sciCurrentFilenameStem;
}

+ (void)setCurrentFilenameStem:(NSString *)stem {
	sciCurrentFilenameStem = stem.copy;
}

#pragma mark - Media extraction

+ (NSString *)captionForMedia:(id)media {
	if (!media) return nil;

	for (NSString *sel in @[@"fullCaptionString", @"captionString", @"caption", @"captionText", @"text"]) {
		id value = sciSendObj(media, sel);
		if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) return value;

		for (NSString *textSel in @[@"text", @"string", @"commentText", @"rawText"]) {
			id text = sciSendObj(value, textSel);
			if ([text respondsToSelector:@selector(string)] && ![text isKindOfClass:NSString.class]) text = sciSendObj(text, @"string");
			if ([text isKindOfClass:NSString.class] && [(NSString *)text length]) return text;
		}

		id fcText = sciFieldCache(value, @"text");
		if ([fcText isKindOfClass:NSString.class] && [(NSString *)fcText length]) return fcText;
	}

	id cap = sciFieldCache(media, @"caption");
	if ([cap isKindOfClass:NSDictionary.class]) {
		NSString *text = ((NSDictionary *)cap)[@"text"];
		if (text.length) return text;
	} else if ([cap isKindOfClass:NSString.class] && [(NSString *)cap length]) {
		return cap;
	}

	NSString *text = sciStringFromObject(cap, @"text") ?: sciStringFromObject(cap, @"string");
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

		NSString *out = [val isKindOfClass:NSString.class] ? val : (sciStringFromObject(val, @"text") ?: sciStringFromObject(val, @"string"));
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
		id value = sciSendObj(media, sel);
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return value;
	}

	for (NSString *ivarName in @[@"_carouselMedia", @"_carouselChildren"]) {
		id value = sciIvar(media, ivarName.UTF8String);
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return value;
	}

	id fc = sciFieldCache(media, @"carousel_media");
	return [fc isKindOfClass:NSArray.class] ? fc : @[];
}

static const void *kSCICarouselParentMediaKey = &kSCICarouselParentMediaKey;

+ (void)stashCarouselParentMedia:(id)parent onView:(UIView *)view {
	if (!view) return;
	objc_setAssociatedObject(view, kSCICarouselParentMediaKey, parent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (BOOL)mediaHasAudio:(id)media {
	if (!media) return NO;

	id hasAudio = sciFieldCache(media, @"has_audio");
	if ([hasAudio respondsToSelector:@selector(boolValue)] && [hasAudio boolValue]) return YES;

	id video = sciSendObj(media, @"video");
	id detected = sciSendObj(video, @"isAudioDetected");
	if ([detected respondsToSelector:@selector(boolValue)] && [detected boolValue]) return YES;

	for (NSString *key in @[@"music_metadata", @"story_music_stickers", @"is_story_image_with_music", @"story_sound_on", @"spotify_stickers", @"story_music_lyric_stickers"]) {
		id value = sciFieldCache(media, key);
		if (!value || [value isKindOfClass:NSNull.class]) continue;
		if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) return YES;
		if ([value isKindOfClass:NSArray.class] && [(NSArray *)value count]) return YES;
		if ([value isKindOfClass:NSDictionary.class] && [(NSDictionary *)value count]) return YES;
	}

	return [SCIDashParser dashManifestForMedia:media].length > 0;
}

+ (NSURL *)fieldCachePhotoURLForMedia:(id)media {
	id candidates = nil;
	id iv2 = sciFieldCache(media, @"image_versions2");
	if ([iv2 isKindOfClass:NSDictionary.class]) candidates = ((NSDictionary *)iv2)[@"candidates"];
	if (!candidates) candidates = sciFieldCache(media, @"candidates");
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

	return sciURLFromString(best[@"url"]);
}

+ (NSURL *)hdPhotoURLForMedia:(id)media {
	NSURL *url = [self fieldCachePhotoURLForMedia:media];
	if (url) return url;

	id photo = sciSendObj(media, @"photo");
	id versions = sciIvar(photo, "_originalImageVersions");
	if (![versions isKindOfClass:NSArray.class]) return nil;

	NSURL *bestURL = nil;
	NSInteger bestWidth = 0;

	for (id item in (NSArray *)versions) {
		NSURL *u = nil;
		NSInteger w = 0;

		if ([item isKindOfClass:NSDictionary.class]) {
			u = sciURLFromString(((NSDictionary *)item)[@"url"]);
			id widthObj = ((NSDictionary *)item)[@"width"];
			w = [widthObj respondsToSelector:@selector(integerValue)] ? [widthObj integerValue] : 0;
		} else {
			id urlObj = sciSendObj(item, @"url") ?: sciKVC(item, @"url");
			if ([urlObj isKindOfClass:NSURL.class]) u = urlObj;
			else if ([urlObj isKindOfClass:NSString.class]) u = sciURLFromString(urlObj);
			id widthObj = sciSendObj(item, @"width") ?: sciKVC(item, @"width");
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

	NSURL *video = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
	if (video) return video;

	if ([[SCIUtils getStringPref:@"default_photo_quality"] isEqualToString:@"high"]) {
		NSURL *hd = [self hdPhotoURLForMedia:media];
		if (hd) return hd;
	}

	return [SCIUtils getPhotoUrlForMedia:(IGMedia *)media] ?: [self fieldCachePhotoURLForMedia:media];
}

+ (NSURL *)coverURLForMedia:(id)media {
	return media ? [SCIUtils getPhotoUrlForMedia:(IGMedia *)media] : nil;
}

#pragma mark - Single downloads

+ (void)downloadPhotoOnlyForMedia:(id)media action:(DownloadAction)action {
	NSURL *url = [self hdPhotoURLForMedia:media] ?: [SCIUtils getPhotoUrlForMedia:(IGMedia *)media] ?: [self fieldCachePhotoURLForMedia:media];
	if (!url) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo URL")];
		return;
	}

	NSString *ext = sciExt(url, @"jpg");
	[sciMakeDownloader(action, NO) downloadFileWithURL:url fileExtension:ext hudLabel:nil];
}

+ (void)downloadAudioOnlyForMedia:(id)media action:(DownloadAction)action {
	NSString *manifest = [SCIDashParser dashManifestForMedia:media];
	SCIDashRepresentation *audio = [SCIDashParser bestAudioFromRepresentations:[SCIDashParser parseManifest:manifest]];

	if (!manifest.length || !audio.url) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No audio track found")];
		return;
	}

	if (![SCIFFmpeg isAvailable]) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"FFmpeg not available")];
		return;
	}

	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSString *stem = self.currentFilenameStem ?: NSUUID.UUID.UUIDString;
	NSString *outPath = [SCITempFiles claimWithExt:@"m4a" ttl:900 tag:stem].path;
	NSString *cmd = [NSString stringWithFormat:@"-i \"%@\" -vn -c:a copy -y \"%@\"", audio.url.absoluteString, outPath];

	__block SCIDownloadJob *job = nil;
	void (^start)(void) = ^{
		[center job:job didProgress:0.05f stage:SCILocalized(@"Downloading audio…")];
		[SCIFFmpeg executeCommand:cmd completion:^(BOOL success, NSString *output) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if ([SCIFFmpeg isCancelled]) {
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
					sciFinishJobWithGallerySave(job, fileURL, SCIGalleryMediaTypeAudio);
					return;
				}

				job.successText = SCILocalized(@"Audio ready");
				[center markJobFinished:job];
				if (action == quickLook) [SCIUtils showQuickLookVC:@[fileURL]];
				else [SCIUtils showShareVC:fileURL];
			});
		}];
	};

	NSString *audioUser = sciPeekPendingMetadata().sourceUsername;
	job = [center enqueueJobWithTitle:(audioUser.length ? [@"@" stringByAppendingString:audioUser] : SCILocalized(@"Audio"))
	                             kind:SCIDownloadJobKindDashMux
	                            start:start
	                           cancel:^{ [SCIFFmpeg cancelAll]; }];
	job.subtitle = SCILocalized(@"Audio");
	job.retryBlock = ^{ [SCIMediaActions downloadAudioOnlyForMedia:media action:action]; };
}

+ (void)downloadHDMedia:(id)media action:(DownloadAction)action fromView:(UIView *)sourceView {
	if (!media) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media")];
		return;
	}

	BOOL isVideo = [SCIUtils getVideoUrlForMedia:(IGMedia *)media] != nil;
	if (!isVideo) {
		NSURL *url = [self bestURLForMedia:media];
		if (!url) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract photo URL")];
			return;
		}

		[sciMakeDownloader(action, NO) downloadFileWithURL:url fileExtension:sciExt(url, @"jpg") hudLabel:nil];
		return;
	}

	BOOL handled = [SCIQualityPicker pickQualityForMedia:media
												fromView:sourceView
												 action:action
												 picked:^(SCIDashRepresentation *video, SCIDashRepresentation *audio) {
		[self downloadDASHVideo:video audio:audio action:action];
	} fallback:^{
		NSURL *url = [self bestURLForMedia:media];
		if (!url) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract video URL")];
			return;
		}

		[sciMakeDownloader(action, YES) downloadFileWithURL:url fileExtension:sciExt(url, @"mp4") hudLabel:nil];
	}];

	(void)handled;
}

+ (void)downloadDASHVideo:(SCIDashRepresentation *)videoRep audio:(SCIDashRepresentation *)audioRep action:(DownloadAction)action {
	if (!videoRep.url) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No video URL")];
		return;
	}

	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSString *preset = [SCIUtils getStringPref:@"ffmpeg_encoding_speed"];
	if (!preset.length) preset = @"ultrafast";

	SCIGallerySaveMetadata *meta = sciPeekPendingMetadata();
	NSString *user = meta.sourceUsername;
	NSString *title = user.length ? [@"@" stringByAppendingString:user] : SCILocalized(@"HD video");
	NSString *subtitle = videoRep.qualityLabel.length
		? [NSString stringWithFormat:SCILocalized(@"Video · %@"), videoRep.qualityLabel]
		: SCILocalized(@"Video");

	__block SCIDownloadJob *job = nil;
	__block void (^muxCancel)(void) = nil;
	__block BOOL pendingCancel = NO;

	void (^start)(void) = ^{
		[SCIFFmpeg muxVideoURL:videoRep.url audioURL:audioRep.url preset:preset progress:^(float progress, NSString *stage) {
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
					job.successText = SCILocalized(@"HD download complete");
					[center markJobFinished:job];
					[SCIUtils showShareVC:outputURL];
					break;
				case quickLook:
					job.successText = SCILocalized(@"HD download complete");
					[center markJobFinished:job];
					[SCIUtils showQuickLookVC:@[outputURL]];
					break;
				case saveToGallery:
					sciFinishJobWithGallerySave(job, outputURL, SCIGalleryMediaTypeVideo);
					break;
				case saveToPhotos: {
					NSString *galleryMode = [SCIUtils getStringPref:@"gallery_save_mode"];
					if ([galleryMode isEqualToString:@"gallery_only"]) {
						sciFinishJobWithGallerySave(job, outputURL, SCIGalleryMediaTypeVideo);
					} else {
						// Mirror: copy to gallery before the Photos save moves the file.
						if ([galleryMode isEqualToString:@"mirror"]) {
							NSError *e = nil;
							sciSaveFileToGalleryURL(outputURL, SCIGalleryMediaTypeVideo, &e);
						}
						sciSaveVideoToPhotosURLForJob(outputURL, job);
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
	                             kind:SCIDownloadJobKindDashMux
	                            start:start
	                           cancel:^{
		pendingCancel = YES;
		if (muxCancel) muxCancel();
	}];
	job.subtitle = subtitle;
	job.retryBlock = ^{
		[SCIMediaActions downloadDASHVideo:videoRep audio:audioRep action:action];
	};
}

#pragma mark - Primary actions

+ (void)expandMedia:(id)media fromView:(UIView *)sourceView caption:(NSString *)caption {
	if (!media) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No media to expand")];
		return;
	}

	NSString *cap = caption ?: [self captionForMedia:media];

	if ([self isCarouselMedia:media]) {
		NSArray<SCIMediaViewerItem *> *items = sciViewerItemsForChildren([self carouselChildrenForMedia:media], cap);
		if (items.count) {
			[SCIMediaViewer showItems:items startIndex:0];
			return;
		}
	}

	NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
	NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)media] ?: (!v ? [self bestURLForMedia:media] : nil);

	if (!v && !p) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract media URL")];
		return;
	}

	[SCIMediaViewer showWithVideoURL:v photoURL:p caption:cap];
}

+ (void)downloadAndShareMedia:(id)media {
	[self downloadAndShareMedia:media fromView:nil];
}

+ (void)downloadAndShareMedia:(id)media fromView:(UIView *)sourceView {
	sciConfirmThen(SCILocalized(@"Download and share"), ^{
		[self downloadHDMedia:media action:share fromView:sourceView];
	});
}

+ (void)downloadAndSaveMedia:(id)media {
	[self downloadAndSaveMedia:media fromView:nil];
}

+ (void)downloadAndSaveMedia:(id)media fromView:(UIView *)sourceView {
	sciConfirmThen(SCILocalized(@"Save to Photos"), ^{
		[self downloadHDMedia:media action:saveToPhotos fromView:sourceView];
	});
}

+ (void)downloadAndSaveMediaToGallery:(id)media fromView:(UIView *)sourceView {
	sciConfirmThen([NSString stringWithFormat:@"%@?", SCILocalized(@"Save to Gallery")], ^{
		[self downloadHDMedia:media action:saveToGallery fromView:sourceView];
	});
}

+ (void)copyURLForMedia:(id)media {
	NSURL *url = [self bestURLForMedia:media];
	if (!url) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract media URL")];
		return;
	}

	UIPasteboard.generalPasteboard.string = url.absoluteString;
	SCINotifySuccess(SCI_NOTIF_COPY_URL, SCILocalized(@"Copied download URL"), nil);
}

+ (void)copyCaptionForMedia:(id)media {
	NSString *caption = [self captionForMedia:media];
	if (!caption.length) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No caption on this post")];
		return;
	}

	UIPasteboard.generalPasteboard.string = caption;
	SCINotifySuccess(SCI_NOTIF_COPY_CAPTION, SCILocalized(@"Copied caption"), nil);
}

#pragma mark - Bulk helpers

+ (void)bulkDownloadURLs:(NSArray<NSURL *> *)urls title:(NSString *)title username:(NSString *)username done:(void(^)(NSArray<NSURL *> *fileURLs))done {
	if (!urls.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No URLs")];
		return;
	}

	sciConfirmThen(title, ^{
		SCIDownloadCenter *center = [SCIDownloadCenter shared];
		NSString *stem = self.currentFilenameStem;
		NSMutableArray<NSURL *> *files = NSMutableArray.array;
		NSMutableArray<NSURLSessionDownloadTask *> *tasks = NSMutableArray.array;
		NSLock *lock = NSLock.new;
		__block BOOL cancelled = NO;
		__block NSUInteger completed = 0;
		__block SCIDownloadJob *job = nil;

		void (^start)(void) = ^{
			dispatch_group_t group = dispatch_group_create();
			NSUInteger total = urls.count;
			[center job:job didProgress:0.0f stage:[NSString stringWithFormat:SCILocalized(@"%lu of %lu"), 0UL, (unsigned long)total]];

			[urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, __unused BOOL *stop) {
				[lock lock]; BOOL shouldSkip = cancelled; [lock unlock];
				if (shouldSkip) return;

				dispatch_group_enter(group);

				NSString *ext = sciExt(url, @"jpg");
				NSString *name = stem.length ? [NSString stringWithFormat:@"%@_%lu", stem, (unsigned long)(idx + 1)] : NSUUID.UUID.UUIDString;
				NSURL *dst = [SCITempFiles claimWithExt:ext ttl:900 tag:name];

				NSURLSessionDownloadTask *task = [NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *loc, __unused NSURLResponse *resp, NSError *err) {
					[lock lock]; BOOL wasCancelled = cancelled || err.code == NSURLErrorCancelled; [lock unlock];

					if (!err && loc && !wasCancelled) {
						[NSFileManager.defaultManager removeItemAtURL:dst error:nil];
						if ([NSFileManager.defaultManager moveItemAtURL:loc toURL:dst error:nil]) {
							[lock lock]; [files addObject:dst]; [lock unlock];
						}
					}

					[lock lock]; completed++; NSUInteger current = completed; [lock unlock];
					if (!wasCancelled)
						[center job:job didProgress:(float)current / (float)total
						        stage:[NSString stringWithFormat:SCILocalized(@"%lu of %lu"), (unsigned long)current, (unsigned long)total]];

					dispatch_group_leave(group);
				}];

				[lock lock]; [tasks addObject:task]; [lock unlock];
				[task resume];
			}];

			dispatch_group_notify(group, dispatch_get_main_queue(), ^{
				[lock lock]; BOOL wasCancelled = cancelled; [lock unlock];
				if (wasCancelled) { [center markJobCancelled:job]; return; }
				if (!files.count) { [center markJob:job failedWithError:nil]; return; }

				job.successText = [NSString stringWithFormat:SCILocalized(@"Downloaded %lu items"), (unsigned long)files.count];
				[center markJobFinished:job];
				if (done) done(files.copy);
			});
		};

		job = [center enqueueJobWithTitle:(username.length ? [@"@" stringByAppendingString:username] : SCILocalized(@"Carousel"))
		                             kind:SCIDownloadJobKindSimpleURL
		                            start:start
		                           cancel:^{
			[lock lock]; cancelled = YES; NSArray *snapshot = tasks.copy; [lock unlock];
			for (NSURLSessionDownloadTask *task in snapshot) [task cancel];
		}];
		job.subtitle = username.length
			? [NSString stringWithFormat:SCILocalized(@"Carousel · %lu items"), (unsigned long)urls.count]
			: [NSString stringWithFormat:SCILocalized(@"%lu items"), (unsigned long)urls.count];
	});
}

+ (void)downloadAllChildrenOfMedia:(id)media progressTitle:(NSString *)title done:(void(^)(NSArray<NSURL *> *fileURLs))done {
	NSArray *children = [self carouselChildrenForMedia:media];
	if (!children.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"No carousel children")];
		return;
	}

	NSArray<NSURL *> *urls = sciURLsForMedias(children);
	if (!urls.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not extract any URLs")];
		return;
	}

	[self bulkDownloadURLs:urls title:title username:sciUsernameForMedia(media) done:done];
}

+ (void)bulkSaveFiles:(NSArray<NSURL *> *)files {
	if (!files.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to save")];
		return;
	}

	NSString *galleryMode = [SCIUtils getStringPref:@"gallery_save_mode"];
	if ([galleryMode isEqualToString:@"gallery_only"]) {
		SCIGallerySaveMetadata *md = sciMakeGalleryMetadata(SCIGallerySourceOther, nil, YES);
		[self bulkSaveFilesToGallery:files perFileMetadata:nil defaultMetadata:md];
		return;
	}
	BOOL mirror = [galleryMode isEqualToString:@"mirror"];

	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSUInteger total = files.count;
	__block SCIDownloadJob *job = nil;

	void (^start)(void) = ^{
		[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
			if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Photo library access denied")];
					[center markJob:job failedWithError:nil];
				});
				return;
			}

			BOOL useAlbum = [SCIUtils getBoolPref:@"save_to_ryukgram_album"];
			__block NSUInteger saved = 0;
			__block NSUInteger index = 0;
			__block void (^saveNext)(void) = nil;

			saveNext = ^{
				if (index >= total) {
					dispatch_async(dispatch_get_main_queue(), ^{
						job.successText = [NSString stringWithFormat:SCILocalized(@"Saved %lu items"), (unsigned long)saved];
						[center markJobFinished:job];
					});
					saveNext = nil;
					return;
				}

				NSURL *file = files[index++];
				[center job:job didProgress:(float)index / (float)total
				        stage:[NSString stringWithFormat:SCILocalized(@"%lu of %lu"), (unsigned long)index, (unsigned long)total]];

				void (^step)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
					if (ok) saved++;
					if (saveNext) saveNext();
				};

				// Mirror: copy to gallery before the Photos save moves the file.
				if (mirror) {
					SCIGallerySaveMetadata *md = sciMakeGalleryMetadata(SCIGallerySourceOther, nil, YES);
					NSError *ge = nil;
					[SCIGalleryFile saveFileToGallery:file
											   source:SCIGallerySourceOther
											mediaType:(sciIsVideoURL(file) ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage)
										   folderPath:nil
											 metadata:md
												error:&ge];
				}

				if (useAlbum) {
					[SCIPhotoAlbum saveFileToAlbum:file completion:step];
					return;
				}

				sciSavePhotosAsset(file, (sciIsVideoURL(file) ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto), step);
			};

			saveNext();
		}];
	};

	job = [center enqueueJobWithTitle:SCILocalized(@"Saving to Photos") kind:SCIDownloadJobKindSimpleURL start:start cancel:nil];
	job.subtitle = [NSString stringWithFormat:SCILocalized(@"%lu items"), (unsigned long)total];
}

+ (void)bulkSaveFilesToGallery:(NSArray<NSURL *> *)files perFileMetadata:(NSArray<SCIGallerySaveMetadata *> *)perFile defaultMetadata:(SCIGallerySaveMetadata *)defaultMetadata {
	if (!files.count) return;

	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	__block SCIDownloadJob *job = nil;
	void (^start)(void) = ^{
		[self _bulkGallerySaveStep:files index:0 success:0 perFileMetadata:perFile defaultMetadata:defaultMetadata job:job];
	};
	job = [center enqueueJobWithTitle:SCILocalized(@"Saving to Gallery") kind:SCIDownloadJobKindSimpleURL start:start cancel:nil];
	job.subtitle = [NSString stringWithFormat:SCILocalized(@"%lu items"), (unsigned long)files.count];
}

+ (void)_bulkGallerySaveStep:(NSArray<NSURL *> *)files index:(NSUInteger)idx success:(NSUInteger)success perFileMetadata:(NSArray<SCIGallerySaveMetadata *> *)perFile defaultMetadata:(SCIGallerySaveMetadata *)defaultMetadata job:(SCIDownloadJob *)job {
	SCIDownloadCenter *center = [SCIDownloadCenter shared];
	NSUInteger total = files.count;
	if (idx >= total) {
		job.successText = [NSString stringWithFormat:SCILocalized(@"Saved %lu items to Gallery"), (unsigned long)success];
		[center markJobFinished:job];
		return;
	}

	[center job:job didProgress:(float)idx / (float)total
	        stage:[NSString stringWithFormat:SCILocalized(@"%lu of %lu"), (unsigned long)idx, (unsigned long)total]];

	NSURL *url = files[idx];
	SCIGallerySaveMetadata *m = (perFile && idx < perFile.count) ? perFile[idx] : defaultMetadata;
	NSError *error = nil;

	SCIGalleryFile *file = [SCIGalleryFile saveFileToGallery:url
													 source:(SCIGallerySource)m.source
												  mediaType:(sciIsVideoURL(url) ? SCIGalleryMediaTypeVideo : SCIGalleryMediaTypeImage)
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
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:SCILocalized(@"Download all and share?") done:^(NSArray<NSURL *> *files) {
		if (!files.count) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to share")];
			return;
		}
		sciPresentActivity(files);
	}];
}

+ (void)downloadAllAndSaveMedia:(id)carouselMedia {
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Save all to Photos")] done:^(NSArray<NSURL *> *files) {
		[self bulkSaveFiles:files];
	}];
}

+ (void)downloadAllAndSaveMediaToGallery:(id)carouselMedia context:(SCIActionContext)ctx {
	[self downloadAllChildrenOfMedia:carouselMedia progressTitle:[NSString stringWithFormat:@"%@?", SCILocalized(@"Save all to Gallery")] done:^(NSArray<NSURL *> *files) {
		if (!files.count) {
			[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Nothing to save")];
			return;
		}

		SCIGallerySaveMetadata *metadata = sciMakeGalleryMetadata(sciGallerySourceFromContext(ctx), carouselMedia, YES);
		[self bulkSaveFilesToGallery:files perFileMetadata:nil defaultMetadata:metadata];
	}];
}

+ (void)copyAllURLsForMedia:(id)carouselMedia {
	NSArray *children = [self carouselChildrenForMedia:carouselMedia];
	if (!children.count) {
		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Not a carousel")];
		return;
	}

	sciCopyURLStrings(sciURLStringsForMedias(children));
}

#pragma mark - Discovery helpers

static UIView *sciFindSubviewOfClass(UIView *root, NSString *className, NSUInteger maxViews) {
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

static NSArray *sciStoryReelMedias(UIView *sourceView) {
	if (!sourceView) return @[];

	UIViewController *storyVC = [SCIUtils nearestViewControllerForView:sourceView];
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

	id vm = sciSendObj(r, @"currentViewModel");
	if (!vm) return @[];

	NSArray *items = nil;
	for (NSString *sel in @[@"items", @"storyItems", @"reelItems", @"mediaItems", @"allItems"]) {
		id val = sciSendObj(vm, sel);
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
			id media = sciSendObj(item, sel);
			if (media && mediaClass && [media isKindOfClass:mediaClass]) {
				[medias addObject:media];
				break;
			}
		}
	}

	return medias.count > 1 ? medias.copy : @[];
}

static id sciCarouselParentMedia(id media, UIView *sourceView) {
	if (!media || [SCIMediaActions isCarouselMedia:media]) return media;

	for (UIView *v = sourceView; v; v = v.superview) {
		id stashed = objc_getAssociatedObject(v, kSCICarouselParentMediaKey);
		if (stashed && [SCIMediaActions isCarouselMedia:stashed]) return stashed;

		id passthrough = sciIvar(v, "_mediaPassthrough");
		if (passthrough && [SCIMediaActions isCarouselMedia:passthrough]) return passthrough;
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

		id parent = sciIvar(cell, "_media");
		if (parent && mediaClass && [parent isKindOfClass:mediaClass] && [SCIMediaActions isCarouselMedia:parent]) return parent;
	}

	return media;
}

#pragma mark - Repost / Settings

+ (void)triggerRepostForContext:(SCIActionContext)ctx sourceView:(UIView *)sourceView {
	if (ctx == SCIActionContextReels) {
		Class cellClass = NSClassFromString(@"IGSundialViewerVideoCell") ?: NSClassFromString(@"IGSundialViewerPhotoView");
		UIView *cell = sourceView;

		while (cell && cellClass && ![cell isKindOfClass:cellClass]) cell = cell.superview;

		UIView *ufi = cell ? sciFindSubviewOfClass(cell, @"IGSundialViewerVerticalUFI", 200) : nil;
		if (ufi) {
			SEL noArg = NSSelectorFromString(@"_didTapRepostButton");
			SEL oneArg = @selector(_didTapRepostButton:);

			if ([ufi respondsToSelector:noArg]) {
				((void(*)(id, SEL))objc_msgSend)(ufi, noArg);
				return;
			}

			if ([ufi respondsToSelector:oneArg]) {
				((void(*)(id, SEL, id))objc_msgSend)(ufi, oneArg, nil);
				return;
			}
		}

		[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Repost unavailable")];
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

	[SCIUtils showErrorHUDWithDescription:SCILocalized(@"Repost unavailable")];
}

+ (void)openSettingsForContext:(SCIActionContext)ctx fromView:(UIView *)sourceView {
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

	if (window) [SCIUtils showSettingsVC:window atTopLevelEntry:sciSettingsTitleForContext(ctx)];
}

#pragma mark - Menu builder

+ (NSArray<SCIAction *> *)actionsForContext:(SCIActionContext)ctx media:(id)media fromView:(UIView *)sourceView {
	return [self actionsForContext:ctx media:media fromView:sourceView includeDisabled:NO];
}

+ (NSArray<SCIAction *> *)actionsForContext:(SCIActionContext)ctx media:(id)media fromView:(UIView *)sourceView includeDisabled:(BOOL)includeDisabled {
	SCIActionMenuConfig *config = [SCIActionMenuConfig configForSource:sciSourceFromContext(ctx)];
	NSString *dateHeader = config.showDate ? sciFormatDateHeader(sciExtractDateFromMedia(media)) : nil;
	NSString *ctxLabel = [self contextLabelForContext:ctx];

	id parentMedia = sciCarouselParentMedia(media, sourceView);
	BOOL isCarousel = parentMedia && [self isCarouselMedia:parentMedia];
	NSString *caption = parentMedia ? [self captionForMedia:parentMedia] : nil;
	NSArray *storyMedias = (ctx == SCIActionContextStories && !isCarousel) ? sciStoryReelMedias(sourceView) : @[];
	BOOL hasBulk = isCarousel || storyMedias.count > 1;
	__weak UIView *weakSource = sourceView;

	__weak id weakParent = parentMedia;
	void (^stamp)(id) = ^(id targetMedia) {
		[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:targetMedia contextLabel:ctxLabel]];

		// Carousel children carry no user info — populate from the parent
		// first, then layer the child's media-specific identifiers on top.
		id parent = weakParent;
		SCIGallerySaveMetadata *m = sciMakeGalleryMetadata(sciGallerySourceFromContext(ctx),
		                                                   (parent && parent != targetMedia) ? parent : nil, NO);
		@try { [SCIGalleryOriginController populateMetadata:m fromMedia:targetMedia]; }
		@catch (__unused id e) {}
		sciSetPendingMetadata(m);
	};

	SCIAction *(^resolve)(NSString *) = ^SCIAction *(NSString *aid) {
		if ([aid isEqualToString:SCIAID_Expand]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Expand") icon:@"arrow.up.left.and.arrow.down.right" handler:^{
				if (isCarousel) {
					NSArray *children = [SCIMediaActions carouselChildrenForMedia:parentMedia];
					NSArray<SCIMediaViewerItem *> *items = sciViewerItemsForChildren(children, caption);

					NSUInteger start = 0;
					if (media != parentMedia) {
						NSUInteger idx = [children indexOfObjectIdenticalTo:media];
						if (idx != NSNotFound) start = idx;
					}

					if (items.count) [SCIMediaViewer showItems:items startIndex:start];
					else [SCIMediaActions expandMedia:media fromView:weakSource caption:caption];
					return;
				}

				[SCIMediaActions expandMedia:media fromView:weakSource caption:caption];
			}];
		}

		if ([aid isEqualToString:SCIAID_ViewCover]) {
			BOOL hasCover = ctx == SCIActionContextReels || (ctx == SCIActionContextFeed && [SCIUtils getVideoUrlForMedia:(IGMedia *)media]);
			if (!hasCover) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"View cover") icon:@"photo" handler:^{
				NSURL *cover = [SCIMediaActions coverURLForMedia:media];
				if (cover) [SCIMediaViewer showWithVideoURL:nil photoURL:cover caption:nil];
				else [SCIUtils showErrorHUDWithDescription:SCILocalized(@"No cover image")];
			}];
		}

		if ([aid isEqualToString:SCIAID_Repost]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Repost") icon:@"arrow.2.squarepath" handler:^{
				[SCIRepostSheet repostWithVideoURL:[SCIUtils getVideoUrlForMedia:(IGMedia *)media] photoURL:[SCIUtils getPhotoUrlForMedia:(IGMedia *)media]];
			}];
		}

		if ([aid isEqualToString:SCIAID_ViewMentions]) {
			if (ctx != SCIActionContextStories || ![SCIUtils getBoolPref:@"view_story_mentions"]) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"View mentions") icon:@"at" handler:^{
				UIViewController *host = [SCIUtils nearestViewControllerForView:weakSource];
				if (host) sciShowStoryMentions(host, weakSource);
			}];
		}

		if ([aid isEqualToString:SCIAID_ToggleAudio]) {
			if (ctx != SCIActionContextStories || ![SCIUtils getBoolPref:@"story_audio_toggle"]) return nil;

			BOOL on = sciIsStoryAudioEnabled();
			return [SCIAction actionWithTitle:(on ? SCILocalized(@"Mute audio") : SCILocalized(@"Unmute audio"))
										 icon:(on ? @"speaker.wave.2" : @"speaker.slash")
									  handler:^{ sciToggleStoryAudio(); }];
		}

		if ([aid isEqualToString:SCIAID_ExcludeUser]) {
			if (ctx != SCIActionContextStories || ![SCIUtils getBoolPref:@"enable_story_user_exclusions"]) return nil;

			extern NSDictionary *sciOwnerInfoForView(UIView *);
			extern void sciRefreshAllVisibleOverlays(UIViewController *);
			extern __weak UIViewController *sciActiveStoryViewerVC;

			NSDictionary *info = weakSource ? sciOwnerInfoForView(weakSource) : nil;
			NSString *pk = info[@"pk"];
			if (!pk.length) return nil;

			BOOL inList = [SCIExcludedStoryUsers isInList:pk];
			BOOL blockMode = [SCIExcludedStoryUsers isBlockSelectedMode];

			NSString *title = inList
				? (blockMode ? SCILocalized(@"Remove from block list") : SCILocalized(@"Remove from exclude list"))
				: (blockMode ? SCILocalized(@"Add to block list") : SCILocalized(@"Exclude from seen"));

			NSString *capturedPK = pk.copy;
			NSString *capturedUser = [info[@"username"] ?: @"" copy];
			NSString *capturedName = [info[@"fullName"] ?: @"" copy];

			return [SCIAction actionWithTitle:title icon:(inList ? @"eye.fill" : @"eye.slash") handler:^{
				if (inList) {
					[SCIExcludedStoryUsers removePK:capturedPK];
					SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY, blockMode ? SCILocalized(@"Unblocked") : SCILocalized(@"Removed from list"), nil);
				} else {
					[SCIExcludedStoryUsers addOrUpdateEntry:@{@"pk": capturedPK, @"username": capturedUser, @"fullName": capturedName}];
					SCINotifySuccess(blockMode ? SCI_NOTIF_BLOCK_TOGGLE : SCI_NOTIF_EXCLUDE_STORY, blockMode ? SCILocalized(@"Added to block list") : SCILocalized(@"Added to exclude list"), nil);
				}
				sciRefreshAllVisibleOverlays(sciActiveStoryViewerVC);
			}];
		}

		if ([aid isEqualToString:SCIAID_CopyCaption]) {
			if (ctx == SCIActionContextStories) return nil;
			return [SCIAction actionWithTitle:SCILocalized(@"Copy caption") icon:@"text.quote" handler:^{
				[SCIMediaActions copyCaptionForMedia:parentMedia];
			}];
		}

		if ([aid isEqualToString:SCIAID_CopyURL]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Copy media URL") icon:@"link" handler:^{
				[SCIMediaActions copyURLForMedia:media];
			}];
		}

		if ([aid isEqualToString:SCIAID_DownloadShare]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Download and share") icon:@"square.and.arrow.up" handler:^{
				stamp(media);
				[SCIMediaActions downloadAndShareMedia:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:SCIAID_DownloadSave]) {
			return [SCIAction actionWithTitle:SCILocalized(@"Download to Photos") icon:@"square.and.arrow.down" handler:^{
				stamp(media);
				[SCIMediaActions downloadAndSaveMedia:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:SCIAID_DownloadGallery]) {
			if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"Download to Gallery") icon:@"photo.on.rectangle.angled" handler:^{
				stamp(media);
				[SCIMediaActions downloadAndSaveMediaToGallery:media fromView:weakSource];
			}];
		}

		if ([aid isEqualToString:SCIAID_BulkCopyURLs]) {
			if (!hasBulk) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"Copy all URLs") icon:@"doc.on.doc" handler:^{
				NSArray<NSString *> *urls = sciURLStringsForMedias(isCarousel ? [SCIMediaActions carouselChildrenForMedia:parentMedia] : storyMedias);
				sciCopyURLStrings(urls);
			}];
		}

		if ([aid isEqualToString:SCIAID_BulkDownloadShare]) {
			if (!hasBulk) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"Download and share all") icon:@"square.and.arrow.up.on.square" handler:^{
				if (isCarousel) {
					[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:parentMedia contextLabel:ctxLabel]];
					[SCIMediaActions downloadAllAndShareMedia:parentMedia];
					return;
				}

				[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:storyMedias.firstObject contextLabel:ctxLabel]];
				[SCIMediaActions bulkDownloadURLs:sciURLsForMedias(storyMedias) title:SCILocalized(@"Download all stories and share?") username:sciUsernameForMedia(storyMedias.firstObject) done:^(NSArray<NSURL *> *files) {
					sciPresentActivity(files);
				}];
			}];
		}

		if ([aid isEqualToString:SCIAID_BulkDownloadSave]) {
			if (!hasBulk) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"Download all to Photos") icon:@"square.and.arrow.down.on.square" handler:^{
				if (isCarousel) {
					[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:parentMedia contextLabel:ctxLabel]];
					[SCIMediaActions downloadAllAndSaveMedia:parentMedia];
					return;
				}

				[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:storyMedias.firstObject contextLabel:ctxLabel]];
				[SCIMediaActions bulkDownloadURLs:sciURLsForMedias(storyMedias) title:SCILocalized(@"Download all to Photos") username:sciUsernameForMedia(storyMedias.firstObject) done:^(NSArray<NSURL *> *files) {
					[SCIMediaActions bulkSaveFiles:files];
				}];
			}];
		}

		if ([aid isEqualToString:SCIAID_BulkDownloadGallery]) {
			if (!hasBulk || ![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;

			return [SCIAction actionWithTitle:SCILocalized(@"Download all to Gallery") icon:@"square.stack.3d.down.right" handler:^{
				if (isCarousel) {
					[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:parentMedia contextLabel:ctxLabel]];
					[SCIMediaActions downloadAllAndSaveMediaToGallery:parentMedia context:ctx];
					return;
				}

				NSArray *medias = storyMedias;
				[SCIMediaActions setCurrentFilenameStem:[SCIMediaActions filenameStemForMedia:medias.firstObject contextLabel:ctxLabel]];
				[SCIMediaActions bulkDownloadURLs:sciURLsForMedias(medias) title:SCILocalized(@"Download all to Gallery") username:sciUsernameForMedia(medias.firstObject) done:^(NSArray<NSURL *> *files) {
					if (!files.count) return;

					NSMutableArray<SCIGallerySaveMetadata *> *metadata = [NSMutableArray arrayWithCapacity:files.count];
					for (NSUInteger i = 0; i < files.count; i++) {
						SCIGallerySaveMetadata *m = sciMakeGalleryMetadata(sciGallerySourceFromContext(ctx),
						                                       (i < medias.count ? medias[i] : nil), YES);
						[metadata addObject:m];
					}

					[SCIMediaActions bulkSaveFilesToGallery:files perFileMetadata:metadata defaultMetadata:metadata.firstObject];
				}];
			}];
		}

		if ([aid isEqualToString:SCIAID_Settings]) {
			return [SCIAction actionWithTitle:[NSString stringWithFormat:SCILocalized(@"%@ settings"), sciSettingsTitleForContext(ctx)]
										 icon:@"gearshape"
									  handler:^{
				[SCIMediaActions openSettingsForContext:ctx fromView:weakSource];
			}];
		}

		return nil;
	};

	NSArray<SCIAction *> *items = [SCIActionMenu actionsForConfig:config dateHeader:dateHeader resolver:resolve includeDisabled:includeDisabled];

	if (hasBulk) {
		NSUInteger bulkCount = isCarousel ? [self carouselChildrenForMedia:parentMedia].count : storyMedias.count;
		if (bulkCount > 1) {
			NSMutableArray<SCIAction *> *patched = [items mutableCopy];
			for (NSUInteger i = 0; i < patched.count; i++) {
				SCIAction *group = patched[i];
				if (!group.children.count) continue;
				BOOL isBulkGroup = NO;
				for (SCIAction *child in group.children) {
					if ([child.actionID hasPrefix:@"bulk_"]) { isBulkGroup = YES; break; }
				}
				if (!isBulkGroup) continue;
				NSString *title = [NSString stringWithFormat:@"%@ (%lu)", group.title, (unsigned long)bulkCount];
				patched[i] = [SCIAction actionWithTitle:title icon:group.systemIconName children:group.children];
				break;
			}
			items = patched;
		}
	}

	return items;
}

static BOOL sciFireActionWithIDInList(NSArray<SCIAction *> *items, NSString *aid) {
	for (SCIAction *action in items) {
		if (action.isSeparator) continue;
		if (action.children.count && sciFireActionWithIDInList(action.children, aid)) return YES;
		if (action.actionID.length && [action.actionID isEqualToString:aid] && action.handler) {
			action.handler();
			return YES;
		}
	}
	return NO;
}

+ (BOOL)executeActionForContext:(SCIActionContext)ctx actionID:(NSString *)aid media:(id)media fromView:(UIView *)sourceView {
	if (!aid.length || [aid isEqualToString:@"menu"]) return NO;
	return sciFireActionWithIDInList([self actionsForContext:ctx media:media fromView:sourceView includeDisabled:YES], aid);
}

@end