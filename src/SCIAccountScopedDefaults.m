#import "SCIAccountScopedDefaults.h"
#import "Utils.h"

@implementation SCIAccountScopedDefaults

+ (NSString *)currentPK {
	NSString *pk = [SCIUtils currentUserPK];
	return (pk.length && ![pk isEqualToString:@"0"]) ? pk : nil;
}

+ (NSString *)scopedKey:(NSString *)baseKey {
	NSString *pk = [self currentPK];
	if (!pk.length) return baseKey;
	return [NSString stringWithFormat:@"%@_acct_%@", baseKey, pk];
}

+ (NSMutableSet<NSString *> *)migrationLedger {
	static NSMutableSet *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

+ (void)migrateIfNeededForBaseKey:(NSString *)baseKey {
	NSString *pk = [self currentPK];
	if (!pk.length) return;
	NSString *ledgerKey = [NSString stringWithFormat:@"%@:%@", baseKey, pk];
	@synchronized ([self migrationLedger]) {
		if ([[self migrationLedger] containsObject:ledgerKey]) return;
		[[self migrationLedger] addObject:ledgerKey];
	}
	NSString *scoped = [self scopedKey:baseKey];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d objectForKey:scoped] != nil) return;
	id bare = [d objectForKey:baseKey];
	if (!bare) return;
	[d setObject:bare forKey:scoped];
	[d removeObjectForKey:baseKey];
}

+ (id)objectForKey:(NSString *)baseKey {
	[self migrateIfNeededForBaseKey:baseKey];
	return [[NSUserDefaults standardUserDefaults] objectForKey:[self scopedKey:baseKey]];
}

+ (NSArray *)arrayForKey:(NSString *)baseKey {
	id v = [self objectForKey:baseKey];
	return [v isKindOfClass:[NSArray class]] ? v : nil;
}

+ (NSDictionary *)dictForKey:(NSString *)baseKey {
	id v = [self objectForKey:baseKey];
	return [v isKindOfClass:[NSDictionary class]] ? v : nil;
}

+ (void)setObject:(id)value forKey:(NSString *)baseKey {
	NSString *pk = [self currentPK];
	if (pk.length) {
		NSString *ledgerKey = [NSString stringWithFormat:@"%@:%@", baseKey, pk];
		@synchronized ([self migrationLedger]) { [[self migrationLedger] addObject:ledgerKey]; }
	}
	[[NSUserDefaults standardUserDefaults] setObject:value forKey:[self scopedKey:baseKey]];
}

+ (void)removeObjectForKey:(NSString *)baseKey {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:[self scopedKey:baseKey]];
}

#pragma mark - Explicit PK

+ (NSString *)scopedKey:(NSString *)baseKey forPK:(NSString *)pk {
	if (!pk.length || [pk isEqualToString:@"0"]) return baseKey;
	return [NSString stringWithFormat:@"%@_acct_%@", baseKey, pk];
}

+ (id)objectForKey:(NSString *)baseKey pk:(NSString *)pk {
	return [[NSUserDefaults standardUserDefaults] objectForKey:[self scopedKey:baseKey forPK:pk]];
}

+ (void)setObject:(id)value forKey:(NSString *)baseKey pk:(NSString *)pk {
	NSString *scoped = [self scopedKey:baseKey forPK:pk];
	if (pk.length) {
		// Pre-seed the ledger so a later login for this PK won't try to migrate
		// a bare key over the data we just restored.
		@synchronized ([self migrationLedger]) {
			[[self migrationLedger] addObject:[NSString stringWithFormat:@"%@:%@", baseKey, pk]];
		}
	}
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if (value) [d setObject:value forKey:scoped];
	else [d removeObjectForKey:scoped];
}

+ (void)removeObjectForKey:(NSString *)baseKey pk:(NSString *)pk {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:[self scopedKey:baseKey forPK:pk]];
}

+ (NSArray<NSString *> *)allKnownPKsForBaseKeys:(NSArray<NSString *> *)baseKeys {
	NSMutableSet<NSString *> *pks = [NSMutableSet set];
	NSDictionary *all = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];

	for (NSString *base in baseKeys) {
		NSString *needle = [base stringByAppendingString:@"_acct_"];
		for (NSString *key in all) {
			if (![key hasPrefix:needle]) continue;
			NSString *pk = [key substringFromIndex:needle.length];
			if (pk.length) [pks addObject:pk];
		}
	}
	return pks.allObjects;
}

@end
