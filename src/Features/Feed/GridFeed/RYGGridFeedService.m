#import "RYGGridFeedService.h"
#import "../../../Networking/RYGInstagramAPI.h"
#import "../../../RYGImageCache.h"
#import "../../../Utils.h"
#import <objc/message.h>

static CGFloat const kRYGGridFeedTargetThumbWidth = 640.0;
// Small on purpose: a big cache makes pagination grind through pages of duplicates.
static NSUInteger const kRYGGridCacheCap = 9;

// IG ids come as bare pk or full "pk_userpk"; normalize to bare so dedup is consistent.
static NSString *rygBarePK(id v) {
	NSString *s = [v isKindOfClass:[NSString class]] ? v : ([v respondsToSelector:@selector(stringValue)] ? [v stringValue] : nil);
	if (!s.length) return nil;
	NSRange u = [s rangeOfString:@"_"];
	return u.location != NSNotFound ? [s substringToIndex:u.location] : s;
}

static id rygVal(NSDictionary *d, NSString *k) {
	id v = [d isKindOfClass:[NSDictionary class]] ? d[k] : nil;
	return (v == (id)[NSNull null]) ? nil : v;
}
static NSInteger rygInt(NSDictionary *d, NSString *k) {
	id v = rygVal(d, k);
	return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}
static double rygDbl(NSDictionary *d, NSString *k) {
	id v = rygVal(d, k);
	return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0;
}
static BOOL rygBool(NSDictionary *d, NSString *k) {
	id v = rygVal(d, k);
	return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

static NSString *rygBestCandidateURL(NSDictionary *imageVersions2) {
	if (![imageVersions2 isKindOfClass:[NSDictionary class]]) return nil;
	NSArray *candidates = imageVersions2[@"candidates"];
	if (![candidates isKindOfClass:[NSArray class]] || !candidates.count) return nil;
	NSDictionary *best = nil;
	CGFloat bestScore = CGFLOAT_MAX;
	NSDictionary *widest = nil;
	CGFloat widestW = -1;
	for (NSDictionary *c in candidates) {
		if (![c isKindOfClass:[NSDictionary class]]) continue;
		NSString *url = c[@"url"];
		if (![url isKindOfClass:[NSString class]] || !url.length) continue;
		CGFloat w = [c[@"width"] doubleValue];
		if (w > widestW) { widestW = w; widest = c; }
		CGFloat score = fabs(w - kRYGGridFeedTargetThumbWidth);
		if (score < bestScore) { bestScore = score; best = c; }
	}
	return (best ?: widest)[@"url"];
}

@implementation RYGGridFeedPost

static BOOL rygMediaIsAd(NSDictionary *m) {
	id injected = m[@"injected"];
	if ([injected isKindOfClass:[NSDictionary class]] && [injected count]) return YES;
	id isAd = m[@"is_ad"];
	if ([isAd isKindOfClass:[NSNumber class]] && [isAd boolValue]) return YES;
	id adId = m[@"ad_id"];
	if ([adId isKindOfClass:[NSString class]] && [adId length]) return YES;
	id sponsor = m[@"sponsor_tags"];
	if ([sponsor isKindOfClass:[NSArray class]] && [sponsor count]) return YES;
	return NO;
}

+ (instancetype)postFromMediaDict:(NSDictionary *)media {
	if (![media isKindOfClass:[NSDictionary class]]) return nil;

	if ([RYGUtils getBoolPref:@"hide_ads"] && [RYGUtils getBoolPref:@"hide_ads_feed"] && rygMediaIsAd(media))
		return nil;

	NSString *pk = rygBarePK(rygVal(media, @"pk") ?: rygVal(media, @"id"));
	NSString *code = [rygVal(media, @"code") isKindOfClass:[NSString class]] ? rygVal(media, @"code") : nil;
	if (!pk.length && !code.length) return nil;

	RYGGridFeedPost *p = [RYGGridFeedPost new];
	p.pk = pk;
	NSString *fullID = [rygVal(media, @"id") isKindOfClass:[NSString class]] ? rygVal(media, @"id") : nil;
	p.mediaID = fullID ?: pk;
	p.code = code;
	p.mediaType = rygInt(media, @"media_type");
	p.likeCount = rygInt(media, @"like_count");
	p.commentCount = rygInt(media, @"comment_count");
	p.viewCount = rygInt(media, @"play_count") ?: rygInt(media, @"view_count");
	p.shareCount = rygInt(media, @"reshare_count") ?: rygInt(media, @"share_count");
	p.takenAt = rygDbl(media, @"taken_at");
	p.countsHidden = rygBool(media, @"like_and_view_counts_disabled");
	p.hasLiked = rygBool(media, @"has_liked");

	NSDictionary *user = rygVal(media, @"user");
	if ([user isKindOfClass:[NSDictionary class]]) {
		p.username = [rygVal(user, @"username") isKindOfClass:[NSString class]] ? rygVal(user, @"username") : nil;
		p.avatarURLString = [rygVal(user, @"profile_pic_url") isKindOfClass:[NSString class]] ? rygVal(user, @"profile_pic_url") : nil;
		id upk = rygVal(user, @"pk") ?: rygVal(user, @"pk_id");
		p.userPK = [upk isKindOfClass:[NSString class]] ? upk : ([upk respondsToSelector:@selector(stringValue)] ? [upk stringValue] : nil);
		NSDictionary *fs = rygVal(user, @"friendship_status");
		if ([fs isKindOfClass:[NSDictionary class]]) p.isFollowing = rygBool(fs, @"following");
	}

	NSDictionary *thumbSource = media;
	NSArray *carousel = rygVal(media, @"carousel_media");
	if ([carousel isKindOfClass:[NSArray class]] && carousel.count) {
		p.carouselCount = carousel.count;
		// Some carousel children lack image_versions2; pick the first that has a thumbnail.
		for (NSDictionary *child in carousel) {
			if ([child isKindOfClass:[NSDictionary class]] && rygVal(child, @"image_versions2")) { thumbSource = child; break; }
		}
	}
	p.thumbURLString = rygBestCandidateURL(rygVal(thumbSource, @"image_versions2"));
	if (!p.thumbURLString.length) return nil;
	return p;
}

+ (instancetype)postFromIGMedia:(id)media {
	if (!media) return nil;
	NSDictionary *fc = [RYGUtils fieldCacheForObject:media];
	NSURL *thumb = [RYGUtils getPhotoUrlForMedia:media];
	if (!thumb) return nil;

	NSString *pk = rygBarePK(rygVal(fc, @"pk"));
	if (!pk.length && [media respondsToSelector:@selector(pk)]) {
		id mpk = ((id(*)(id, SEL))objc_msgSend)(media, @selector(pk));
		pk = rygBarePK(mpk);
	}
	NSString *code = [rygVal(fc, @"code") isKindOfClass:[NSString class]] ? rygVal(fc, @"code") : nil;
	if (!pk.length && !code.length) return nil;

	RYGGridFeedPost *p = [RYGGridFeedPost new];
	p.pk = pk; p.mediaID = pk; p.code = code;
	p.thumbURLString = thumb.absoluteString;
	p.mediaType = rygInt(fc, @"media_type");
	p.likeCount = rygInt(fc, @"like_count");
	p.commentCount = rygInt(fc, @"comment_count");
	p.viewCount = rygInt(fc, @"play_count") ?: rygInt(fc, @"view_count");
	p.shareCount = rygInt(fc, @"reshare_count");
	p.carouselCount = rygInt(fc, @"carousel_media_count");
	p.takenAt = rygDbl(fc, @"taken_at");
	p.countsHidden = rygBool(fc, @"like_and_view_counts_disabled");
	p.hasLiked = rygBool(fc, @"has_liked");

	id userObj = rygVal(fc, @"user");
	NSDictionary *ufc = [userObj isKindOfClass:[NSDictionary class]] ? userObj : [RYGUtils fieldCacheForObject:userObj];
	if ([ufc isKindOfClass:[NSDictionary class]]) {
		p.username = [rygVal(ufc, @"username") isKindOfClass:[NSString class]] ? rygVal(ufc, @"username") : nil;
		p.avatarURLString = [rygVal(ufc, @"profile_pic_url") isKindOfClass:[NSString class]] ? rygVal(ufc, @"profile_pic_url") : nil;
		id upk = rygVal(ufc, @"pk") ?: rygVal(ufc, @"pk_id");
		p.userPK = [upk isKindOfClass:[NSString class]] ? upk : ([upk respondsToSelector:@selector(stringValue)] ? [upk stringValue] : nil);
		id fs = rygVal(ufc, @"friendship_status");
		if ([fs isKindOfClass:[NSDictionary class]]) p.isFollowing = rygBool(fs, @"following");
	}
	return p;
}

- (NSDictionary *)toDictionary {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	if (self.pk) d[@"pk"] = self.pk;
	if (self.mediaID) d[@"mid"] = self.mediaID;
	if (self.code) d[@"code"] = self.code;
	if (self.thumbURLString) d[@"thumb"] = self.thumbURLString;
	if (self.username) d[@"un"] = self.username;
	if (self.userPK) d[@"upk"] = self.userPK;
	if (self.avatarURLString) d[@"av"] = self.avatarURLString;
	d[@"mt"] = @(self.mediaType);
	d[@"lk"] = @(self.likeCount);
	d[@"cm"] = @(self.commentCount);
	d[@"vw"] = @(self.viewCount);
	d[@"sh"] = @(self.shareCount);
	d[@"cc"] = @(self.carouselCount);
	d[@"ta"] = @(self.takenAt);
	d[@"ch"] = @(self.countsHidden);
	d[@"hl"] = @(self.hasLiked);
	d[@"fo"] = @(self.isFollowing);
	return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)d {
	if (![d isKindOfClass:[NSDictionary class]]) return nil;
	NSString *thumb = d[@"thumb"];
	if (![thumb isKindOfClass:[NSString class]] || !thumb.length) return nil;
	RYGGridFeedPost *p = [RYGGridFeedPost new];
	p.pk = rygBarePK(d[@"pk"]); p.mediaID = d[@"mid"]; p.code = d[@"code"];
	p.thumbURLString = thumb;
	p.username = d[@"un"]; p.userPK = d[@"upk"]; p.avatarURLString = d[@"av"];
	p.mediaType = [d[@"mt"] integerValue];
	p.likeCount = [d[@"lk"] integerValue];
	p.commentCount = [d[@"cm"] integerValue];
	p.viewCount = [d[@"vw"] integerValue];
	p.shareCount = [d[@"sh"] integerValue];
	p.carouselCount = [d[@"cc"] integerValue];
	p.takenAt = [d[@"ta"] doubleValue];
	p.countsHidden = [d[@"ch"] boolValue];
	p.hasLiked = [d[@"hl"] boolValue];
	p.isFollowing = [d[@"fo"] boolValue];
	return p;
}

@end

@interface RYGGridFeedService ()
@property (nonatomic, strong) NSMutableArray<RYGGridFeedPost *> *mutablePosts;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenCodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, RYGGridFeedPost *> *byKey;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *indexByKey;
@property (nonatomic, strong) NSMutableIndexSet *pendingUpdated;
@property (nonatomic, copy) NSString *nextMaxID;
@property (nonatomic) BOOL isLoading;
@property (nonatomic) BOOL moreAvailable;
@property (nonatomic) BOOL didLoadOnce;
@end

@implementation RYGGridFeedService

- (instancetype)init {
	if ((self = [super init])) {
		_mutablePosts = [NSMutableArray array];
		_seenCodes = [NSMutableSet set];
		_byKey = [NSMutableDictionary dictionary];
		_indexByKey = [NSMutableDictionary dictionary];
		_pendingUpdated = [NSMutableIndexSet indexSet];
		_moreAvailable = YES;
	}
	return self;
}

// Adds a new post, or merges fuller stats into an existing one. Returns YES if appended.
- (BOOL)upsertPost:(RYGGridFeedPost *)p {
	NSString *k = rygPostKey(p);
	if (!k.length) return NO;
	RYGGridFeedPost *ex = self.byKey[k];
	if (ex) {
		BOOL ch = NO;
		if (p.likeCount > ex.likeCount) { ex.likeCount = p.likeCount; ch = YES; }
		if (p.commentCount > ex.commentCount) { ex.commentCount = p.commentCount; ch = YES; }
		if (p.viewCount > ex.viewCount) { ex.viewCount = p.viewCount; ch = YES; }
		if (p.shareCount > ex.shareCount) { ex.shareCount = p.shareCount; ch = YES; }
		if (!ex.code.length && p.code.length) { ex.code = p.code; }
		if (!ex.username.length && p.username.length) { ex.username = p.username; ch = YES; }
		// Posts only ever append, so the recorded index stays valid until a full reset.
		if (ch) { NSNumber *i = self.indexByKey[k]; if (i) [self.pendingUpdated addIndex:i.unsignedIntegerValue]; }
		return NO;
	}
	self.byKey[k] = p;
	self.indexByKey[k] = @(self.mutablePosts.count);
	[self.seenCodes addObject:k];
	[self.mutablePosts addObject:p];
	return YES;
}

- (NSIndexSet *)takePendingUpdated {
	NSIndexSet *s = [self.pendingUpdated copy];
	[self.pendingUpdated removeAllIndexes];
	return s;
}

- (NSArray<RYGGridFeedPost *> *)posts { return self.mutablePosts; }

- (void)clear {
	[self.mutablePosts removeAllObjects];
	[self.seenCodes removeAllObjects];
	[self.byKey removeAllObjects];
	[self.indexByKey removeAllObjects];
	[self.pendingUpdated removeAllIndexes];
	self.nextMaxID = nil;
	self.moreAvailable = YES;
	self.didLoadOnce = NO;
	self.isLoading = NO;
}

- (NSString *)cachePath {
	NSString *base = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
	NSString *dir = [base stringByAppendingPathComponent:@"RyukGramGrid"];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	NSString *acct = self.accountPK.length ? self.accountPK : @"unknown";
	NSString *file = [NSString stringWithFormat:@"%@_%@.json", acct, self.following ? @"following" : @"foryou"];
	return [dir stringByAppendingPathComponent:file];
}

- (void)saveCache {
	// The last few loaded whose thumbnail is already on disk (IG URLs expire, so an uncached
	// post would boot as a black tile). Scan is floored — each check is a disk stat.
	NSMutableArray<RYGGridFeedPost *> *renderable = [NSMutableArray array];
	NSInteger last = (NSInteger)self.mutablePosts.count - 1;
	NSInteger floor = MAX(0, last - 60);
	for (NSInteger i = last; i >= floor && renderable.count < kRYGGridCacheCap; i--) {
		RYGGridFeedPost *p = self.mutablePosts[i];
		NSString *k = p.pk.length ? p.pk : p.code;
		if ([RYGImageCache hasImageForKey:k]) [renderable insertObject:p atIndex:0];
	}
	NSMutableArray *arr = [NSMutableArray array];
	for (RYGGridFeedPost *p in renderable) [arr addObject:[p toDictionary]];
	NSDictionary *payload = @{ @"posts": arr, @"next": self.nextMaxID ?: @"", @"more": @(self.moreAvailable) };
	NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	NSString *path = [self cachePath];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [data writeToFile:path atomically:YES]; });
}

- (void)loadCache {
	if (self.mutablePosts.count) return;
	NSData *data = [NSData dataWithContentsOfFile:[self cachePath]];
	id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	if (![obj isKindOfClass:[NSDictionary class]]) return;
	NSMutableArray<RYGGridFeedPost *> *loaded = [NSMutableArray array];
	for (NSDictionary *d in obj[@"posts"]) {
		RYGGridFeedPost *p = [RYGGridFeedPost fromDictionary:d];
		if (p) [loaded addObject:p];
	}
	NSUInteger start = loaded.count > kRYGGridCacheCap ? loaded.count - kRYGGridCacheCap : 0;
	for (NSUInteger i = start; i < loaded.count; i++) [self upsertPost:loaded[i]];
	[self.pendingUpdated removeAllIndexes];
	NSString *next = obj[@"next"];
	self.nextMaxID = ([next isKindOfClass:[NSString class]] && next.length) ? next : nil;
	self.moreAvailable = obj[@"more"] ? [obj[@"more"] boolValue] : YES;
}

static NSString *rygPostKey(RYGGridFeedPost *p) {
	if (p.pk.length) return p.pk;
	if (p.code.length) return p.code;
	return p.mediaID;
}

- (NSInteger)ingestNextPage:(NSArray<RYGGridFeedPost *> *)posts nextMaxID:(NSString *)nextMaxID {
	NSInteger added = 0;
	for (RYGGridFeedPost *p in posts) if ([self upsertPost:p]) added++;
	if (nextMaxID.length) self.nextMaxID = nextMaxID;
	self.moreAvailable = YES;
	self.didLoadOnce = YES;
	if (added) [self saveCache];
	return added;
}

- (void)refreshWithCompletion:(RYGGridFeedLoadCompletion)completion {
	self.nextMaxID = nil;
	self.moreAvailable = YES;
	[self fetchReplacing:YES completion:completion];
}

- (void)loadMoreWithCompletion:(RYGGridFeedLoadCompletion)completion {
	if (self.isLoading || !self.moreAvailable) { if (completion) completion(@[], nil); return; }
	[self fetchReplacing:NO completion:completion];
}

- (void)fetchReplacing:(BOOL)replacing completion:(RYGGridFeedLoadCompletion)completion {
	if (self.isLoading) { if (completion) completion(@[], nil); return; }
	if (replacing) [self.seenCodes removeAllObjects];
	self.isLoading = YES;

	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"reason"] = replacing ? @"cold_start_fetch" : @"pagination";
	body[@"is_pull_to_refresh"] = replacing ? @"1" : @"0";
	body[@"feed_view_info"] = @"[]";
	if (!replacing && self.nextMaxID.length) body[@"max_id"] = self.nextMaxID;
	if (self.following) body[@"pagination_source"] = @"following";

	__weak typeof(self) weakSelf = self;
	[RYGInstagramAPI sendRequestWithMethod:@"POST"
	                                  path:@"feed/timeline/"
	                                  body:body
	                            completion:^(NSDictionary *resp, NSError *error) {
		typeof(self) strongSelf = weakSelf;
		[strongSelf handleResponse:resp error:error replacing:replacing completion:completion];
	}];
}

- (void)handleResponse:(NSDictionary *)resp error:(NSError *)error replacing:(BOOL)replacing completion:(RYGGridFeedLoadCompletion)completion {
		self.isLoading = NO;

		if (error || ![resp isKindOfClass:[NSDictionary class]]) {
			if (completion) completion(nil, error ?: [NSError errorWithDomain:@"RYGGridFeed" code:1 userInfo:@{NSLocalizedDescriptionKey: @"No response"}]);
			return;
		}

		NSArray *feedItems = resp[@"feed_items"];
		if (![feedItems isKindOfClass:[NSArray class]]) feedItems = resp[@"items"];
		if (![feedItems isKindOfClass:[NSArray class]]) {
			if (completion) completion(nil, [NSError errorWithDomain:@"RYGGridFeed" code:2 userInfo:@{NSLocalizedDescriptionKey: resp[@"message"] ?: @"Feed unavailable"}]);
			return;
		}

		NSMutableArray<RYGGridFeedPost *> *parsed = [NSMutableArray array];
		for (NSDictionary *item in feedItems) {
			if (![item isKindOfClass:[NSDictionary class]]) continue;
			NSDictionary *media = item[@"media_or_ad"];
			if (![media isKindOfClass:[NSDictionary class]]) media = item;
			RYGGridFeedPost *p = [RYGGridFeedPost postFromMediaDict:media];
			if (p) [parsed addObject:p];
		}

		id next = resp[@"next_max_id"];
		if ([next isKindOfClass:[NSString class]]) self.nextMaxID = next;
		else if ([next isKindOfClass:[NSNumber class]]) self.nextMaxID = [next stringValue];
		else self.nextMaxID = nil;

		// A missing more_available must not read as "feed over" — this never flips back once NO.
		id more = resp[@"more_available"];
		BOOL moreFlag = [more isKindOfClass:[NSNumber class]] ? [more boolValue] : (self.nextMaxID.length > 0);
		self.moreAvailable = moreFlag && self.nextMaxID.length > 0;

		if (replacing) { [self.mutablePosts removeAllObjects]; [self.byKey removeAllObjects]; [self.indexByKey removeAllObjects]; [self.seenCodes removeAllObjects]; }
		NSInteger added = 0;
		for (RYGGridFeedPost *p in parsed) if ([self upsertPost:p]) added++;
		self.didLoadOnce = YES;
		if (added) [self saveCache];
		if (completion) completion(parsed, nil);
}

@end
