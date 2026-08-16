#import "RYGProfileAnalyzerModels.h"
#import "RYGProfileAnalyzerChecks.h"
#import <objc/runtime.h>

static id rygFieldCacheValueLocal(id obj, NSString *key) {
	if (!obj || !key) return nil;
	Ivar fcIvar = NULL;
	for (Class c = [obj class]; c && !fcIvar; c = class_getSuperclass(c)) {
		fcIvar = class_getInstanceVariable(c, "_fieldCache");
	}
	if (!fcIvar) return nil;
	NSDictionary *fc = object_getIvar(obj, fcIvar);
	if (![fc isKindOfClass:[NSDictionary class]]) return nil;
	id v = fc[key];
	if (!v || [v isKindOfClass:[NSNull class]]) return nil;
	return v;
}

#pragma mark - User

@implementation RYGProfileAnalyzerUser

+ (instancetype)userFromAPIDict:(NSDictionary *)d {
	id pkRaw = d[@"pk"] ?: d[@"pk_id"] ?: d[@"id"];
	NSString *pk = [pkRaw isKindOfClass:[NSString class]] ? pkRaw
														  : [pkRaw respondsToSelector:@selector(stringValue)] ? [pkRaw stringValue] : nil;
	if (!pk.length) return nil;

	RYGProfileAnalyzerUser *u = [self new];
	u.pk = pk;
	u.username = [d[@"username"] isKindOfClass:[NSString class]] ? d[@"username"] : @"";
	u.fullName = [d[@"full_name"] isKindOfClass:[NSString class]] ? d[@"full_name"] : nil;
	u.profilePicURL = [d[@"profile_pic_url"] isKindOfClass:[NSString class]] ? d[@"profile_pic_url"] : nil;
	id pid = d[@"profile_pic_id"];
	if ([pid isKindOfClass:[NSString class]]) u.profilePicID = pid;
	else if ([pid respondsToSelector:@selector(stringValue)]) u.profilePicID = [pid stringValue];
	u.isPrivate = [d[@"is_private"] boolValue];
	u.isVerified = [d[@"is_verified"] boolValue];
	return u;
}

+ (instancetype)userFromIGUserObject:(id)igUser {
	if (!igUser) return nil;
	id pkRaw = rygFieldCacheValueLocal(igUser, @"strong_id__")
			?: rygFieldCacheValueLocal(igUser, @"pk")
			?: rygFieldCacheValueLocal(igUser, @"pk_id");
	NSString *pk = [pkRaw isKindOfClass:[NSString class]] ? pkRaw
														  : [pkRaw respondsToSelector:@selector(stringValue)] ? [pkRaw stringValue] : nil;
	if (!pk.length) return nil;

	RYGProfileAnalyzerUser *u = [self new];
	u.pk = pk;
	id un = rygFieldCacheValueLocal(igUser, @"username");
	u.username = [un isKindOfClass:[NSString class]] ? un : @"";
	id fn = rygFieldCacheValueLocal(igUser, @"full_name");
	if ([fn isKindOfClass:[NSString class]]) u.fullName = fn;
	id pic = rygFieldCacheValueLocal(igUser, @"profile_pic_url");
	if ([pic isKindOfClass:[NSString class]]) u.profilePicURL = pic;
	id pid = rygFieldCacheValueLocal(igUser, @"profile_pic_id");
	if ([pid isKindOfClass:[NSString class]]) u.profilePicID = pid;
	else if ([pid respondsToSelector:@selector(stringValue)]) u.profilePicID = [pid stringValue];
	u.isPrivate = [rygFieldCacheValueLocal(igUser, @"is_private") boolValue];
	u.isVerified = [rygFieldCacheValueLocal(igUser, @"is_verified") boolValue];
	return u;
}

+ (instancetype)userFromJSONDict:(NSDictionary *)d {
	if (![d[@"pk"] isKindOfClass:[NSString class]]) return nil;
	RYGProfileAnalyzerUser *u = [self new];
	u.pk = d[@"pk"];
	u.username = d[@"username"] ?: @"";
	u.fullName = d[@"full_name"];
	u.profilePicURL = d[@"profile_pic_url"];
	u.profilePicID = d[@"profile_pic_id"];
	u.isPrivate = [d[@"is_private"] boolValue];
	u.isVerified = [d[@"is_verified"] boolValue];
	return u;
}

- (NSDictionary *)toJSONDict {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"pk"] = self.pk ?: @"";
	d[@"username"] = self.username ?: @"";
	if (self.fullName) d[@"full_name"] = self.fullName;
	if (self.profilePicURL) d[@"profile_pic_url"] = self.profilePicURL;
	if (self.profilePicID)  d[@"profile_pic_id"]  = self.profilePicID;
	d[@"is_private"] = @(self.isPrivate);
	d[@"is_verified"] = @(self.isVerified);
	return d;
}

- (id)copyWithZone:(NSZone *)zone {
	RYGProfileAnalyzerUser *u = [RYGProfileAnalyzerUser new];
	u.pk = self.pk;
	u.username = self.username;
	u.fullName = self.fullName;
	u.profilePicURL = self.profilePicURL;
	u.profilePicID = self.profilePicID;
	u.isPrivate = self.isPrivate;
	u.isVerified = self.isVerified;
	return u;
}

- (NSUInteger)hash { return self.pk.hash; }
- (BOOL)isEqual:(id)other {
	if (![other isKindOfClass:[RYGProfileAnalyzerUser class]]) return NO;
	return [self.pk isEqualToString:((RYGProfileAnalyzerUser *)other).pk];
}

@end

#pragma mark - Visit

@implementation RYGProfileAnalyzerVisit

+ (instancetype)visitFromJSONDict:(NSDictionary *)d {
	NSDictionary *userDict = d[@"user"];
	if (![userDict isKindOfClass:[NSDictionary class]]) return nil;
	RYGProfileAnalyzerUser *u = [RYGProfileAnalyzerUser userFromJSONDict:userDict];
	if (!u) return nil;
	double first = [d[@"first_seen"] doubleValue];
	double last  = [d[@"last_seen"]  doubleValue];
	if (last  <= 0) last  = [[NSDate date] timeIntervalSince1970];   // legacy zero → "now"
	if (first <= 0) first = last;
	RYGProfileAnalyzerVisit *v = [self new];
	v.user = u;
	v.firstSeen = [NSDate dateWithTimeIntervalSince1970:first];
	v.lastSeen  = [NSDate dateWithTimeIntervalSince1970:last];
	v.visitCount = MAX(1, [d[@"visit_count"] integerValue]);
	return v;
}

- (NSDictionary *)toJSONDict {
	return @{
		@"user": [self.user toJSONDict],
		@"first_seen": @([self.firstSeen timeIntervalSince1970]),
		@"last_seen":  @([self.lastSeen  timeIntervalSince1970]),
		@"visit_count": @(self.visitCount),
	};
}

@end

#pragma mark - Snapshot

@implementation RYGProfileAnalyzerSnapshot

+ (instancetype)snapshotFromJSONDict:(NSDictionary *)d {
	if (!d[@"self_pk"]) return nil;
	RYGProfileAnalyzerSnapshot *s = [self new];
	s.scanDate = [NSDate dateWithTimeIntervalSince1970:[d[@"scan_date"] doubleValue]];
	s.selfPK = d[@"self_pk"];
	s.selfUsername = d[@"self_username"];
	s.selfFullName = d[@"self_full_name"];
	s.selfProfilePicURL = d[@"self_profile_pic_url"];
	s.followerCount = [d[@"follower_count"] integerValue];
	s.followingCount = [d[@"following_count"] integerValue];
	s.mediaCount = [d[@"media_count"] integerValue];

	NSMutableArray *f = [NSMutableArray array];
	if ([d[@"followers"] isKindOfClass:[NSArray class]]) {
		for (id u in (NSArray *)d[@"followers"]) {
			if (![u isKindOfClass:[NSDictionary class]]) continue;
			RYGProfileAnalyzerUser *user = [RYGProfileAnalyzerUser userFromJSONDict:u];
			if (user) [f addObject:user];
		}
	}
	s.followers = f;

	NSMutableArray *g = [NSMutableArray array];
	if ([d[@"following"] isKindOfClass:[NSArray class]]) {
		for (id u in (NSArray *)d[@"following"]) {
			if (![u isKindOfClass:[NSDictionary class]]) continue;
			RYGProfileAnalyzerUser *user = [RYGProfileAnalyzerUser userFromJSONDict:u];
			if (user) [g addObject:user];
		}
	}
	s.following = g;
	return s;
}

- (NSDictionary *)toJSONDict {
	NSMutableArray *f = [NSMutableArray arrayWithCapacity:self.followers.count];
	for (RYGProfileAnalyzerUser *u in self.followers) [f addObject:[u toJSONDict]];
	NSMutableArray *g = [NSMutableArray arrayWithCapacity:self.following.count];
	for (RYGProfileAnalyzerUser *u in self.following) [g addObject:[u toJSONDict]];

	return @{
		@"scan_date": @([self.scanDate timeIntervalSince1970]),
		@"self_pk": self.selfPK ?: @"",
		@"self_username": self.selfUsername ?: @"",
		@"self_full_name": self.selfFullName ?: @"",
		@"self_profile_pic_url": self.selfProfilePicURL ?: @"",
		@"follower_count": @(self.followerCount),
		@"following_count": @(self.followingCount),
		@"media_count": @(self.mediaCount),
		@"followers": f,
		@"following": g,
	};
}

@end

#pragma mark - Profile change

@implementation RYGProfileAnalyzerProfileChange
- (BOOL)usernameChanged  { return ![self.previous.username isEqualToString:self.current.username]; }
- (BOOL)fullNameChanged  { return ![(self.previous.fullName ?: @"") isEqualToString:(self.current.fullName ?: @"")]; }
// Compare profile_pic_id (stable per upload); URL diffing is useless because
// IG rotates the CDN host per request. Skip when either side lacks the id.
- (BOOL)profilePicChanged {
	NSString *a = self.previous.profilePicID;
	NSString *b = self.current.profilePicID;
	if (!a.length || !b.length) return NO;
	return ![a isEqualToString:b];
}
@end

#pragma mark - Report

@implementation RYGProfileAnalyzerReport

static NSArray *rygSubtract(NSArray *a, NSSet *bSet) {
	if (!a.count) return @[];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:a.count];
	for (RYGProfileAnalyzerUser *u in a) if (![bSet containsObject:u]) [out addObject:u];
	return out;
}

static NSArray *rygIntersect(NSArray *a, NSSet *bSet) {
	if (!a.count) return @[];
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:a.count];
	for (RYGProfileAnalyzerUser *u in a) if ([bSet containsObject:u]) [out addObject:u];
	return out;
}

+ (RYGProfileAnalyzerReport *)reportFromCurrent:(RYGProfileAnalyzerSnapshot *)current
										previous:(RYGProfileAnalyzerSnapshot *)previous {
	RYGProfileAnalyzerReport *r = [self new];
	r.current = current;
	r.previous = previous;
	r.mutualFollowers = @[];
	r.notFollowingYouBack = @[];
	r.youDontFollowBack = @[];
	r.recentFollowers = @[];
	r.lostFollowers = @[];
	r.youStartedFollowing = @[];
	r.youUnfollowed = @[];
	r.profileUpdates = @[];
	if (!current) return r;

	// Disabled checks aren't computed — their arrays stay empty.
	BOOL (^on)(RYGPACategory) = ^BOOL(RYGPACategory c) { return [RYGProfileAnalyzerChecks isCategoryEnabled:c]; };

	NSSet *followersSet = [NSSet setWithArray:current.followers];
	NSSet *followingSet = [NSSet setWithArray:current.following];

	if (on(RYGPACategoryMutual))            r.mutualFollowers     = rygIntersect(current.followers, followingSet);
	if (on(RYGPACategoryNotFollowingBack))  r.notFollowingYouBack = rygSubtract(current.following, followersSet);
	if (on(RYGPACategoryDontFollowBack))    r.youDontFollowBack   = rygSubtract(current.followers, followingSet);

	if (previous) {
		NSSet *prevFollowers = [NSSet setWithArray:previous.followers];
		NSSet *prevFollowing = [NSSet setWithArray:previous.following];
		if (on(RYGPACategoryNewFollowers))        r.recentFollowers     = rygSubtract(current.followers, prevFollowers);
		if (on(RYGPACategoryLostFollowers))       r.lostFollowers       = rygSubtract(previous.followers, followersSet);
		if (on(RYGPACategoryYouStartedFollowing)) r.youStartedFollowing = rygSubtract(current.following, prevFollowing);
		if (on(RYGPACategoryYouUnfollowed))       r.youUnfollowed       = rygSubtract(previous.following, followingSet);

		if (on(RYGPACategoryProfileUpdates)) {
			// Same pk in both snapshots, any field differs.
			NSMutableDictionary *prevByPK = [NSMutableDictionary dictionary];
			for (RYGProfileAnalyzerUser *u in previous.followers) prevByPK[u.pk] = u;
			for (RYGProfileAnalyzerUser *u in previous.following) prevByPK[u.pk] = u;

			NSMutableArray *updates = [NSMutableArray array];
			NSMutableSet *seen = [NSMutableSet set];
			NSArray *currentAll = [current.followers arrayByAddingObjectsFromArray:current.following];
			for (RYGProfileAnalyzerUser *u in currentAll) {
				if ([seen containsObject:u.pk]) continue;
				[seen addObject:u.pk];
				RYGProfileAnalyzerUser *prev = prevByPK[u.pk];
				if (!prev) continue;
				RYGProfileAnalyzerProfileChange *ch = [RYGProfileAnalyzerProfileChange new];
				ch.previous = prev;
				ch.current = u;
				if (ch.usernameChanged || ch.fullNameChanged || ch.profilePicChanged) [updates addObject:ch];
			}
			r.profileUpdates = updates;
		}
	}
	return r;
}

@end
