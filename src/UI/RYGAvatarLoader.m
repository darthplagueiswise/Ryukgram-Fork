#import "RYGAvatarLoader.h"
#import "../RYGImageCache.h"
#import "../Features/StoriesAndMessages/RYGDirectUserResolver.h"
#import "../Features/StoriesAndMessages/RYGDirectThreadInfo.h"
#import "../Networking/RYGInstagramAPI.h"
#import "../Utils.h"

NSString *const RYGAvatarLoadedNotification = @"RYGAvatarLoadedNotification";

static NSCache<NSString *, UIImage *> *rygAvatarCache(void) {
	static NSCache *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSCache new];
		cache.countLimit = 150;
	});
	return cache;
}

static NSMutableSet<NSString *> *rygAvatarLoading(void) {
	static NSMutableSet *set;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ set = [NSMutableSet new]; });
	return set;
}

// 48pt gray disc + glyph so it sits in the cell like a real profile picture.
static UIImage *rygAvatarPlaceholder(BOOL group) {
	BOOL dark = UITraitCollection.currentTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
	static NSMutableDictionary<NSString *, UIImage *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });

	NSString *key = [NSString stringWithFormat:@"%d-%d", group, dark];
	UIImage *img = cache[key];
	if (img) return img;

	CGSize size = CGSizeMake(48.0, 48.0);
	UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
	fmt.opaque = NO;

	UIImage *glyph = [UIImage systemImageNamed:group ? @"person.2.fill" : @"person.fill"
							 withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium]];
	UIColor *disc = dark ? [UIColor colorWithWhite:0.25 alpha:1] : [UIColor colorWithWhite:0.78 alpha:1];
	UIColor *tint = dark ? [UIColor colorWithWhite:0.55 alpha:1] : UIColor.whiteColor;

	img = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
		[disc setFill];
		[[UIBezierPath bezierPathWithOvalInRect:(CGRect){CGPointZero, size}] fill];

		UIImage *tinted = [glyph imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
		CGSize gs = tinted.size;
		[tinted drawInRect:CGRectMake((size.width - gs.width) / 2.0, (size.height - gs.height) / 2.0, gs.width, gs.height)];
	}];

	if (img) cache[key] = img;
	return img;
}

static UIImage *rygRoundedAvatar(UIImage *src) {
	if (!src) return nil;

	CGSize size = CGSizeMake(48.0, 48.0);
	UIGraphicsImageRendererFormat *fmt = UIGraphicsImageRendererFormat.preferredFormat;
	fmt.opaque = NO;

	return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {
		[[UIBezierPath bezierPathWithOvalInRect:(CGRect){CGPointZero, size}] addClip];
		[src drawInRect:(CGRect){CGPointZero, size}];
	}];
}

static NSString *rygAvatarText(id v) {
	return [v isKindOfClass:NSString.class] ? v : @"";
}

// pk/thread → backfilled pic URL. Memory-only; the image itself disk-caches.
static NSMutableDictionary<NSString *, NSString *> *rygPKURLCache(void) {
	static NSMutableDictionary *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ map = [NSMutableDictionary new]; });
	return map;
}

static void rygBackfillPicForPK(NSString *pk) {
	static NSMutableSet<NSString *> *inflight;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inflight = [NSMutableSet new]; });

	@synchronized (inflight) {
		if ([inflight containsObject:pk]) return;
		[inflight addObject:pk];
	}

	[RYGInstagramAPI sendRequestWithMethod:@"GET"
									  path:[NSString stringWithFormat:@"users/%@/info/", pk]
									  body:nil
								completion:^(NSDictionary *resp, NSError *error) {
		@synchronized (inflight) { [inflight removeObject:pk]; }

		NSDictionary *user = [resp[@"user"] isKindOfClass:NSDictionary.class] ? resp[@"user"] : nil;
		NSString *pic = rygAvatarText(user[@"profile_pic_url"]);
		if (!pic.length) return;

		@synchronized (rygPKURLCache()) { rygPKURLCache()[pk] = pic; }
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSNotificationCenter.defaultCenter postNotificationName:RYGAvatarLoadedNotification object:nil];
		});
	}];
}

// thread_image ships as a URL string, a url/uri dict, or a media dict with
// image_versions2.candidates depending on IG version.
static NSString *rygImageURLFromThreadImage(id ti) {
	if ([ti isKindOfClass:NSString.class]) return (NSString *)ti;
	if (![ti isKindOfClass:NSDictionary.class]) return nil;

	NSDictionary *d = ti;
	NSString *url = rygAvatarText(d[@"url"]);
	if (!url.length) url = rygAvatarText(d[@"uri"]);
	if (url.length) return url;

	NSDictionary *iv2 = [d[@"image_versions2"] isKindOfClass:NSDictionary.class] ? d[@"image_versions2"] : nil;
	NSArray *candidates = [iv2[@"candidates"] isKindOfClass:NSArray.class] ? iv2[@"candidates"] : nil;
	NSDictionary *best = nil;
	for (NSDictionary *c in candidates) {
		if (![c isKindOfClass:NSDictionary.class]) continue;
		if (!best || [c[@"width"] doubleValue] > [best[@"width"] doubleValue]) best = c;
	}
	return rygAvatarText(best[@"url"]);
}

// Group avatar: live direct cache first (no API call), then the thread API.
static void rygBackfillGroupAvatarForThread(NSString *tid) {
	static NSMutableSet<NSString *> *inflight;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ inflight = [NSMutableSet new]; });

	@synchronized (inflight) {
		if ([inflight containsObject:tid]) return;
		[inflight addObject:tid];
	}

	void (^finish)(NSString *) = ^(NSString *pic) {
		@synchronized (inflight) { [inflight removeObject:tid]; }
		if (!pic.length) return;
		@synchronized (rygPKURLCache()) { rygPKURLCache()[[@"t:" stringByAppendingString:tid]] = pic; }
		dispatch_async(dispatch_get_main_queue(), ^{
			[NSNotificationCenter.defaultCenter postNotificationName:RYGAvatarLoadedNotification object:nil];
		});
	};

	NSString *owner = [RYGUtils currentUserPK];
	[RYGDirectThreadInfo fetchThreadId:tid ownerPK:owner completion:^(id thread) {
		NSDictionary *gi = thread ? [RYGDirectThreadInfo groupInfoForThread:thread viewerPK:owner] : nil;
		NSString *img = [gi[@"image"] isKindOfClass:NSString.class] ? gi[@"image"] : nil;
		if (img.length) { finish(img); return; }

		[RYGInstagramAPI sendRequestWithMethod:@"GET"
										  path:[NSString stringWithFormat:@"direct_v2/threads/%@/", tid]
										  body:nil
									completion:^(NSDictionary *resp, __unused NSError *error) {
			NSDictionary *t = [resp[@"thread"] isKindOfClass:NSDictionary.class] ? resp[@"thread"] : nil;
			NSString *pic = [t[@"thread_avatar_url"] isKindOfClass:NSString.class] ? t[@"thread_avatar_url"] : nil;
			if (!pic.length) pic = rygImageURLFromThreadImage(t[@"thread_image"]);
			finish(pic);
		}];
	}];
}

static NSDictionary *rygSingleUser(NSDictionary *e) {
	NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
	return users.count == 1 && [users.firstObject isKindOfClass:NSDictionary.class] ? users.firstObject : nil;
}

static NSString *rygAvatarURLForEntry(NSDictionary *e) {
	NSString *url = rygAvatarText(e[@"avatarURL"]);
	if (url.length) return url;

	url = rygAvatarText(e[@"profilePicURL"]);
	if (url.length) return url;

	if ([e[@"isGroup"] boolValue]) {
		NSString *tid = rygAvatarText(e[@"threadId"]);
		if (!tid.length) return @"";

		@synchronized (rygPKURLCache()) {
			NSString *cached = rygPKURLCache()[[@"t:" stringByAppendingString:tid]];
			if (cached.length) return cached;
		}

		rygBackfillGroupAvatarForThread(tid);
		return @"";
	}

	NSDictionary *u = rygSingleUser(e);
	url = rygAvatarText(u[@"profilePicURL"]);
	if (url.length) return url;

	NSString *pk = rygAvatarText(e[@"pk"]);
	if (!pk.length) pk = rygAvatarText(u[@"pk"]);
	if (!pk.length) {
		NSArray *users = [e[@"users"] isKindOfClass:NSArray.class] ? e[@"users"] : @[];
		for (NSDictionary *cand in users) {
			if ([cand isKindOfClass:NSDictionary.class] && rygAvatarText(cand[@"pk"]).length) { pk = rygAvatarText(cand[@"pk"]); break; }
		}
	}
	if (!pk.length) return @"";

	@synchronized (rygPKURLCache()) {
		NSString *cached = rygPKURLCache()[pk];
		if (cached.length) return cached;
	}

	NSString *resolved = rygDirectUserResolverProfilePicURLStringForPK(pk);
	if (resolved.length) return resolved;

	rygBackfillPicForPK(pk);
	return @"";
}

@implementation RYGAvatarLoader

+ (UIImage *)avatarForEntry:(NSDictionary *)entry {
	BOOL group = [entry[@"isGroup"] boolValue];
	return [self avatarForURLString:rygAvatarURLForEntry(entry) group:group];
}

+ (UIImage *)avatarForURLString:(NSString *)urlString group:(BOOL)group {
	if (!urlString.length) return rygAvatarPlaceholder(group);

	UIImage *cached = [rygAvatarCache() objectForKey:urlString];
	if (cached) return cached;

	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) return rygAvatarPlaceholder(group);

	@synchronized (rygAvatarLoading()) {
		if ([rygAvatarLoading() containsObject:urlString]) return rygAvatarPlaceholder(group);
		[rygAvatarLoading() addObject:urlString];
	}

	// Cache key drops the query string — CDN signatures rotate, the asset path doesn't.
	[RYGImageCache loadImageFromURL:url cacheKey:(url.path.length ? url.path : nil) completion:^(UIImage *image) {
		UIImage *rounded = rygRoundedAvatar(image);
		if (rounded) [rygAvatarCache() setObject:rounded forKey:urlString];

		@synchronized (rygAvatarLoading()) {
			[rygAvatarLoading() removeObject:urlString];
		}

		if (rounded) {
			[NSNotificationCenter.defaultCenter postNotificationName:RYGAvatarLoadedNotification object:nil];
		}
	}];

	return rygAvatarPlaceholder(group);
}

@end
