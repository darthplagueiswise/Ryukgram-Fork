#import "SCIChatBackgroundManager.h"
#import "../../Utils.h"
#import "../../SCIAccountScopedDefaults.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>

NSString *const SCIChatBackgroundDidChangeNotification = @"SCIChatBackgroundDidChangeNotification";
NSString *const SCIChatBackgroundRenderDirtyNotification = @"SCIChatBackgroundRenderDirtyNotification";

NSString *const SCIPrefChatBackgroundEnabled = @"chat_bg_enabled";
NSString *const SCIPrefChatBackgroundDefaultAsset = @"chat_bg_default_asset";
NSString *const SCIPrefChatBackgroundThreadMap = @"chat_bg_thread_map";
NSString *const SCIPrefChatBackgroundLibrary = @"chat_bg_library";
NSString *const SCIPrefChatBackgroundPerImage = @"chat_bg_per_image";
NSString *const SCIPrefChatBackgroundThreadMeta = @"chat_bg_thread_meta";

static NSString *const kAssetsDirName = @"ChatBackgrounds";
static NSString *const kOpacity = @"opacity";
static NSString *const kBlur = @"blur";
static NSString *const kDim = @"dim";

static double SCIClamp(double v, double min, double max) {
	if (isnan(v)) return min;
	return MIN(MAX(v, min), max);
}

static CIContext *SCISharedCIContext(void) {
	static CIContext *ctx;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ctx = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];
	});
	return ctx;
}

@interface SCIChatBackgroundManager ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *processedCache;
@end

@implementation SCIChatBackgroundManager

+ (instancetype)shared {
	static SCIChatBackgroundManager *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [SCIChatBackgroundManager new]; });
	return s;
}

- (instancetype)init {
	if ((self = [super init])) {
		_imageCache = [NSCache new];
		_imageCache.countLimit = 16;

		_processedCache = [NSCache new];
		_processedCache.countLimit = 24;
	}
	return self;
}

#pragma mark - Paths

- (NSURL *)assetsDirectoryURL {
	NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
	if (!docs) return nil;

	NSURL *dir = [[docs URLByAppendingPathComponent:@"RyukGram" isDirectory:YES] URLByAppendingPathComponent:kAssetsDirName isDirectory:YES];

	if (![NSFileManager.defaultManager fileExistsAtPath:dir.path]) {
		NSError *err = nil;
		if (![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&err]) {
			NSLog(@"[RyukGram][ChatBG] mkdir failed: %@", err);
			return nil;
		}
	}

	return dir;
}

- (NSURL *)urlForRelativeAsset:(NSString *)relPath {
	if (!relPath.length) return nil;
	NSURL *dir = [self assetsDirectoryURL];
	return dir ? [dir URLByAppendingPathComponent:relPath] : nil;
}

#pragma mark - Helpers

- (void)postChange {
	[self.imageCache removeAllObjects];
	[self.processedCache removeAllObjects];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIChatBackgroundDidChangeNotification object:nil];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIChatBackgroundRenderDirtyNotification object:nil];
}

- (void)postRenderDirty {
	[self.processedCache removeAllObjects];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIChatBackgroundRenderDirtyNotification object:nil];
}

- (BOOL)fileExistsForAsset:(NSString *)asset {
	NSURL *url = [self urlForRelativeAsset:asset];
	return url.path.length && [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

#pragma mark - Prefs

- (BOOL)isEnabled {
	return [SCIUtils getBoolPref:SCIPrefChatBackgroundEnabled];
}

- (NSString *)defaultAsset {
	id v = [SCIAccountScopedDefaults objectForKey:SCIPrefChatBackgroundDefaultAsset];
	return [v isKindOfClass:NSString.class] && [v length] ? v : nil;
}

- (void)setDefaultAsset:(NSString *)relPath {
	NSString *old = [self defaultAsset] ?: @"";
	NSString *new = relPath ?: @"";
	if ([old isEqualToString:new]) return;

	if (new.length) [SCIAccountScopedDefaults setObject:new forKey:SCIPrefChatBackgroundDefaultAsset];
	else [SCIAccountScopedDefaults removeObjectForKey:SCIPrefChatBackgroundDefaultAsset];

	[self postChange];
}

#pragma mark - Library

- (NSArray<NSString *> *)libraryAssets {
	id raw = [NSUserDefaults.standardUserDefaults objectForKey:SCIPrefChatBackgroundLibrary];
	if (![raw isKindOfClass:NSArray.class]) return @[];

	NSMutableArray *out = [NSMutableArray new];
	NSMutableSet *seen = [NSMutableSet new];

	for (id v in (NSArray *)raw) {
		if (![v isKindOfClass:NSString.class] || ![(NSString *)v length]) continue;
		if ([seen containsObject:v] || ![self fileExistsForAsset:v]) continue;

		[seen addObject:v];
		[out addObject:v];
	}

	return out.copy;
}

- (void)appendLibraryAsset:(NSString *)relPath {
	if (!relPath.length) return;

	NSMutableArray *list = [[self libraryAssets] mutableCopy];
	if ([list containsObject:relPath]) return;

	[list addObject:relPath];
	[NSUserDefaults.standardUserDefaults setObject:list forKey:SCIPrefChatBackgroundLibrary];
}

- (void)deleteLibraryAsset:(NSString *)relPath {
	if (!relPath.length) return;

	NSURL *url = [self urlForRelativeAsset:relPath];
	if (url) [NSFileManager.defaultManager removeItemAtURL:url error:nil];

	NSMutableArray *library = [[self libraryAssets] mutableCopy];
	[library removeObject:relPath];
	[NSUserDefaults.standardUserDefaults setObject:library forKey:SCIPrefChatBackgroundLibrary];

	if ([[self defaultAsset] isEqualToString:relPath]) {
		[SCIAccountScopedDefaults removeObjectForKey:SCIPrefChatBackgroundDefaultAsset];
	}

	NSMutableDictionary *threadMap = [[self allThreadAssets] mutableCopy];
	for (NSString *tid in [threadMap.allKeys copy]) {
		if ([threadMap[tid] isEqualToString:relPath]) [threadMap removeObjectForKey:tid];
	}
	[SCIAccountScopedDefaults setObject:threadMap forKey:SCIPrefChatBackgroundThreadMap];

	NSMutableDictionary *perImage = [[self perImageDict] mutableCopy];
	[perImage removeObjectForKey:relPath];
	[NSUserDefaults.standardUserDefaults setObject:perImage forKey:SCIPrefChatBackgroundPerImage];

	[self.imageCache removeObjectForKey:relPath];
	[self postChange];
}

#pragma mark - Thread assets

- (NSDictionary<NSString *, NSString *> *)allThreadAssets {
	id raw = [SCIAccountScopedDefaults dictForKey:SCIPrefChatBackgroundThreadMap];
	if (![raw isKindOfClass:NSDictionary.class]) return @{};

	NSMutableDictionary *out = [NSMutableDictionary new];

	for (id k in (NSDictionary *)raw) {
		id v = raw[k];
		if ([k isKindOfClass:NSString.class] && [v isKindOfClass:NSString.class] && [v length]) {
			out[k] = v;
		}
	}

	return out.copy;
}

- (NSString *)assetForThreadID:(NSString *)threadID {
	if (!threadID.length) return nil;
	return [self allThreadAssets][threadID];
}

- (void)setAsset:(NSString *)relPath forThreadID:(NSString *)threadID {
	if (!threadID.length) return;

	NSMutableDictionary *map = [[self allThreadAssets] mutableCopy];
	NSString *old = map[threadID] ?: @"";
	NSString *new = relPath ?: @"";
	if ([old isEqualToString:new]) return;

	if (new.length) map[threadID] = new;
	else [map removeObjectForKey:threadID];

	[SCIAccountScopedDefaults setObject:map forKey:SCIPrefChatBackgroundThreadMap];
	[self postChange];
}

- (void)clearAssetForThreadID:(NSString *)threadID {
	if (!threadID.length) return;
	[self setAsset:nil forThreadID:threadID];
	[self setMetadata:nil forThreadID:threadID];
}

#pragma mark - Metadata

- (NSDictionary *)metaDict {
	id raw = [SCIAccountScopedDefaults dictForKey:SCIPrefChatBackgroundThreadMeta];
	return [raw isKindOfClass:NSDictionary.class] ? raw : @{};
}

- (NSDictionary *)metadataForThreadID:(NSString *)tid {
	if (!tid.length) return nil;
	id v = [self metaDict][tid];
	return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

- (void)setMetadata:(NSDictionary *)meta forThreadID:(NSString *)tid {
	if (!tid.length) return;

	NSMutableDictionary *map = [[self metaDict] mutableCopy];
	if (meta.count) map[tid] = meta;
	else [map removeObjectForKey:tid];

	[SCIAccountScopedDefaults setObject:map forKey:SCIPrefChatBackgroundThreadMeta];
	[NSNotificationCenter.defaultCenter postNotificationName:SCIChatBackgroundDidChangeNotification object:nil];
}

#pragma mark - Resolve

- (NSString *)resolvedAssetForThreadID:(NSString *)threadID {
	NSString *asset = [self assetForThreadID:threadID];
	return asset.length ? asset : [self defaultAsset];
}

- (UIImage *)resolvedImageForThreadID:(NSString *)threadID {
	return [self imageForAsset:[self resolvedAssetForThreadID:threadID]];
}

- (UIImage *)processedImageForThreadID:(NSString *)threadID darkAppearance:(BOOL)isDark {
	return [self processedImageForAsset:[self resolvedAssetForThreadID:threadID] darkAppearance:isDark];
}

- (UIImage *)processedImageForAsset:(NSString *)asset darkAppearance:(BOOL)isDark {
	return [self processImage:[self imageForAsset:asset] asset:asset darkAppearance:isDark];
}

#pragma mark - Image cache / processing

- (UIImage *)imageForAsset:(NSString *)asset {
	if (!asset.length) return nil;

	UIImage *cached = [self.imageCache objectForKey:asset];
	if (cached) return cached;

	NSURL *url = [self urlForRelativeAsset:asset];
	if (!url.path.length) return nil;

	UIImage *img = [UIImage imageWithContentsOfFile:url.path];
	if (img) [self.imageCache setObject:img forKey:asset];

	return img;
}

- (UIImage *)processImage:(UIImage *)raw asset:(NSString *)asset darkAppearance:(BOOL)isDark {
	if (!raw || !asset.length) return raw;

	double blur = [self effectiveBlurForAsset:asset];
	double dim = isDark ? [self effectiveDimForAsset:asset] : 0.0;
	NSString *key = [NSString stringWithFormat:@"%@|%@|%.1f|%.2f", asset, isDark ? @"D" : @"L", blur, dim];

	UIImage *cached = [self.processedCache objectForKey:key];
	if (cached) return cached;

	UIImage *out = raw;

	if (blur > 0.5) {
		CIImage *ci = [[CIImage alloc] initWithImage:raw];
		if (ci) {
			CIFilter *clamp = [CIFilter filterWithName:@"CIAffineClamp"];
			[clamp setValue:ci forKey:kCIInputImageKey];
			[clamp setValue:[NSValue valueWithCGAffineTransform:CGAffineTransformIdentity] forKey:@"inputTransform"];

			CIFilter *gauss = [CIFilter filterWithName:@"CIGaussianBlur"];
			[gauss setValue:clamp.outputImage forKey:kCIInputImageKey];
			[gauss setValue:@(blur) forKey:@"inputRadius"];

			CGImageRef cg = [SCISharedCIContext() createCGImage:gauss.outputImage fromRect:ci.extent];
			if (cg) {
				out = [UIImage imageWithCGImage:cg scale:raw.scale orientation:raw.imageOrientation];
				CGImageRelease(cg);
			}
		}
	}

	if (dim > 0.001) {
		UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
		fmt.scale = out.scale;
		fmt.opaque = NO;

		out = [[[UIGraphicsImageRenderer alloc] initWithSize:out.size format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
			[out drawInRect:(CGRect){ .origin = CGPointZero, .size = out.size }];
			[[UIColor colorWithWhite:0 alpha:dim] setFill];
			UIRectFillUsingBlendMode((CGRect){ .origin = CGPointZero, .size = out.size }, kCGBlendModeNormal);
		}];
	}

	if (out) [self.processedCache setObject:out forKey:key];
	return out;
}

#pragma mark - Per-image settings

- (NSDictionary *)perImageDict {
	id raw = [NSUserDefaults.standardUserDefaults objectForKey:SCIPrefChatBackgroundPerImage];
	return [raw isKindOfClass:NSDictionary.class] ? raw : @{};
}

- (NSDictionary *)settingsForAsset:(NSString *)asset {
	if (!asset.length) return nil;
	id v = [self perImageDict][asset];
	return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

- (double)valueForAsset:(NSString *)asset key:(NSString *)key fallback:(double)fallback min:(double)min max:(double)max {
	NSNumber *v = [self settingsForAsset:asset][key];
	return v ? SCIClamp(v.doubleValue, min, max) : fallback;
}

- (void)setSetting:(double)value forAsset:(NSString *)asset key:(NSString *)key min:(double)min max:(double)max {
	if (!asset.length || !key.length) return;

	double clamped = SCIClamp(value, min, max);
	NSDictionary *oldEntry = [self settingsForAsset:asset] ?: @{};
	NSNumber *old = oldEntry[key];

	if (old && fabs(old.doubleValue - clamped) < 0.0001) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [oldEntry mutableCopy];
	entry[key] = @(clamped);
	map[asset] = entry;

	[NSUserDefaults.standardUserDefaults setObject:map forKey:SCIPrefChatBackgroundPerImage];
	[self postRenderDirty];
}

- (BOOL)hasCustomSettingsForAsset:(NSString *)asset {
	return [self settingsForAsset:asset].count > 0;
}

- (double)effectiveOpacityForAsset:(NSString *)asset {
	return [self valueForAsset:asset key:kOpacity fallback:1.0 min:0.1 max:1.0];
}

- (double)effectiveBlurForAsset:(NSString *)asset {
	return [self valueForAsset:asset key:kBlur fallback:0.0 min:0.0 max:30.0];
}

- (double)effectiveDimForAsset:(NSString *)asset {
	return [self valueForAsset:asset key:kDim fallback:0.0 min:0.0 max:0.85];
}

- (void)setOpacity:(double)value forAsset:(NSString *)asset {
	[self setSetting:value forAsset:asset key:kOpacity min:0.1 max:1.0];
}

- (void)setBlur:(double)value forAsset:(NSString *)asset {
	[self setSetting:value forAsset:asset key:kBlur min:0.0 max:30.0];
}

- (void)setDim:(double)value forAsset:(NSString *)asset {
	[self setSetting:value forAsset:asset key:kDim min:0.0 max:0.85];
}

- (void)resetSettingsForAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	if (!map[asset]) return;

	[map removeObjectForKey:asset];
	[NSUserDefaults.standardUserDefaults setObject:map forKey:SCIPrefChatBackgroundPerImage];
	[self postRenderDirty];
}

#pragma mark - Import

- (NSString *)importImage:(UIImage *)image {
	if (!image) return nil;

	NSData *data = UIImageJPEGRepresentation(image, 0.92);
	if (!data.length) data = UIImagePNGRepresentation(image);
	if (!data.length) return nil;

	return [self importData:data ext:@"jpg"];
}

- (NSString *)importFileURL:(NSURL *)src {
	if (!src) return nil;

	BOOL scoped = [src startAccessingSecurityScopedResource];
	NSData *data = [NSData dataWithContentsOfURL:src];
	if (scoped) [src stopAccessingSecurityScopedResource];

	if (!data.length) return nil;

	NSString *ext = src.pathExtension.lowercaseString;
	if (![@[@"jpg", @"jpeg", @"png", @"heic", @"webp", @"gif"] containsObject:ext]) ext = @"jpg";

	return [self importData:data ext:ext];
}

- (NSString *)importData:(NSData *)data ext:(NSString *)ext {
	if (!data.length) return nil;

	NSURL *dir = [self assetsDirectoryURL];
	if (!dir) return nil;

	unsigned char digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, (CC_LONG)data.length, digest);

	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
	for (NSUInteger i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];

	NSString *name = [hex stringByAppendingPathExtension:ext.length ? ext : @"jpg"];
	NSURL *dst = [dir URLByAppendingPathComponent:name];

	if (![NSFileManager.defaultManager fileExistsAtPath:dst.path]) {
		NSError *err = nil;
		if (![data writeToURL:dst options:NSDataWritingAtomic error:&err]) {
			NSLog(@"[RyukGram][ChatBG] write failed: %@", err);
			return nil;
		}
	}

	[self appendLibraryAsset:name];
	[self postChange];
	return name;
}

#pragma mark - Reset

- (void)resetAll {
	NSURL *dir = [self assetsDirectoryURL];

	if (dir) {
		NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil];
		for (NSURL *file in files) [NSFileManager.defaultManager removeItemAtURL:file error:nil];
	}

	[NSUserDefaults.standardUserDefaults removeObjectForKey:SCIPrefChatBackgroundLibrary];
	[NSUserDefaults.standardUserDefaults removeObjectForKey:SCIPrefChatBackgroundPerImage];

	[SCIAccountScopedDefaults removeObjectForKey:SCIPrefChatBackgroundThreadMap];
	[SCIAccountScopedDefaults removeObjectForKey:SCIPrefChatBackgroundDefaultAsset];
	[SCIAccountScopedDefaults removeObjectForKey:SCIPrefChatBackgroundThreadMeta];

	[self postChange];
}

@end