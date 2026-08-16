#import "RYGAccountRegistry.h"
#import "Utils.h"
#import "Networking/RYGInstagramAPI.h"

NSNotificationName const RYGAccountRegistryDidChangeNotification = @"RYGAccountRegistryDidChangeNotification";

static NSString *const kRYGKnownAccountsKey = @"ryg_known_accounts";
static const NSTimeInterval kRYGResolveRetryDelay = 60 * 60;

@implementation RYGAccountRegistry

+ (NSDictionary<NSString *, NSDictionary *> *)allAccounts {
	id v = [[NSUserDefaults standardUserDefaults] objectForKey:kRYGKnownAccountsKey];
	return [v isKindOfClass:NSDictionary.class] ? v : @{};
}

+ (NSDictionary *)infoForPK:(NSString *)pk {
	if (!pk.length) return nil;
	id v = [self allAccounts][pk];
	return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

+ (NSString *)displayNameForPK:(NSString *)pk {
	return [self displayNameForPK:pk info:[self infoForPK:pk]];
}

+ (NSString *)displayNameForPK:(NSString *)pk info:(NSDictionary *)info {
	NSString *username = [info[@"username"] isKindOfClass:NSString.class] ? info[@"username"] : nil;
	if (username.length) return [@"@" stringByAppendingString:username];
	return [NSString stringWithFormat:RYGLocalized(@"PK %@"), pk ?: @"?"];
}

+ (NSString *)stringValue:(id)v {
	return [v isKindOfClass:NSString.class] ? v : ([v isKindOfClass:NSNumber.class] ? [v description] : nil);
}

+ (void)noteCurrentAccount {
	id user = nil;
	@try { user = [[RYGUtils activeUserSession] valueForKey:@"user"]; } @catch (__unused id e) {}
	NSString *pk = [RYGUtils pkFromIGUser:user];
	if (!pk.length || [pk isEqualToString:@"0"]) return;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	info[@"username"] = [self stringValue:[RYGUtils fieldCacheValue:user forKey:@"username"]];
	info[@"full_name"] = [self stringValue:[RYGUtils fieldCacheValue:user forKey:@"full_name"]];
	info[@"profile_pic_url"] = [self stringValue:[RYGUtils fieldCacheValue:user forKey:@"profile_pic_url"]];
	if (!info.count) return;

	NSDictionary *known = [self infoForPK:pk];
	BOOL unchanged = YES;
	for (NSString *k in info) unchanged &= [info[k] isEqual:known[k]];
	if (unchanged && known) return;

	info[@"last_seen"] = @([[NSDate date] timeIntervalSince1970]);
	[self storeInfo:info forPK:pk];
}

// NSNull clears a field — the dict is a plist and can't hold it.
+ (void)storeInfo:(NSDictionary *)info forPK:(NSString *)pk {
	NSMutableDictionary *all = [[self allAccounts] mutableCopy];
	NSMutableDictionary *merged = [(all[pk] ?: @{}) mutableCopy];
	for (NSString *k in info) {
		if ([info[k] isKindOfClass:NSNull.class]) [merged removeObjectForKey:k];
		else merged[k] = info[k];
	}
	all[pk] = merged;
	[[NSUserDefaults standardUserDefaults] setObject:all forKey:kRYGKnownAccountsKey];
}

#pragma mark - Resolving unknown accounts

+ (NSMutableSet<NSString *> *)inFlight {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

+ (BOOL)needsNameForPK:(NSString *)pk {
	NSDictionary *info = [self infoForPK:pk];
	NSString *username = [info[@"username"] isKindOfClass:NSString.class] ? info[@"username"] : nil;
	if (username.length) return NO;
	id failed = info[@"resolve_failed_at"];
	if ([failed isKindOfClass:NSNumber.class] &&
		[[NSDate date] timeIntervalSince1970] - [failed doubleValue] < kRYGResolveRetryDelay) return NO;
	return YES;
}

+ (void)resolveMissingNamesForPKs:(NSArray<NSString *> *)pks {
	NSMutableArray<NSString *> *wanted = [NSMutableArray array];
	@synchronized ([self inFlight]) {
		for (NSString *pk in pks) {
			if (![pk isKindOfClass:NSString.class] || !pk.length) continue;
			if ([[self inFlight] containsObject:pk] || ![self needsNameForPK:pk]) continue;
			[[self inFlight] addObject:pk];
			[wanted addObject:pk];
		}
	}
	if (!wanted.count) return;

	__block NSInteger pending = (NSInteger)wanted.count;
	__block BOOL changed = NO;
	for (NSString *pk in wanted) {
		[RYGInstagramAPI fetchUserInfoForPK:pk completion:^(NSDictionary *user, __unused NSError *error) {
			NSString *username = [user[@"username"] isKindOfClass:NSString.class] ? user[@"username"] : nil;
			if (username.length) {
				NSMutableDictionary *info = [NSMutableDictionary dictionary];
				for (NSString *k in @[ @"username", @"full_name", @"profile_pic_url" ]) {
					NSString *v = [self stringValue:user[k]];
					if (v.length) info[k] = v;
				}
				info[@"resolve_failed_at"] = [NSNull null];
				[self storeInfo:info forPK:pk];
				changed = YES;
			} else {
				// Back off — a deleted account would retry on every screen open.
				[self storeInfo:@{ @"resolve_failed_at": @([[NSDate date] timeIntervalSince1970]) } forPK:pk];
			}
			@synchronized ([self inFlight]) { [[self inFlight] removeObject:pk]; }
			if (--pending > 0 || !changed) return;
			[[NSNotificationCenter defaultCenter] postNotificationName:RYGAccountRegistryDidChangeNotification object:nil];
		}];
	}
}

+ (void)mergeAccounts:(NSDictionary<NSString *, NSDictionary *> *)accounts {
	if (![accounts isKindOfClass:NSDictionary.class] || !accounts.count) return;
	for (NSString *pk in accounts) {
		if (![pk isKindOfClass:NSString.class]) continue;
		NSDictionary *info = accounts[pk];
		if (![info isKindOfClass:NSDictionary.class] || !info.count) continue;
		// Local names are fresher than a backup's — only fill gaps.
		NSDictionary *known = [self infoForPK:pk];
		NSMutableDictionary *fill = [NSMutableDictionary dictionary];
		for (NSString *k in @[ @"username", @"full_name", @"profile_pic_url" ]) {
			NSString *v = [self stringValue:info[k]];
			if (v.length && ![known[k] isKindOfClass:NSString.class]) fill[k] = v;
		}
		if (fill.count) [self storeInfo:fill forPK:pk];
	}
}

@end
