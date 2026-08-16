// While the grid owns the home feed, IG's ingest is skipped and the parsed response goes
// straight to the grid instead. The live toggle falls through to %orig.

#import "RYGGridFeedService.h"
#import "RYGGridFeedInfo.h"
#import "../../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString *const RYGGridFeedResponseNote = @"RYGGridFeedResponseNote";
static NSArray<RYGGridFeedPost *> *gLatestPosts = nil;
static NSString *gLatestNextMaxID = nil;
static BOOL gLatestReplacing = NO;

static id rygIvarObj(id obj, const char *name) {
	if (!obj) return nil;
	Class c = object_getClass(obj);
	while (c) { Ivar iv = class_getInstanceVariable(c, name); if (iv) return object_getIvar(obj, iv); c = class_getSuperclass(c); }
	return nil;
}

static id rygCall(id obj, NSString *sel) {
	if (!obj) return nil;
	SEL s = NSSelectorFromString(sel);
	if (![obj respondsToSelector:s]) return nil;
	return ((id(*)(id, SEL))objc_msgSend)(obj, s);
}

NSArray *RYGLatestFeedPosts(void) { return gLatestPosts; }
NSString *RYGLatestFeedNextMaxID(void) { return gLatestNextMaxID; }
BOOL RYGLatestFeedReplacing(void) { return gLatestReplacing; }

static NSArray *rygMediaDictsFromResponseJSON(id obj) {
	if ([obj isKindOfClass:[NSData class]]) obj = [(NSData *)obj length] ? [NSJSONSerialization JSONObjectWithData:obj options:0 error:nil] : nil;
	if (![obj isKindOfClass:[NSDictionary class]]) return nil;
	NSArray *items = [obj[@"feed_items"] isKindOfClass:[NSArray class]] ? obj[@"feed_items"] : obj[@"items"];
	if (![items isKindOfClass:[NSArray class]]) return nil;
	NSMutableArray *out = [NSMutableArray array];
	for (id it in items) {
		if (![it isKindOfClass:[NSDictionary class]]) continue;
		NSDictionary *m = it[@"media_or_ad"];
		[out addObject:([m isKindOfClass:[NSDictionary class]] ? m : (NSDictionary *)it)];
	}
	return out;
}

// Prefers the raw JSON (full stats), falling back to IG's model arrays.
static NSArray<RYGGridFeedPost *> *rygPostsFromResponse(id response, NSString **outNext) {
	if (!response) return nil;
	NSMutableArray<RYGGridFeedPost *> *posts = [NSMutableArray array];

	for (NSString *sel in @[@"rawResponseData", @"responseData", @"data"]) {
		id d = rygCall(response, sel);
		NSArray *dicts = rygMediaDictsFromResponseJSON(d);
		if (!dicts.count) continue;
		for (NSDictionary *m in dicts) { RYGGridFeedPost *p = [RYGGridFeedPost postFromMediaDict:m]; if (p) [posts addObject:p]; }
		if (posts.count) break;
	}
	if (!posts.count) {
		for (NSString *sel in @[@"downloadedItems", @"items", @"posts"]) {
			id arr = rygCall(response, sel);
			if (![arr isKindOfClass:[NSArray class]] || ![arr count]) continue;
			for (id m in arr) {
				RYGGridFeedPost *p = [m isKindOfClass:[NSDictionary class]] ? [RYGGridFeedPost postFromMediaDict:m] : [RYGGridFeedPost postFromIGMedia:m];
				if (p) [posts addObject:p];
			}
			if (posts.count) break;
		}
	}
	if (outNext) {
		id v = rygCall(response, @"nextMaxID");
		if ([v isKindOfClass:[NSString class]] && [v length]) *outNext = v;
	}
	return posts;
}

// Following/Favourites share this controller; only pagination_source separates them.
static NSString *rygFeedVariant(id config) {
	id params = rygIvarObj(config, "_requestParameters");
	id src = [params isKindOfClass:[NSDictionary class]] ? params[@"pagination_source"] : nil;
	return ([src isKindOfClass:[NSString class]] && [(NSString *)src length]) ? src : nil;
}

static BOOL rygConfigIsReplacing(id config) {
	id params = rygIvarObj(config, "_requestParameters");
	NSString *reason = [params isKindOfClass:[NSDictionary class]] ? params[@"reason"] : nil;
	if ([reason isKindOfClass:[NSString class]]) {
		if ([reason containsString:@"cold_start"] || [reason containsString:@"pull"] || [reason containsString:@"refresh"] || [reason containsString:@"warm_start"]) return YES;
		if ([reason containsString:@"pagination"] || [reason containsString:@"auto_load"] || [reason containsString:@"next"]) return NO;
	}
	id maxid = [params isKindOfClass:[NSDictionary class]] ? params[@"max_id"] : nil;
	return !([maxid isKindOfClass:[NSString class]] && [maxid length]);
}

%group RYGGridFeedKill
%hook IGMainFeedDataController
- (void)feedNetworkSource:(id)source didReceiveFeedResponse:(id)response forRequestConfig:(id)config {
	if (![RYGGridFeedInfo visible] || rygFeedVariant(config)) { %orig; return; }
	NSString *next = nil;
	NSArray<RYGGridFeedPost *> *posts = rygPostsFromResponse(response, &next);
	if (posts.count) {
		BOOL replacing = rygConfigIsReplacing(config);
		gLatestPosts = posts; gLatestNextMaxID = next; gLatestReplacing = replacing;
		NSDictionary *ui = @{ @"posts": posts, @"replacing": @(replacing), @"next": next ?: @"" };
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] postNotificationName:RYGGridFeedResponseNote object:nil userInfo:ui];
		});
	}
	// No %orig: IG's data controller never ingests, so its feed has nothing to render.
}
%end
%end

%ctor {
	if ([RYGGridFeedInfo active]) %init(RYGGridFeedKill);
}
