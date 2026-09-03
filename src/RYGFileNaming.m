#import "RYGFileNaming.h"
#import "Utils.h"
#import "Gallery/RYGGallerySaveMetadata.h"

static NSString *const kRYGNamePrefixPref = @"dl_name_prefix";
static NSString *const kRYGNamePrefix = @"ryuk_";
static NSUInteger const kRYGMaxComponentLength = 48;

#pragma mark - Extensions

static NSSet<NSString *> *RYGAudioExts(void) {
	static NSSet<NSString *> *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		set = [NSSet setWithArray:@[ @"m4a", @"aac", @"mp3", @"ogg", @"opus", @"wav", @"aiff", @"flac" ]];
	});
	return set;
}

static NSSet<NSString *> *RYGVideoExts(void) {
	static NSSet<NSString *> *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ set = [NSSet setWithArray:@[ @"mp4", @"mov", @"m4v", @"webm" ]]; });
	return set;
}

static NSSet<NSString *> *RYGImageExts(void) {
	static NSSet<NSString *> *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ set = [NSSet setWithArray:@[ @"jpg", @"jpeg", @"png", @"heic", @"heif", @"webp", @"gif" ]]; });
	return set;
}

BOOL RYGGalleryExtensionIsAudio(NSString *ext) {
	return ext.length ? [RYGAudioExts() containsObject:ext.lowercaseString] : NO;
}

RYGGalleryMediaType RYGGalleryMediaTypeForExtension(NSString *ext) {
	NSString *e = ext.lowercaseString ?: @"";
	if ([e isEqualToString:@"gif"]) return RYGGalleryMediaTypeGIF;
	if ([RYGAudioExts() containsObject:e]) return RYGGalleryMediaTypeAudio;
	if ([RYGVideoExts() containsObject:e]) return RYGGalleryMediaTypeVideo;
	return RYGGalleryMediaTypeImage;
}

static NSString *RYGGalleryNormalizedExtension(NSString *ext, RYGGalleryMediaType mediaType) {
	NSString *e = ext.length ? ext.lowercaseString : @"";
	if (e.length > 0 && e.length <= 5) {
		if ([RYGImageExts() containsObject:e] || [RYGVideoExts() containsObject:e] || [RYGAudioExts() containsObject:e]) {
			return [e isEqualToString:@"jpeg"] ? @"jpg" : e;
		}
	}
	switch (mediaType) {
		case RYGGalleryMediaTypeVideo: return @"mp4";
		case RYGGalleryMediaTypeAudio: return @"m4a";
		case RYGGalleryMediaTypeGIF:   return @"gif";
		case RYGGalleryMediaTypeImage:
		default:					   return @"jpg";
	}
}

#pragma mark - Stem pieces

static NSString *RYGSanitizedComponent(NSString *raw) {
	if (![raw isKindOfClass:NSString.class] || !raw.length) return @"";

	NSMutableString *out = [NSMutableString stringWithCapacity:MIN(kRYGMaxComponentLength, raw.length)];
	[raw enumerateSubstringsInRange:NSMakeRange(0, raw.length)
						    options:NSStringEnumerationByComposedCharacterSequences
						 usingBlock:^(NSString *substring, __unused NSRange r, __unused NSRange er, BOOL *stop) {
		if (out.length >= kRYGMaxComponentLength) { *stop = YES; return; }
		unichar c = substring.length == 1 ? [substring characterAtIndex:0] : 0;
		BOOL keep = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
			|| c == '-' || c == '.' || c == '_';
		[out appendString:keep ? substring : @"-"];
	}];

	NSString *clean = out;
	while ([clean containsString:@"--"]) clean = [clean stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
	while ([clean containsString:@"__"]) clean = [clean stringByReplacingOccurrencesOfString:@"__" withString:@"_"];
	return [clean stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".-_"]];
}

static NSString *RYGStamp(NSDate *date) {
	static NSDateFormatter *fmt;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		fmt = [NSDateFormatter new];
		fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		fmt.dateFormat = @"yyyy-MM-dd_HH-mm-ss";
	});
	fmt.timeZone = NSTimeZone.localTimeZone;
	return [fmt stringFromDate:(date ?: NSDate.date)];
}

static NSString *RYGPrefix(void) {
	return [RYGUtils getBoolPref:kRYGNamePrefixPref] ? kRYGNamePrefix : @"";
}

// Second alternative still matches names written before the readable stamp.
static BOOL RYGIsGeneratedStem(NSString *stem) {
	if (!stem.length) return NO;

	static NSRegularExpression *re;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		re = [NSRegularExpression regularExpressionWithPattern:@"_(\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}-\\d{2}|\\d{8}_\\d{6})(_\\d+)?$"
													  options:0
														error:nil];
	});
	return [re firstMatchInString:stem options:0 range:NSMakeRange(0, stem.length)] != nil;
}

static BOOL RYGLooksLikeUUID(NSString *base) {
	if (base.length < 32 || base.length > 40) return NO;
	return [[NSUUID alloc] initWithUUIDString:base] != nil;
}

static BOOL RYGLooksLikeScratch(NSString *base) {
	return [base hasPrefix:@"ryuk_tmp_"] || [base hasPrefix:@"ryg_tmp_"];
}

@implementation RYGFileName

+ (NSString *)contextSlugForSource:(RYGGallerySource)source {
	switch (source) {
		case RYGGallerySourceFeed:		return @"feed";
		case RYGGallerySourceStories:	return @"story";
		case RYGGallerySourceReels:		return @"reel";
		case RYGGallerySourceProfile:	return @"profile-photo";
		case RYGGallerySourceDMs:		return @"dm";
		case RYGGallerySourceThumbnail:	return @"thumbnail";
		case RYGGallerySourceNotes:		return @"note";
		case RYGGallerySourceComments:	return @"comment";
		case RYGGallerySourceInstants:	return @"instant";
		case RYGGallerySourceCalls:		return @"call";
		case RYGGallerySourceImported:	return @"import";
		case RYGGallerySourceOther:
		default:						return @"media";
	}
}

+ (NSString *)stemForUsername:(NSString *)username
					  context:(NSString *)context
						 date:(NSDate *)date
						index:(NSInteger)index {
	NSString *user = RYGSanitizedComponent(username);
	NSString *ctx = RYGSanitizedComponent(context);
	if (!ctx.length) ctx = @"media";

	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	if (user.length) [parts addObject:[@"@" stringByAppendingString:user]];
	[parts addObject:ctx];

	NSString *seq = index > 0 ? [NSString stringWithFormat:@"_%ld", (long)index] : @"";
	return [NSString stringWithFormat:@"%@%@_%@%@", RYGPrefix(), [parts componentsJoinedByString:@"_"], RYGStamp(date), seq];
}

+ (NSString *)stemForMetadata:(RYGGallerySaveMetadata *)metadata {
	NSString *context = metadata.contextLabel.length
		? metadata.contextLabel
		: [self contextSlugForSource:(RYGGallerySource)metadata.source];
	return [self stemForUsername:metadata.sourceUsername
						 context:context
							date:metadata.mediaDate
						   index:metadata.sequenceIndex];
}

+ (NSString *)stemForURL:(NSURL *)url metadata:(RYGGallerySaveMetadata *)metadata {
	NSString *base = [url.lastPathComponent stringByDeletingPathExtension] ?: @"";

	// Without this, download → share → gallery stacks a second stamp every hop.
	if (RYGIsGeneratedStem(base)) return base;

	BOOL described = metadata.sourceUsername.length
		|| metadata.contextLabel.length
		|| (RYGGallerySource)metadata.source != RYGGallerySourceOther;
	if (described) return [self stemForMetadata:metadata];

	NSString *clean = RYGLooksLikeUUID(base) || RYGLooksLikeScratch(base) ? @"" : RYGSanitizedComponent(base);
	if (!clean.length) {
		return [self stemForUsername:nil context:nil date:metadata.mediaDate index:metadata.sequenceIndex];
	}
	return [NSString stringWithFormat:@"%@%@_%@", RYGPrefix(), clean, RYGStamp(metadata.mediaDate)];
}

+ (NSString *)nameForURL:(NSURL *)url
			   mediaType:(RYGGalleryMediaType)mediaType
				metadata:(RYGGallerySaveMetadata *)metadata {
	NSString *ext = RYGGalleryNormalizedExtension(url.pathExtension, mediaType);
	return [[self stemForURL:url metadata:metadata] stringByAppendingPathExtension:ext];
}

+ (NSString *)exportNameForURL:(NSURL *)url metadata:(RYGGallerySaveMetadata *)metadata {
	NSString *stem = [self stemForURL:url metadata:metadata];
	NSString *ext = url.pathExtension;
	return ext.length ? [stem stringByAppendingPathExtension:ext] : stem;
}

+ (NSString *)uniqueName:(NSString *)name inDirectory:(NSString *)directory {
	NSFileManager *fm = NSFileManager.defaultManager;
	if (!directory.length || ![fm fileExistsAtPath:[directory stringByAppendingPathComponent:name]]) return name;

	NSString *stem = [name stringByDeletingPathExtension];
	NSString *ext = name.pathExtension;
	for (NSInteger n = 1; n < 1000; n++) {
		NSString *candidate = [[NSString stringWithFormat:@"%@-%ld", stem, (long)n] stringByAppendingPathExtension:ext];
		if (![fm fileExistsAtPath:[directory stringByAppendingPathComponent:candidate]]) return candidate;
	}
	return [[NSString stringWithFormat:@"%@-%@", stem, NSUUID.UUID.UUIDString] stringByAppendingPathExtension:ext];
}

@end
