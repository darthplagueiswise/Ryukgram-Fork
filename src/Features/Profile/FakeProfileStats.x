// Fake profile stats for own profile — follower/following/post counts
// and verified badge. Counts rewrite IGStatButton labels; verified flips
// is_verified on the parsed response and on the model getter.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL gFakeFollowerCount;
static BOOL gFakeFollowingCount;
static BOOL gFakePostCount;
static BOOL gFakeVerified;

static inline BOOL rygAnyFakeCountOn(void) {
	return gFakeFollowerCount || gFakeFollowingCount || gFakePostCount;
}

%group FakeProfileCounts

// Pass non-numeric input through ("1.2M"); format digit-only via shared formatter.
static NSString *rygFormatCount(NSString *raw) {
	raw = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	if (!raw.length) return nil;

	NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
	for (NSUInteger i = 0; i < raw.length; i++) {
		if (![digits characterIsMember:[raw characterAtIndex:i]]) return raw;
	}

	return [RYGUtils igStyleCount:raw.longLongValue];
}

static inline NSString *rygFakeValue(NSString *valueKey) {
	return rygFormatCount([NSUserDefaults.standardUserDefaults stringForKey:valueKey]);
}

// ============ Fake counts — IGStatButton label rewrite ============

// IG 428+: ObjC class `IGProfileSimpleAvatarStatsCell` was replaced by Swift
// `_TtC21IGProfileDetailHeader30IGProfileSimpleAvatarStatsCell`. Swift stored
// props also dropped the leading underscore on the ivar name.
static Class rygStatsCellClass(void) {
	static Class cached;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		cached = NSClassFromString(@"IGProfileSimpleAvatarStatsCell") ?: NSClassFromString(@"_TtC21IGProfileDetailHeader30IGProfileSimpleAvatarStatsCell");

		if (!cached) {
			unsigned int count = 0;
			Class *classes = objc_copyClassList(&count);

			for (unsigned int i = 0; i < count; i++) {
				const char *name = class_getName(classes[i]);
				if (name && strstr(name, "IGProfileSimpleAvatarStatsCell")) {
					cached = classes[i];
					break;
				}
			}

			free(classes);
		}
	});

	return cached;
}

static BOOL rygCellIsCurrentUser(UIView *cell) {
	id value = nil;

	@try {
		value = [cell valueForKey:@"isCurrentUser"];
	} @catch (...) {}

	if (value) return [value boolValue];

	Ivar ivar = class_getInstanceVariable(cell.class, "_isCurrentUser") ?: class_getInstanceVariable(cell.class, "isCurrentUser");
	return ivar ? *(BOOL *)((uint8_t *)(__bridge void *)cell + ivar_getOffset(ivar)) : NO;
}

static BOOL rygButtonIsOnOwnProfile(UIView *btn) {
	Class cellClass = rygStatsCellClass();
	if (!cellClass) return NO;

	for (UIView *view = btn; view; view = view.superview) {
		if ([view isKindOfClass:cellClass]) return rygCellIsCurrentUser(view);
	}

	return NO;
}

static NSString *rygFakeTextForName(NSString *name) {
	if (![name isKindOfClass:NSString.class]) return nil;

	NSString *low = name.lowercaseString;

	if ([low containsString:@"follower"] && gFakeFollowerCount) return rygFakeValue(@"fake_follower_count_value");
	if ([low containsString:@"following"] && gFakeFollowingCount) return rygFakeValue(@"fake_following_count_value");
	if ([low containsString:@"post"] && gFakePostCount) return rygFakeValue(@"fake_post_count_value");

	return nil;
}

static void rygApplyFakeToButton(id btn) {
	if (!rygButtonIsOnOwnProfile(btn)) return;

	Ivar nameIvar = class_getInstanceVariable([btn class], "_name");
	Ivar labelIvar = class_getInstanceVariable([btn class], "_countLabel");
	if (!nameIvar || !labelIvar) return;

	NSString *name = nil;
	UILabel *label = nil;

	@try {
		name = object_getIvar(btn, nameIvar);
		label = object_getIvar(btn, labelIvar);
	} @catch (...) {}

	NSString *fake = rygFakeTextForName(name);
	if ([label isKindOfClass:UILabel.class] && fake.length && ![fake isEqualToString:label.text]) {
		label.text = fake;
	}
}

static void (*orig_setName)(id, SEL, id);
static void new_setName(id self, SEL _cmd, id name) {
	if (orig_setName) orig_setName(self, _cmd, name);
	rygApplyFakeToButton(self);
}

static void (*orig_setCount)(id, SEL, id);
static void new_setCount(id self, SEL _cmd, id cfg) {
	if (orig_setCount) orig_setCount(self, _cmd, cfg);
	rygApplyFakeToButton(self);
}

static void (*orig_layout)(id, SEL);
static void new_layout(id self, SEL _cmd) {
	if (orig_layout) orig_layout(self, _cmd);
	rygApplyFakeToButton(self);
}

static void rygInitFakeCounts(void) {
	Class statButton = NSClassFromString(@"IGStatButton");
	if (!statButton) return;

	MSHookMessageEx(statButton, @selector(setName:), (IMP)new_setName, (IMP *)&orig_setName);
	MSHookMessageEx(statButton, @selector(setCount:), (IMP)new_setCount, (IMP *)&orig_setCount);
	MSHookMessageEx(statButton, @selector(layoutSubviews), (IMP)new_layout, (IMP *)&orig_layout);
}

%end

%group FakeProfileVerified

// ============ Fake verified ============

static NSString *gSelfPK;

static BOOL rygPKMatchesSelf(id pk) {
	if (!gSelfPK.length) return NO;
	if ([pk isKindOfClass:NSString.class]) return [pk isEqualToString:gSelfPK];
	if ([pk isKindOfClass:NSNumber.class]) return [[pk stringValue] isEqualToString:gSelfPK];
	return NO;
}

static void rygFlipVerifiedInJSON(id obj, int depth) {
	if (depth > 16) return;

	if ([obj isKindOfClass:NSMutableDictionary.class]) {
		NSMutableDictionary *dict = obj;
		id pk = dict[@"pk"] ?: dict[@"strong_id__"] ?: dict[@"user_id"] ?: dict[@"id"];

		if (rygPKMatchesSelf(pk)) dict[@"is_verified"] = @YES;

		for (id value in dict.allValues) {
			rygFlipVerifiedInJSON(value, depth + 1);
		}
	} else if ([obj isKindOfClass:NSMutableArray.class]) {
		for (id value in (NSMutableArray *)obj) {
			rygFlipVerifiedInJSON(value, depth + 1);
		}
	}
}

// Take the boxed true from IG — the protocol needs more than an NSNumber gives.
static id gBoxedTrue;

static void rygNoteBoxedTrue(id value) {
	if (gBoxedTrue || !value) return;

	if ([value respondsToSelector:@selector(boolValue)] && [value boolValue]) {
		gBoxedTrue = value;
	} else if ([value isKindOfClass:NSNumber.class] && [@YES respondsToSelector:@selector(asNumber)]) {
		gBoxedTrue = @YES;
	}
}

static BOOL rygUserIsSelf(id user) {
	id pk = [RYGUtils fieldCacheValue:user forKey:@"pk"] ?: [RYGUtils fieldCacheValue:user forKey:@"strong_id__"];
	return rygPKMatchesSelf(pk);
}

%hook IGBaseUser

- (id)isVerified {
	id value = %orig;
	rygNoteBoxedTrue(value);

	if (!gBoxedTrue || ([value respondsToSelector:@selector(boolValue)] && [value boolValue])) return value;
	return rygUserIsSelf(self) ? gBoxedTrue : value;
}

%end

static id (*orig_JSONObjectWithData)(Class, SEL, NSData *, NSJSONReadingOptions, NSError **);
static id new_JSONObjectWithData(Class self, SEL _cmd, NSData *data, NSJSONReadingOptions opts, NSError **err) {
	id result = orig_JSONObjectWithData ? orig_JSONObjectWithData(self, _cmd, data, opts | NSJSONReadingMutableContainers, err) : nil;
	if (result) rygFlipVerifiedInJSON(result, 0);
	return result;
}

static void rygRefreshSelfIdentity(void) {
	NSString *pk = nil;

	@try {
		pk = [[RYGUtils currentUserPK] copy];
	} @catch (...) {}

	if (pk.length) gSelfPK = pk;
}

static void rygInitFakeVerified(void) {
	rygRefreshSelfIdentity();

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		rygRefreshSelfIdentity();
	});

	[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
		rygRefreshSelfIdentity();
	}];

	Class jsonClass = object_getClass(NSJSONSerialization.class);
	if (jsonClass) {
		MSHookMessageEx(jsonClass, @selector(JSONObjectWithData:options:error:), (IMP)new_JSONObjectWithData, (IMP *)&orig_JSONObjectWithData);
	}
}

%end

%ctor {
	gFakeFollowerCount = [RYGUtils getBoolPref:@"fake_follower_count"];
	gFakeFollowingCount = [RYGUtils getBoolPref:@"fake_following_count"];
	gFakePostCount = [RYGUtils getBoolPref:@"fake_post_count"];
	gFakeVerified = [RYGUtils getBoolPref:@"fake_verified"];

	if (rygAnyFakeCountOn()) {
		%init(FakeProfileCounts);
		rygInitFakeCounts();
	}

	if (gFakeVerified) {
		%init(FakeProfileVerified);
		rygInitFakeVerified();
	}
}