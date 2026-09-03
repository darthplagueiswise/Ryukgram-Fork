#import "RYGHomeShortcutBadges.h"
#import "../../Utils.h"

NSNotificationName const RYGHomeShortcutBadgesDidChangeNotification = @"RYGHomeShortcutBadgesDidChangeNotification";

static NSString *const kBadgesKey = @"home_shortcut_badges";
static NSString *const kNoOwner = @"_none";

@implementation RYGHomeShortcutBadges

+ (id)lock {
	static id token; static dispatch_once_t once;
	dispatch_once(&once, ^{ token = [NSObject new]; });
	return token;
}

+ (NSString *)scope {
	NSString *pk = [RYGUtils currentUserPK];
	return pk.length ? pk : kNoOwner;
}

+ (void)postChange {
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSNotificationCenter.defaultCenter postNotificationName:RYGHomeShortcutBadgesDidChangeNotification object:nil];
	});
}

+ (NSMutableDictionary *)sanitizedRoot {
	NSMutableDictionary *root = [[RYGUtils getDictPref:kBadgesKey] mutableCopy];
	for (NSString *k in root.allKeys) {
		if (![root[k] isKindOfClass:NSDictionary.class]) [root removeObjectForKey:k];
	}
	return root;
}

+ (NSInteger)countForActionID:(NSString *)actionID {
	if (!actionID.length) return 0;
	@synchronized ([self lock]) {
		NSDictionary *owned = [RYGUtils getDictPref:kBadgesKey][[self scope]];
		if (![owned isKindOfClass:NSDictionary.class]) return 0;
		return MAX(0, [owned[actionID] integerValue]);
	}
}

+ (NSInteger)totalForActionIDs:(NSArray<NSString *> *)actionIDs {
	NSInteger total = 0;
	@synchronized ([self lock]) {
		NSDictionary *owned = [RYGUtils getDictPref:kBadgesKey][[self scope]];
		if (![owned isKindOfClass:NSDictionary.class]) return 0;
		for (NSString *aid in actionIDs) total += MAX(0, [owned[aid] integerValue]);
	}
	return total;
}

+ (void)addCount:(NSInteger)delta toActionID:(NSString *)actionID {
	if (!actionID.length || delta == 0) return;
	BOOL changed = NO;
	@synchronized ([self lock]) {
		NSString *scope = [self scope];
		NSMutableDictionary *root = [self sanitizedRoot];
		NSMutableDictionary *owned = [root[scope] mutableCopy] ?: [NSMutableDictionary dictionary];
		NSInteger cur = MAX(0, [owned[actionID] integerValue]);
		NSInteger next = MAX(0, cur + delta);
		if (next != cur) {
			if (next) owned[actionID] = @(next); else [owned removeObjectForKey:actionID];
			if (owned.count) root[scope] = owned; else [root removeObjectForKey:scope];
			[RYGUtils setPref:root forKey:kBadgesKey];
			changed = YES;
		}
	}
	if (changed) [self postChange];
}

+ (void)bumpActionID:(NSString *)actionID {
	[self addCount:1 toActionID:actionID];
}

+ (void)clearActionID:(NSString *)actionID {
	if (!actionID.length) return;
	BOOL changed = NO;
	@synchronized ([self lock]) {
		NSString *scope = [self scope];
		NSMutableDictionary *root = [self sanitizedRoot];
		NSMutableDictionary *owned = [root[scope] mutableCopy];
		if (owned[actionID]) {
			[owned removeObjectForKey:actionID];
			if (owned.count) root[scope] = owned; else [root removeObjectForKey:scope];
			[RYGUtils setPref:root forKey:kBadgesKey];
			changed = YES;
		}
	}
	if (changed) [self postChange];
}

@end
