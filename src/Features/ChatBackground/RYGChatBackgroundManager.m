#import "RYGChatBackgroundManager.h"
#import "../../Utils.h"
#import "../../RYGAccountScopedDefaults.h"
#import "../Theme/RYGTheme.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>

NSString *const RYGChatBackgroundDidChangeNotification = @"RYGChatBackgroundDidChangeNotification";
NSString *const RYGChatBackgroundRenderDirtyNotification = @"RYGChatBackgroundRenderDirtyNotification";

NSString *const RYGPrefChatBackgroundEnabled = @"chat_bg_enabled";
NSString *const RYGPrefChatBackgroundDefaultAsset = @"chat_bg_default_asset";
NSString *const RYGPrefChatBackgroundThreadMap = @"chat_bg_thread_map";
NSString *const RYGPrefChatBackgroundLibrary = @"chat_bg_library";
NSString *const RYGPrefChatBackgroundPerImage = @"chat_bg_per_image";
NSString *const RYGPrefChatBackgroundThreadMeta = @"chat_bg_thread_meta";

static NSString *const kAssetsDirName = @"ChatBackgrounds";
static NSString *const kOpacity = @"opacity";
static NSString *const kBlur = @"blur";
static NSString *const kDim = @"dim";
static NSString *const kAutoBubble = @"auto_bubble";
static NSString *const kBubbleColors = @"bubble_colors";
static NSString *const kBubbleSides = @"bubble_sides";
static NSString *const kBubbleTextColor = @"bubble_text_color";
static NSString *const kBubbleGradientDir = @"bubble_gradient_dir";

static double RYGClamp(double v, double min, double max) {
	if (isnan(v)) return min;
	return MIN(MAX(v, min), max);
}

static CIContext *RYGSharedCIContext(void) {
	static CIContext *ctx;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		ctx = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];
	});
	return ctx;
}

@interface RYGChatBackgroundManager ()
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *imageCache;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *processedCache;
@property (nonatomic, strong) NSCache<NSString *, UIColor *> *bubbleColorCache;
@end

// Most vibrant color in the image (skips near-gray and extremes), or the average as fallback.
static UIColor *RYGVibrantColor(UIImage *image) {
	if (!image.CGImage) return nil;

	const int N = 24;
	unsigned char *buf = calloc(N * N * 4, 1);
	if (!buf) return nil;

	CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(buf, N, N, 8, N * 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(cs);
	if (!ctx) { free(buf); return nil; }
	CGContextDrawImage(ctx, CGRectMake(0, 0, N, N), image.CGImage);
	CGContextRelease(ctx);

	double bestScore = -1, bR = 0, bG = 0, bB = 0;
	double sumR = 0, sumG = 0, sumB = 0; int sumN = 0;

	for (int i = 0; i < N * N; i++) {
		double r = buf[i * 4] / 255.0, g = buf[i * 4 + 1] / 255.0, b = buf[i * 4 + 2] / 255.0;
		double a = buf[i * 4 + 3] / 255.0;
		if (a < 0.5) continue;
		sumR += r; sumG += g; sumB += b; sumN++;

		double mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
		double sat = mx <= 0.001 ? 0 : (mx - mn) / mx;
		if (sat < 0.18 || mx < 0.15 || mx > 0.97) continue;

		double score = sat * (0.55 + 0.45 * mx);
		if (score > bestScore) { bestScore = score; bR = r; bG = g; bB = b; }
	}
	free(buf);

	if (bestScore < 0) {
		if (!sumN) return nil;
		return [UIColor colorWithRed:sumR / sumN green:sumG / sumN blue:sumB / sumN alpha:1.0];
	}

	UIColor *c = [UIColor colorWithRed:bR green:bG blue:bB alpha:1.0];
	CGFloat h, s, v, a;
	if ([c getHue:&h saturation:&s brightness:&v alpha:&a]) {
		s = MIN(s * 1.1, 1.0);
		v = RYGClamp(v, 0.30, 0.85);
		c = [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
	}
	return c;
}

static double RYGLinearChannel(double c) {
	return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

static double RYGRelativeLuminance(UIColor *c) {
	CGFloat r, g, b, a, w;
	if ([c getRed:&r green:&g blue:&b alpha:&a]) {
		return 0.2126 * RYGLinearChannel(r) + 0.7152 * RYGLinearChannel(g) + 0.0722 * RYGLinearChannel(b);
	}
	if ([c getWhite:&w alpha:&a]) return RYGLinearChannel(w);
	return 1.0;
}

static double RYGContrastRatio(double l1, double l2) {
	double hi = MAX(l1, l2), lo = MIN(l1, l2);
	return (hi + 0.05) / (lo + 0.05);
}

// Pure white vs near-black, whichever keeps the worst endpoint readable. Worst-case
// across both gradient stops so text doesn't wash out at one end.
static UIColor *RYGContrastColorForColors(NSArray<UIColor *> *colors) {
	if (!colors.count) return UIColor.whiteColor;

	UIColor *black = [UIColor colorWithWhite:0.10 alpha:1.0];
	double whiteWorst = INFINITY, blackWorst = INFINITY;

	for (UIColor *c in colors) {
		double l = RYGRelativeLuminance(c);
		whiteWorst = MIN(whiteWorst, RYGContrastRatio(1.0, l));
		blackWorst = MIN(blackWorst, RYGContrastRatio(RYGRelativeLuminance(black), l));
	}

	return whiteWorst >= blackWorst ? UIColor.whiteColor : black;
}

static UIColor *RYGDarkerVariant(UIColor *c) {
	CGFloat h, s, v, a;
	if ([c getHue:&h saturation:&s brightness:&v alpha:&a]) {
		return [UIColor colorWithHue:h saturation:MIN(s * 1.05, 1.0) brightness:RYGClamp(v * 0.62, 0.10, 1.0) alpha:a];
	}
	return c;
}

@implementation RYGChatBackgroundManager

+ (instancetype)shared {
	static RYGChatBackgroundManager *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [RYGChatBackgroundManager new]; });
	return s;
}

- (instancetype)init {
	if ((self = [super init])) {
		_imageCache = [NSCache new];
		_imageCache.countLimit = 16;

		_processedCache = [NSCache new];
		_processedCache.countLimit = 24;

		_bubbleColorCache = [NSCache new];
		_bubbleColorCache.countLimit = 32;
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

// Observers relayout IG views, so notifications must fire on the main thread
// (imports can complete on a background queue).
static void rygPostOnMain(void (^block)(void)) {
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

- (void)postChange {
	[self.imageCache removeAllObjects];
	[self.processedCache removeAllObjects];
	[self.bubbleColorCache removeAllObjects];
	rygPostOnMain(^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGChatBackgroundDidChangeNotification object:nil];
		[NSNotificationCenter.defaultCenter postNotificationName:RYGChatBackgroundRenderDirtyNotification object:nil];
	});
}

- (void)postRenderDirty {
	[self.processedCache removeAllObjects];
	rygPostOnMain(^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGChatBackgroundRenderDirtyNotification object:nil];
	});
}

- (BOOL)fileExistsForAsset:(NSString *)asset {
	NSURL *url = [self urlForRelativeAsset:asset];
	return url.path.length && [NSFileManager.defaultManager fileExistsAtPath:url.path];
}

#pragma mark - Prefs

- (BOOL)isEnabled {
	return [RYGUtils getBoolPref:RYGPrefChatBackgroundEnabled];
}

- (NSString *)defaultAsset {
	id v = [RYGAccountScopedDefaults objectForKey:RYGPrefChatBackgroundDefaultAsset];
	return [v isKindOfClass:NSString.class] && [v length] ? v : nil;
}

- (void)setDefaultAsset:(NSString *)relPath {
	NSString *old = [self defaultAsset] ?: @"";
	NSString *new = relPath ?: @"";
	if ([old isEqualToString:new]) return;

	if (new.length) [RYGAccountScopedDefaults setObject:new forKey:RYGPrefChatBackgroundDefaultAsset];
	else [RYGAccountScopedDefaults removeObjectForKey:RYGPrefChatBackgroundDefaultAsset];

	[self postChange];
}

#pragma mark - Library

- (NSArray<NSString *> *)libraryAssets {
	id raw = [NSUserDefaults.standardUserDefaults objectForKey:RYGPrefChatBackgroundLibrary];
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
	[NSUserDefaults.standardUserDefaults setObject:list forKey:RYGPrefChatBackgroundLibrary];
}

- (void)deleteLibraryAsset:(NSString *)relPath {
	if (!relPath.length) return;

	NSURL *url = [self urlForRelativeAsset:relPath];
	if (url) [NSFileManager.defaultManager removeItemAtURL:url error:nil];

	NSMutableArray *library = [[self libraryAssets] mutableCopy];
	[library removeObject:relPath];
	[NSUserDefaults.standardUserDefaults setObject:library forKey:RYGPrefChatBackgroundLibrary];

	if ([[self defaultAsset] isEqualToString:relPath]) {
		[RYGAccountScopedDefaults removeObjectForKey:RYGPrefChatBackgroundDefaultAsset];
	}

	NSMutableDictionary *threadMap = [[self allThreadAssets] mutableCopy];
	for (NSString *tid in [threadMap.allKeys copy]) {
		if ([threadMap[tid] isEqualToString:relPath]) [threadMap removeObjectForKey:tid];
	}
	[RYGAccountScopedDefaults setObject:threadMap forKey:RYGPrefChatBackgroundThreadMap];

	NSMutableDictionary *perImage = [[self perImageDict] mutableCopy];
	[perImage removeObjectForKey:relPath];
	[NSUserDefaults.standardUserDefaults setObject:perImage forKey:RYGPrefChatBackgroundPerImage];

	[self.imageCache removeObjectForKey:relPath];
	[self postChange];
}

// Re-edit yields a new hash: migrate default/thread/per-image refs, keep the library
// slot, delete the old file.
- (void)replaceAsset:(NSString *)oldRel withAsset:(NSString *)newRel {
	if (!oldRel.length || !newRel.length || [oldRel isEqualToString:newRel]) return;

	if ([[self defaultAsset] isEqualToString:oldRel]) [self setDefaultAsset:newRel];

	NSMutableDictionary *threadMap = [[self allThreadAssets] mutableCopy];
	for (NSString *tid in [threadMap.allKeys copy])
		if ([threadMap[tid] isEqualToString:oldRel]) threadMap[tid] = newRel;
	[RYGAccountScopedDefaults setObject:threadMap forKey:RYGPrefChatBackgroundThreadMap];

	NSMutableDictionary *perImage = [[self perImageDict] mutableCopy];
	if (perImage[oldRel] && !perImage[newRel]) perImage[newRel] = perImage[oldRel];
	[perImage removeObjectForKey:oldRel];
	[NSUserDefaults.standardUserDefaults setObject:perImage forKey:RYGPrefChatBackgroundPerImage];

	NSMutableArray *library = [[self libraryAssets] mutableCopy];
	NSUInteger oldIdx = [library indexOfObject:oldRel];
	[library removeObject:newRel];
	if (oldIdx != NSNotFound) {
		library[oldIdx] = newRel;
	} else if (![library containsObject:newRel]) {
		[library addObject:newRel];
	}
	[NSUserDefaults.standardUserDefaults setObject:library forKey:RYGPrefChatBackgroundLibrary];

	NSURL *oldURL = [self urlForRelativeAsset:oldRel];
	if (oldURL) [NSFileManager.defaultManager removeItemAtURL:oldURL error:nil];
	[self.imageCache removeObjectForKey:oldRel];

	[self postChange];
}

#pragma mark - Thread assets

- (NSDictionary<NSString *, NSString *> *)allThreadAssets {
	id raw = [RYGAccountScopedDefaults dictForKey:RYGPrefChatBackgroundThreadMap];
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

	[RYGAccountScopedDefaults setObject:map forKey:RYGPrefChatBackgroundThreadMap];
	[self postChange];
}

- (void)clearAssetForThreadID:(NSString *)threadID {
	if (!threadID.length) return;
	[self setAsset:nil forThreadID:threadID];
	[self setMetadata:nil forThreadID:threadID];
}

#pragma mark - Metadata

- (NSDictionary *)metaDict {
	id raw = [RYGAccountScopedDefaults dictForKey:RYGPrefChatBackgroundThreadMeta];
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

	[RYGAccountScopedDefaults setObject:map forKey:RYGPrefChatBackgroundThreadMeta];
	[NSNotificationCenter.defaultCenter postNotificationName:RYGChatBackgroundDidChangeNotification object:nil];
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

	UIImage *img = [RYGChatBackgroundManager isVideoAsset:asset]
		? [self posterFrameForURL:url]
		: [UIImage imageWithContentsOfFile:url.path];
	if (img) [self.imageCache setObject:img forKey:asset];

	return img;
}

- (UIImage *)posterFrameForURL:(NSURL *)url {
	if (!url) return nil;

	AVAsset *asset = [AVAsset assetWithURL:url];
	AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
	gen.appliesPreferredTrackTransform = YES;
	gen.maximumSize = CGSizeMake(1080, 1080);

	CGImageRef cg = [gen copyCGImageAtTime:CMTimeMakeWithSeconds(0.0, 600) actualTime:NULL error:NULL];
	if (!cg) return nil;

	UIImage *img = [UIImage imageWithCGImage:cg];
	CGImageRelease(cg);
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

			CGImageRef cg = [RYGSharedCIContext() createCGImage:gauss.outputImage fromRect:ci.extent];
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
	id raw = [NSUserDefaults.standardUserDefaults objectForKey:RYGPrefChatBackgroundPerImage];
	return [raw isKindOfClass:NSDictionary.class] ? raw : @{};
}

- (NSDictionary *)settingsForAsset:(NSString *)asset {
	if (!asset.length) return nil;
	id v = [self perImageDict][asset];
	return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

- (double)valueForAsset:(NSString *)asset key:(NSString *)key fallback:(double)fallback min:(double)min max:(double)max {
	NSNumber *v = [self settingsForAsset:asset][key];
	return v ? RYGClamp(v.doubleValue, min, max) : fallback;
}

- (void)setSetting:(double)value forAsset:(NSString *)asset key:(NSString *)key min:(double)min max:(double)max {
	if (!asset.length || !key.length) return;

	double clamped = RYGClamp(value, min, max);
	NSDictionary *oldEntry = [self settingsForAsset:asset] ?: @{};
	NSNumber *old = oldEntry[key];

	if (old && fabs(old.doubleValue - clamped) < 0.0001) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [oldEntry mutableCopy];
	entry[key] = @(clamped);
	map[asset] = entry;

	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
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
	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postRenderDirty];
}

#pragma mark - Auto bubble color

- (BOOL)autoBubbleEnabledForAsset:(NSString *)asset {
	return [[self settingsForAsset:asset][kAutoBubble] boolValue];
}

- (void)setAutoBubble:(BOOL)on forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [([self settingsForAsset:asset] ?: @{}) mutableCopy];
	entry[kAutoBubble] = @(on);
	map[asset] = entry;

	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postChange];
}

- (UIColor *)autoBubbleColorForAsset:(NSString *)asset {
	if (!asset.length) return nil;

	UIColor *cached = [self.bubbleColorCache objectForKey:asset];
	if (cached) return cached;

	UIImage *img = [self imageForAsset:asset];
	UIColor *color = RYGVibrantColor(img);
	if (color) [self.bubbleColorCache setObject:color forKey:asset];
	return color;
}

- (NSArray<UIColor *> *)bubbleColorOverrideForAsset:(NSString *)asset {
	id raw = [self settingsForAsset:asset][kBubbleColors];
	if (![raw isKindOfClass:NSArray.class] || ![(NSArray *)raw count]) return nil;

	NSMutableArray *out = [NSMutableArray new];
	for (id hex in (NSArray *)raw) {
		UIColor *c = [RYGTheme colorFromHex:hex];
		if (c) [out addObject:c];
	}
	return out.count ? out : nil;
}

- (void)setBubbleColorOverride:(NSArray<UIColor *> *)colors forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [([self settingsForAsset:asset] ?: @{}) mutableCopy];

	if (colors.count) {
		NSMutableArray *hexes = [NSMutableArray new];
		for (UIColor *c in colors) [hexes addObject:[RYGTheme hexFromColor:c]];
		entry[kBubbleColors] = hexes;
	} else {
		[entry removeObjectForKey:kBubbleColors];
	}

	map[asset] = entry;
	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postChange];
}

- (NSArray<UIColor *> *)bubbleColorsForAsset:(NSString *)asset {
	NSArray<UIColor *> *override = [self bubbleColorOverrideForAsset:asset];
	if (override.count) return override;

	UIColor *derived = [self autoBubbleColorForAsset:asset];
	return derived ? @[derived] : @[];
}

- (UIColor *)autoBubbleTextColorForAsset:(NSString *)asset {
	UIColor *override = [self bubbleTextColorOverrideForAsset:asset];
	if (override) return override;

	NSArray<UIColor *> *colors = [self bubbleColorsForAsset:asset];
	return colors.count ? RYGContrastColorForColors(colors) : nil;
}

- (RYGBubbleSides)bubbleSidesForAsset:(NSString *)asset {
	NSNumber *v = [self settingsForAsset:asset][kBubbleSides];
	NSInteger raw = v ? v.integerValue : RYGBubbleSidesIncoming;
	if (raw < RYGBubbleSidesIncoming || raw > RYGBubbleSidesBoth) raw = RYGBubbleSidesIncoming;
	return (RYGBubbleSides)raw;
}

- (void)setBubbleSides:(RYGBubbleSides)sides forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [([self settingsForAsset:asset] ?: @{}) mutableCopy];
	entry[kBubbleSides] = @(sides);
	map[asset] = entry;

	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postChange];
}

- (BOOL)bubbleGradientForAsset:(NSString *)asset {
	return [self bubbleColorsForAsset:asset].count > 1;
}

- (void)setBubbleGradient:(BOOL)on forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSArray<UIColor *> *cur = [self bubbleColorsForAsset:asset];
	UIColor *base = cur.firstObject ?: [self autoBubbleColorForAsset:asset] ?: UIColor.systemBlueColor;

	if (on) {
		UIColor *second = cur.count > 1 ? cur[1] : RYGDarkerVariant(base);
		[self setBubbleColorOverride:@[base, second] forAsset:asset];
	} else {
		[self setBubbleColorOverride:@[base] forAsset:asset];
	}
}

- (RYGBubbleGradientDirection)bubbleGradientDirectionForAsset:(NSString *)asset {
	NSNumber *v = [self settingsForAsset:asset][kBubbleGradientDir];
	NSInteger raw = v ? v.integerValue : RYGBubbleGradientDirectionDiagonal;
	if (raw < RYGBubbleGradientDirectionVertical || raw > RYGBubbleGradientDirectionDiagonal) raw = RYGBubbleGradientDirectionDiagonal;
	return (RYGBubbleGradientDirection)raw;
}

- (void)setBubbleGradientDirection:(RYGBubbleGradientDirection)direction forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [([self settingsForAsset:asset] ?: @{}) mutableCopy];
	entry[kBubbleGradientDir] = @(direction);
	map[asset] = entry;

	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postChange];
}

- (UIColor *)bubbleTextColorOverrideForAsset:(NSString *)asset {
	id hex = [self settingsForAsset:asset][kBubbleTextColor];
	return [hex isKindOfClass:NSString.class] ? [RYGTheme colorFromHex:hex] : nil;
}

- (void)setBubbleTextColorOverride:(UIColor *)color forAsset:(NSString *)asset {
	if (!asset.length) return;

	NSMutableDictionary *map = [[self perImageDict] mutableCopy];
	NSMutableDictionary *entry = [([self settingsForAsset:asset] ?: @{}) mutableCopy];

	if (color) entry[kBubbleTextColor] = [RYGTheme hexFromColor:color];
	else [entry removeObjectForKey:kBubbleTextColor];

	map[asset] = entry;
	[NSUserDefaults.standardUserDefaults setObject:map forKey:RYGPrefChatBackgroundPerImage];
	[self postChange];
}

#pragma mark - Import

+ (BOOL)isVideoExtension:(NSString *)ext {
	return [@[@"mp4", @"mov", @"m4v"] containsObject:ext.lowercaseString];
}

+ (BOOL)isVideoAsset:(NSString *)relPath {
	return relPath.length && [self isVideoExtension:relPath.pathExtension];
}

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
	if ([RYGChatBackgroundManager isVideoExtension:ext]) return [self importData:data ext:ext];
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

	[NSUserDefaults.standardUserDefaults removeObjectForKey:RYGPrefChatBackgroundLibrary];
	[NSUserDefaults.standardUserDefaults removeObjectForKey:RYGPrefChatBackgroundPerImage];

	[RYGAccountScopedDefaults removeObjectForKey:RYGPrefChatBackgroundThreadMap];
	[RYGAccountScopedDefaults removeObjectForKey:RYGPrefChatBackgroundDefaultAsset];
	[RYGAccountScopedDefaults removeObjectForKey:RYGPrefChatBackgroundThreadMeta];

	[self postChange];
}

@end