#import "RYGStoryMarkedSeen.h"
#import "../../RYGAccountScopedDefaults.h"

#define RYG_MARKED_SEEN_KEY @"ryg_marked_seen_stories"

static const NSTimeInterval kRYGMarkedSeenTTL = 48.0 * 3600.0;

static NSString *rygMarkedCacheKey;
static NSDictionary *rygMarkedCache;

@implementation RYGStoryMarkedSeen

+ (NSDictionary *)entries {
	NSString *scoped = [RYGAccountScopedDefaults scopedKey:RYG_MARKED_SEEN_KEY];
	if (rygMarkedCache && [scoped isEqualToString:rygMarkedCacheKey]) return rygMarkedCache;

	rygMarkedCache = [RYGAccountScopedDefaults dictForKey:RYG_MARKED_SEEN_KEY] ?: @{};
	rygMarkedCacheKey = scoped;
	return rygMarkedCache;
}

+ (void)recordMediaPK:(NSString *)pk {
	if (!pk.length) return;

	NSTimeInterval now = NSDate.date.timeIntervalSince1970;
	NSDictionary *stored = [self entries];
	NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:stored.count + 1];

	for (NSString *key in stored) {
		if (now - [stored[key] doubleValue] < kRYGMarkedSeenTTL) entries[key] = stored[key];
	}

	entries[pk] = @(now);
	[RYGAccountScopedDefaults setObject:entries forKey:RYG_MARKED_SEEN_KEY];
	rygMarkedCache = entries;
	rygMarkedCacheKey = [RYGAccountScopedDefaults scopedKey:RYG_MARKED_SEEN_KEY];
}

+ (BOOL)isMarkedMediaPK:(NSString *)pk {
	if (!pk.length) return NO;

	NSNumber *ts = [self entries][pk];
	return ts && (NSDate.date.timeIntervalSince1970 - ts.doubleValue < kRYGMarkedSeenTTL);
}

@end
