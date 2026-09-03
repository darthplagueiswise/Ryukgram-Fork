// Local username / display name spoof for the logged-in account.
// Applied on the parsed response and on the model getters, so store-served
// surfaces read the same value as freshly fetched ones.

#import "../../Utils.h"
#import "../../Observers/RYGAccountObserver.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kRYGRealIdentityPref = @"fake_identity_real";

static NSString *gFakeUsername;
static NSString *gFakeFullName;
static NSString *gRealUsername;
static NSString *gRealFullName;
static NSString *gSelfPK;

static void rygPersistRealIdentity(void) {
	if (!gSelfPK.length) return;

	NSMutableDictionary *map = [([NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRealIdentityPref] ?: @{}) mutableCopy];
	NSMutableDictionary *entry = [(map[gSelfPK] ?: @{}) mutableCopy];

	if (gRealUsername.length) entry[@"username"] = gRealUsername;
	if (gRealFullName.length) entry[@"full_name"] = gRealFullName;

	map[gSelfPK] = entry;
	[NSUserDefaults.standardUserDefaults setObject:map forKey:kRYGRealIdentityPref];
}

// Only a server value may become the real one, never our own fake.
static BOOL rygLearnReal(NSString *__strong *slot, id candidate, NSString *fake) {
	if (![candidate isKindOfClass:NSString.class] || ![candidate length]) return NO;
	if ([candidate isEqualToString:fake] || [candidate isEqualToString:*slot]) return NO;

	*slot = [candidate copy];
	return YES;
}

static void rygLoadPersistedRealIdentity(void) {
	NSDictionary *entry = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGRealIdentityPref][gSelfPK ?: @""];
	rygLearnReal(&gRealUsername, entry[@"username"], gFakeUsername);
	rygLearnReal(&gRealFullName, entry[@"full_name"], gFakeFullName);
}

static void rygRefreshRealIdentity(void) {
	id user = nil;

	@try {
		user = [[RYGUtils activeUserSession] valueForKey:@"user"];
	} @catch (__unused id e) {}

	NSString *pk = [RYGUtils currentUserPK];
	if (pk.length && ![pk isEqualToString:gSelfPK]) {
		gSelfPK = [pk copy];
		gRealUsername = nil;
		gRealFullName = nil;
		rygLoadPersistedRealIdentity();
	}

	BOOL learned = rygLearnReal(&gRealUsername, [RYGUtils fieldCacheValue:user forKey:@"username"], gFakeUsername);
	learned |= rygLearnReal(&gRealFullName, [RYGUtils fieldCacheValue:user forKey:@"full_name"], gFakeFullName);
	if (learned) rygPersistRealIdentity();
}

static BOOL rygPKMatchesSelf(id pk) {
	if (!gSelfPK.length) return NO;
	if ([pk isKindOfClass:NSString.class]) return [pk isEqualToString:gSelfPK];
	if ([pk isKindOfClass:NSNumber.class]) return [[pk stringValue] isEqualToString:gSelfPK];
	return NO;
}

static BOOL rygUserIsSelf(id user) {
	return rygPKMatchesSelf([RYGUtils fieldCacheValue:user forKey:@"pk"] ?: [RYGUtils fieldCacheValue:user forKey:@"strong_id__"]);
}

static void rygSpoofIdentityInJSON(id object, int depth) {
	if (depth > 16) return;

	if ([object isKindOfClass:NSMutableDictionary.class]) {
		NSMutableDictionary *dict = object;

		if (rygPKMatchesSelf(dict[@"pk"] ?: dict[@"strong_id__"] ?: dict[@"user_id"] ?: dict[@"id"])) {
			BOOL learned = rygLearnReal(&gRealUsername, dict[@"username"], gFakeUsername);
			learned |= rygLearnReal(&gRealFullName, dict[@"full_name"], gFakeFullName);
			if (learned) rygPersistRealIdentity();

			if (gFakeUsername.length && [dict[@"username"] isKindOfClass:NSString.class]) dict[@"username"] = gFakeUsername;
			if (gFakeFullName.length && [dict[@"full_name"] isKindOfClass:NSString.class]) dict[@"full_name"] = gFakeFullName;
		}

		for (id value in dict.allValues) {
			rygSpoofIdentityInJSON(value, depth + 1);
		}
	} else if ([object isKindOfClass:NSMutableArray.class]) {
		for (id value in (NSMutableArray *)object) {
			rygSpoofIdentityInJSON(value, depth + 1);
		}
	}
}

static id (*orig_JSONObjectWithData)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);

// Gate on the pk, never on the username — the username can be a value we wrote.
static id new_JSONObjectWithData(Class self, SEL _cmd, NSData *data, NSJSONReadingOptions opts, NSError **err) {
	const char *pk = gSelfPK.UTF8String;
	BOOL relevant = pk && [data isKindOfClass:NSData.class] && data.length && memmem(data.bytes, data.length, pk, strlen(pk));

	if (!relevant) return orig_JSONObjectWithData ? orig_JSONObjectWithData(self, _cmd, data, opts, err) : nil;

	id result = orig_JSONObjectWithData ? orig_JSONObjectWithData(self, _cmd, data, opts | NSJSONReadingMutableContainers, err) : nil;
	if (result) rygSpoofIdentityInJSON(result, 0);
	return result;
}

%group FakeIdentity

%hook IGBaseUser

- (id)username {
	id value = %orig;
	if (!gFakeUsername.length || ![value isKindOfClass:NSString.class] || ![value isEqualToString:gRealUsername]) return value;
	return rygUserIsSelf(self) ? gFakeUsername : value;
}

- (id)fullName {
	id value = %orig;
	if (!gFakeFullName.length || ![value isKindOfClass:NSString.class] || ![value isEqualToString:gRealFullName]) return value;
	return rygUserIsSelf(self) ? gFakeFullName : value;
}

%end

// Keeps its own copy of the title and re-applies it on layout, never re-reading the model.
%hook IGChevronTitleButton

- (void)setTitle:(NSString *)title {
	if (gFakeUsername.length && [title isKindOfClass:NSString.class] && [title isEqualToString:gRealUsername]) {
		%orig(gFakeUsername);
		return;
	}

	%orig;
}

%end

%end

static NSString *rygFakeValueForKey(NSString *key) {
	NSString *value = [[RYGUtils getStringPref:key] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if ([value hasPrefix:@"@"]) value = [value substringFromIndex:1];
	return value.length ? value : nil;
}

%ctor {
	if ([RYGUtils getBoolPref:@"fake_username"]) gFakeUsername = rygFakeValueForKey(@"fake_username_value");
	if ([RYGUtils getBoolPref:@"fake_full_name"]) gFakeFullName = rygFakeValueForKey(@"fake_full_name_value");
	if (!gFakeUsername && !gFakeFullName) return;

	%init(FakeIdentity);

	Class jsonClass = object_getClass(NSJSONSerialization.class);
	if (jsonClass) MSHookMessageEx(jsonClass, @selector(JSONObjectWithData:options:error:), (IMP)new_JSONObjectWithData, (IMP *)&orig_JSONObjectWithData);

	rygRefreshRealIdentity();

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		rygRefreshRealIdentity();
	});

	for (NSString *name in @[UIApplicationDidBecomeActiveNotification, RYGActiveAccountDidChangeNotification]) {
		[NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
			rygRefreshRealIdentity();
		}];
	}
}
