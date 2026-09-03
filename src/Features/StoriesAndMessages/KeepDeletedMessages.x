#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../Theme/RYGTheme.h"
#import "RYGExcludedThreads.h"
#import "RYGDirectUserResolver.h"
#import "RYGDirectThreadInfo.h"
#import "RYGKeptMessageStore.h"
#import "../DeletedMessages/RYGDeletedMessagesCapture.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <stdatomic.h>

#define RYG_SENDER_MAP_MAX			3000
#define RYG_CONTENT_MAP_MAX			2500
#define RYG_PRESERVED_MAX			200
#define RYG_PRESERVED_IDS_KEY		@"RYGPreservedMsgIdsByPk"
#define RYG_PRESERVED_LEGACY_KEY	@"RYGPreservedMsgIds"
#define RYG_PRESERVED_TAG			1399

static atomic_int rygLocalDeleteInProgress = 0;

static NSMutableDictionary<NSString *, NSDate *> *rygDeleteForYouKeys;
static NSMutableSet<NSString *> *rygPendingLocalSids;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *rygPreservedByPk;
static NSMutableDictionary<NSString *, NSString *> *rygSenderPkBySid;
static NSMutableDictionary<NSString *, NSString *> *rygSenderNameBySid;
static NSMutableDictionary<NSString *, NSString *> *rygContentClassBySid;
static NSMutableDictionary<NSString *, NSString *> *rygThreadIdBySid;

static void rygUpdateCellIndicator(id cell);

#pragma mark - Prefs / runtime helpers

static inline BOOL rygKeepOn(void) { return [RYGUtils getBoolPref:@"keep_deleted_message"]; }
static inline BOOL rygKeepMineOn(void) { return [RYGUtils getBoolPref:@"keep_my_deleted_messages"]; }
static inline BOOL rygLogOn(void) { return [RYGUtils getBoolPref:@"deleted_messages_log_enabled"]; }
static inline BOOL rygIndicatorOn(void) { return [RYGUtils getBoolPref:@"indicate_unsent_messages"]; }
static inline BOOL rygUnsentLabelOn(void) { return [RYGUtils getBoolPref:@"unsent_indicator_label"]; }
static inline BOOL rygUnsentDimOn(void) { return [RYGUtils getBoolPref:@"unsent_indicator_dim"]; }
static inline BOOL rygUnsentHideAccessoriesOn(void) { return [RYGUtils getBoolPref:@"unsent_indicator_hide_accessories"]; }

static CGFloat rygUnsentAlpha(void) {
	double pct = [RYGUtils getDoublePref:@"unsent_indicator_opacity"];
	if (pct <= 0) pct = 45.0;
	return (CGFloat)MAX(0.05, MIN(1.0, pct / 100.0));
}

static CGFloat rygUnsentLabelSize(void) {
	double pt = [RYGUtils getDoublePref:@"unsent_indicator_label_size"];
	return (CGFloat)MAX(6.0, MIN(24.0, pt > 0 ? pt : 10.0));
}

static inline BOOL rygUnsentTintOn(void) { return [RYGUtils getBoolPref:@"unsent_indicator_bubble"]; }

static UIColor *rygUnsentTintColor(void) {
	UIColor *c = [RYGTheme colorFromHex:[RYGUtils getStringPref:@"unsent_indicator_bubble_color"]];
	return c ?: [UIColor colorWithRed:0.42 green:0.18 blue:0.18 alpha:1.0];
}

static UIColor *rygUnsentLabelColor(void) {
	UIColor *c = [RYGTheme colorFromHex:[RYGUtils getStringPref:@"unsent_indicator_label_color"]];
	return c ?: [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
}

static NSString *rygUnsentLabelText(void) {
	NSString *custom = [[RYGUtils getStringPref:@"unsent_indicator_text"]
		stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	return custom.length ? custom : RYGLocalized(@"Unsent");
}

static NSString *rygUnsentLabelPosition(void) {
	NSString *p = [RYGUtils getStringPref:@"unsent_indicator_position"];
	return p.length ? p : @"side";
}

static id rygIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;
		@try { return object_getIvar(obj, iv); }
		@catch (__unused id e) { return nil; }
	}
	return nil;
}

static void rygSetIvar(id obj, const char *name, id value) {
	if (!obj || !name) return;
	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;
		@try { object_setIvar(obj, iv, value); } @catch (__unused id e) {}
		return;
	}
}

static long long rygIntIvar(id obj, const char *name, long long fallback) {
	if (!obj || !name) return fallback;
	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;

		@try {
			ptrdiff_t off = ivar_getOffset(iv);
			return *(long long *)((char *)(__bridge void *)obj + off);
		} @catch (__unused id e) {
			return fallback;
		}
	}
	return fallback;
}

static id rygKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try {
		id v = [obj valueForKey:key];
		return v == NSNull.null ? nil : v;
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *rygString(id v) {
	if ([v isKindOfClass:NSString.class]) return [(NSString *)v length] ? v : nil;
	if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
	return nil;
}

static NSString *rygFirstIvarString(id obj, NSArray<NSString *> *names) {
	for (NSString *n in names) {
		NSString *s = rygString(rygIvar(obj, n.UTF8String));
		if (s.length) return s;
	}
	return nil;
}

#pragma mark - Message ids / metadata

static NSString *rygServerIdFromKey(id key) {
	return rygFirstIvarString(key, @[@"_messageServerId", @"_serverId"]);
}

static NSString *rygServerIdFromMetadata(id meta) {
	NSString *sid = rygFirstIvarString(meta, @[@"_serverId", @"_messageServerId"]);
	return sid.length ? sid : rygServerIdFromKey(rygIvar(meta, "_key"));
}

static NSString *rygServerIdFromMessage(id message) {
	NSString *sid = rygServerIdFromMetadata(rygIvar(message, "_metadata"));
	return sid.length ? sid : rygServerIdFromMetadata(message);
}

static NSString *rygSenderPkFromMessage(id message) {
	id meta = rygIvar(message, "_metadata");
	NSString *pk = rygString(rygIvar(meta, "_senderPk"));
	return pk.length ? pk : rygString(rygIvar(message, "_senderPk"));
}

static NSDictionary *rygThreadMessagesBySid(id applicator, NSString *threadId) {
	if (!threadId.length) return nil;

	@try {
		id cache = rygIvar(applicator, "_cache");
		SEL sel = NSSelectorFromString(@"threadClientStateForThreadId:");
		if (!cache || ![cache respondsToSelector:sel]) return nil;

		id state = ((id (*)(id, SEL, id))objc_msgSend)(cache, sel, threadId);
		id messageSet = rygIvar(state, "_threadMessageSet");
		id dict = rygIvar(messageSet, "_messagesByServerId");
		return [dict isKindOfClass:NSDictionary.class] ? dict : nil;
	} @catch (__unused id e) {}

	return nil;
}

// Live message from the thread cache — covers sids the session-only sender maps never saw.
static id rygCachedMessageForSid(id applicator, NSString *sid, NSString *threadId) {
	if (!sid.length) return nil;
	return rygThreadMessagesBySid(applicator, threadId)[sid];
}

static NSString *rygCellServerId(id cell) {
	id vm = rygIvar(cell, "_viewModel");

	if (!vm && [cell respondsToSelector:@selector(viewModel)]) {
		@try { vm = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(viewModel)); }
		@catch (__unused id e) {}
	}

	id meta = nil;
	SEL sel = NSSelectorFromString(@"messageMetadata");
	if ([vm respondsToSelector:sel]) {
		@try { meta = ((id (*)(id, SEL))objc_msgSend)(vm, sel); }
		@catch (__unused id e) {}
	}

	return rygServerIdFromMetadata(meta);
}

#pragma mark - Small stores

static void rygTrimMap(NSMutableDictionary *map, NSUInteger max) {
	if (map.count <= max) return;

	NSArray *keys = map.allKeys;
	NSUInteger drop = MAX((NSUInteger)1, keys.count / 10);
	for (NSUInteger i = 0; i < drop && i < keys.count; i++) {
		[map removeObjectForKey:keys[i]];
	}
}

static NSMutableDictionary<NSString *, NSString *> *rygSenderPkMap(void) {
	if (!rygSenderPkBySid) rygSenderPkBySid = NSMutableDictionary.dictionary;
	return rygSenderPkBySid;
}

static NSMutableDictionary<NSString *, NSString *> *rygSenderNameMap(void) {
	if (!rygSenderNameBySid) rygSenderNameBySid = NSMutableDictionary.dictionary;
	return rygSenderNameBySid;
}

static NSMutableDictionary<NSString *, NSString *> *rygContentClassMap(void) {
	if (!rygContentClassBySid) rygContentClassBySid = NSMutableDictionary.dictionary;
	return rygContentClassBySid;
}

static void rygTrackInMap(NSMutableDictionary<NSString *, NSString *> *map,
						  NSString *sid,
						  NSString *value,
						  NSUInteger max) {
	if (!sid.length || !value.length) return;
	map[sid] = value;
	rygTrimMap(map, max);
}

static NSMutableSet<NSString *> *rygPendingLocalSet(void) {
	if (!rygPendingLocalSids) rygPendingLocalSids = NSMutableSet.set;
	return rygPendingLocalSids;
}

static void rygTrackMessage(id message) {
	NSString *sid = rygServerIdFromMessage(message);
	if (!sid.length) return;

	NSString *pk = rygSenderPkFromMessage(message);
	if (pk.length) rygTrackInMap(rygSenderPkMap(), sid, pk, RYG_SENDER_MAP_MAX);

	rygTrackInMap(rygContentClassMap(), sid, NSStringFromClass([message class]), RYG_CONTENT_MAP_MAX);
}

static BOOL rygIsReactionOrActionLog(NSString *sid) {
	NSString *cls = sid.length ? rygContentClassMap()[sid] : nil;
	return [cls localizedCaseInsensitiveContainsString:@"reaction"] ||
		   [cls localizedCaseInsensitiveContainsString:@"actionlog"];
}

#pragma mark - Owner / preserved ids

static NSString *rygUserPK(id user) {
	return rygDirectUserResolverPKFromUser(user);
}

static NSString *rygOwnerPkFromApplicator(id applicator) {
	return rygUserPK(rygIvar(applicator, "_user"));
}

static NSString *rygUsernameFromUser(id user) {
	if (!user) return nil;

	id fc = rygIvar(user, "_fieldCache");
	if ([fc isKindOfClass:NSDictionary.class]) {
		NSString *u = rygString(fc[@"username"]);
		if (u.length) return u;
	}

	return rygString(rygKVC(user, @"username"));
}

static NSString *rygOwnerUsernameFromApplicator(id applicator) {
	return rygUsernameFromUser(rygIvar(applicator, "_user"));
}

static NSString *rygLastKnownPk;

// Message sets are rebuilt off the main thread, so the window walk has to stay on it.
static NSString *rygCurrentUserPk(void) {
	if (!NSThread.isMainThread) {
		if (!rygLastKnownPk.length) dispatch_async(dispatch_get_main_queue(), ^{ rygCurrentUserPk(); });
		return rygLastKnownPk;
	}

	@try {
		for (UIWindow *w in UIApplication.sharedApplication.windows) {
			id session = rygKVC(w, @"userSession");
			NSString *pk = rygUserPK(rygKVC(session, @"user"));
			if (pk.length) {
				rygLastKnownPk = pk;
				return pk;
			}
		}
	} @catch (__unused id e) {}

	return nil;
}

static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *rygPreservedStore(void) {
	if (rygPreservedByPk) return rygPreservedByPk;

	rygPreservedByPk = NSMutableDictionary.dictionary;

	NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:RYG_PRESERVED_IDS_KEY];
	if ([saved isKindOfClass:NSDictionary.class]) {
		for (NSString *pk in saved) {
			NSArray *arr = [saved[pk] isKindOfClass:NSArray.class] ? saved[pk] : nil;
			if (arr.count) rygPreservedByPk[pk] = [NSMutableSet setWithArray:arr];
		}
	}

	NSArray *legacy = [NSUserDefaults.standardUserDefaults arrayForKey:RYG_PRESERVED_LEGACY_KEY];
	NSString *currentPk = legacy.count ? rygCurrentUserPk() : nil;
	if (legacy.count && currentPk.length) {
		NSMutableSet *bucket = rygPreservedByPk[currentPk] ?: NSMutableSet.set;
		[bucket addObjectsFromArray:legacy];
		rygPreservedByPk[currentPk] = bucket;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:RYG_PRESERVED_LEGACY_KEY];
	}

	return rygPreservedByPk;
}

static NSMutableSet<NSString *> *rygBucket(NSString *pk, BOOL create) {
	if (!pk.length) return nil;

	NSMutableDictionary *store = rygPreservedStore();
	NSMutableSet *bucket = store[pk];

	if (!bucket && create) {
		bucket = NSMutableSet.set;
		store[pk] = bucket;
	}
	return bucket;
}

NSMutableSet *rygGetPreservedIds(void) {
	NSString *pk = rygCurrentUserPk();
	return pk.length ? (rygBucket(pk, YES) ?: NSMutableSet.set) : NSMutableSet.set;
}

static void rygSavePreservedIds(void) {
	NSMutableDictionary *out = NSMutableDictionary.dictionary;

	for (NSString *pk in rygPreservedStore()) {
		NSMutableSet *set = rygPreservedByPk[pk];

		while (set.count > RYG_PRESERVED_MAX) {
			[set removeObject:set.anyObject];
		}

		if (set.count) out[pk] = set.allObjects;
	}

	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	if (out.count) [d setObject:out forKey:RYG_PRESERVED_IDS_KEY];
	else [d removeObjectForKey:RYG_PRESERVED_IDS_KEY];
}

void rygClearPreservedIds(void) {
	NSString *pk = rygCurrentUserPk();
	if (!pk.length) return;

	[rygPreservedStore() removeObjectForKey:pk];
	rygSavePreservedIds();
	[RYGKeptMessageStore resetForOwnerPK:pk];
}

#pragma mark - Delete-for-you / local delete tracking

static void rygPruneDeleteForYouKeys(void) {
	if (!rygDeleteForYouKeys.count) return;

	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-10.0];
	for (NSString *sid in rygDeleteForYouKeys.allKeys) {
		if ([rygDeleteForYouKeys[sid] compare:cutoff] == NSOrderedAscending) {
			[rygDeleteForYouKeys removeObjectForKey:sid];
		}
	}
}

static BOOL rygKeysIntersectSet(NSArray *keys, NSSet *set) {
	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length && [set containsObject:sid]) return YES;
	}
	return NO;
}

static void rygRemoveKeysFromSet(NSArray *keys, NSMutableSet *set) {
	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length) [set removeObject:sid];
	}
}

static BOOL rygKeysMarkedDeleteForYou(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length && rygDeleteForYouKeys[sid]) return YES;
	}
	return NO;
}

static void rygRemoveDeleteForYouKeys(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length) [rygDeleteForYouKeys removeObjectForKey:sid];
	}
}

static void rygTrackDeleteForYouKeys(NSArray *keys) {
	if (!rygDeleteForYouKeys) rygDeleteForYouKeys = NSMutableDictionary.dictionary;

	NSDate *now = NSDate.date;
	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length) rygDeleteForYouKeys[sid] = now;
	}
}

static void rygTrackPendingLocalKeys(NSArray *keys) {
	NSMutableSet *pending = rygPendingLocalSet();

	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (sid.length) [pending addObject:sid];
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		rygRemoveKeysFromSet(keys, pending);
	});
}

#pragma mark - Preserved message re-injection

static NSMutableDictionary<NSString *, id> *rygKeptPublished;
static NSMutableDictionary<NSString *, id> *rygKeptUI;

// An unsend only carries an id, so hold what the thread has shown.
#define RYG_RECENT_MAX 1500

static NSMutableDictionary<NSString *, id> *rygRecentBySid;
static NSMutableOrderedSet<NSString *> *rygRecentOrder;

static void rygRememberPublishedMessages(NSDictionary *bySid) {
	if (![bySid isKindOfClass:NSDictionary.class] || !bySid.count) return;

	if (!rygRecentBySid) {
		rygRecentBySid = NSMutableDictionary.dictionary;
		rygRecentOrder = NSMutableOrderedSet.orderedSet;
	}

	for (NSString *sid in bySid) {
		if (![sid isKindOfClass:NSString.class]) continue;
		rygRecentBySid[sid] = bySid[sid];
		[rygRecentOrder removeObject:sid];
		[rygRecentOrder addObject:sid];
	}

	while (rygRecentOrder.count > RYG_RECENT_MAX) {
		NSString *oldest = rygRecentOrder.firstObject;
		[rygRecentOrder removeObjectAtIndex:0];
		[rygRecentBySid removeObjectForKey:oldest];
	}
}

// Pool, then the on-disk mirror, then anything already archived for this id.
static id rygRecoverMessage(NSString *sid) {
	if (!sid.length) return nil;

	NSString *ownerPk = rygCurrentUserPk();
	id message = rygRecentBySid[sid];

	if (!message) message = [RYGKeptMessageStore mirroredMessageForServerId:sid ownerPK:ownerPk];
	if (!message) message = [RYGKeptMessageStore messageForServerId:sid ownerPK:ownerPk];
	if (!message) return nil;

	[RYGKeptMessageStore saveMessage:message serverId:sid ownerPK:ownerPk];
	return message;
}

static id rygCallSel(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); }
	@catch (__unused id e) { return nil; }
}

static id rygMessageMetadata(id message) {
	id meta = rygCallSel(message, @selector(metadata));
	if (meta) return meta;

	meta = rygIvar(message, "_metadata");
	if (meta) return meta;

	return rygCallSel(message, NSSelectorFromString(@"messageMetadata"));
}

static id rygInnerPublishedMessage(id message) {
	id inner = rygIvar(message, "_message_publishedMessage");
	if (inner) return inner;

	return rygCallSel(message, NSSelectorFromString(@"publishedMessage"));
}

static NSString *rygMessageThreadId(id message) {
	if (!message) return nil;

	NSString *tid = rygString(rygCallSel(rygMessageMetadata(message), NSSelectorFromString(@"threadId")));
	if (tid.length) return tid;

	tid = rygString(rygIvar(message, "_message_threadId"));
	if (tid.length) return tid;

	id inner = rygInnerPublishedMessage(message);
	if (inner) return rygString(rygCallSel(rygMessageMetadata(inner), NSSelectorFromString(@"threadId")));

	id nested = rygCallSel(message, NSSelectorFromString(@"message"));
	return nested && nested != message ? rygMessageThreadId(nested) : nil;
}

static NSDate *rygMessageDate(id message) {
	if (!message) return nil;

	id meta = rygMessageMetadata(message);
	for (NSString *name in @[@"serverTimestamp", @"sentDate"]) {
		id date = rygCallSel(meta, NSSelectorFromString(name));
		if ([date isKindOfClass:NSDate.class]) return date;
	}

	id sorting = rygCallSel(meta, NSSelectorFromString(@"sortingInfo")) ?: rygIvar(meta, "_sortingInfo");
	id primary = rygCallSel(sorting, NSSelectorFromString(@"primarySortingDate"));
	if ([primary isKindOfClass:NSDate.class]) return primary;

	id inner = rygInnerPublishedMessage(message);
	if (inner) return rygMessageDate(inner);

	id nested = rygCallSel(message, NSSelectorFromString(@"message"));
	return nested && nested != message ? rygMessageDate(nested) : nil;
}

static NSUInteger rygInsertionIndex(NSArray *sorted, NSDate *date) {
	NSDate *first = rygMessageDate(sorted.firstObject);
	NSDate *last = rygMessageDate(sorted.lastObject);
	BOOL ascending = !first || !last || [first compare:last] != NSOrderedDescending;

	for (NSUInteger i = 0; i < sorted.count; i++) {
		NSDate *other = rygMessageDate(sorted[i]);
		if (!other) continue;

		NSComparisonResult cmp = [date compare:other];
		if (ascending ? cmp != NSOrderedDescending : cmp != NSOrderedAscending) return i;
	}

	return sorted.count;
}

// A reload rebuilds these from the server window and drops what we kept.
static void rygReinjectPreserved(NSMutableDictionary<NSString *, id> *cache, BOOL durable, NSArray **sortedRef, NSDictionary **bySidRef) {
	NSArray *sorted = *sortedRef;
	NSDictionary *bySid = *bySidRef;

	if (![sorted isKindOfClass:NSArray.class] || ![bySid isKindOfClass:NSDictionary.class] || !sorted.count) return;

	NSSet<NSString *> *preserved = rygGetPreservedIds();
	if (!preserved.count) return;

	NSString *threadId = rygMessageThreadId(sorted.firstObject);
	if (!threadId.length) return;

	NSString *ownerPk = rygCurrentUserPk();
	NSMutableArray *missing = NSMutableArray.array;

	for (NSString *sid in preserved) {
		id present = bySid[sid];

		if (present) {
			cache[sid] = present;
			if (durable) [RYGKeptMessageStore saveMessage:present serverId:sid ownerPK:ownerPk];
			continue;
		}

		id kept = cache[sid];
		if (!kept && durable) {
			kept = [RYGKeptMessageStore messageForServerId:sid ownerPK:ownerPk];
			if (kept) cache[sid] = kept;
		}

		if (kept && [rygMessageThreadId(kept) isEqualToString:threadId]) [missing addObject:kept];
	}

	if (!missing.count) return;

	NSMutableArray *patchedSorted = [sorted mutableCopy];
	NSMutableDictionary *patchedBySid = [bySid mutableCopy];

	for (id message in missing) {
		NSDate *date = rygMessageDate(message);
		NSString *sid = rygServerIdFromMessage(message)
			?: rygString(rygCallSel(rygMessageMetadata(message), NSSelectorFromString(@"serverId")));
		if (!date || !sid.length) continue;

		[patchedSorted insertObject:message atIndex:rygInsertionIndex(patchedSorted, date)];
		patchedBySid[sid] = message;
	}

	if (patchedSorted.count == sorted.count) return;

	*sortedRef = patchedSorted;
	*bySidRef = patchedBySid;
}

static NSMutableDictionary<NSString *, id> *rygKeptPublishedCache(void) {
	if (!rygKeptPublished) rygKeptPublished = NSMutableDictionary.dictionary;
	return rygKeptPublished;
}

static NSMutableDictionary<NSString *, id> *rygKeptUICache(void) {
	if (!rygKeptUI) rygKeptUI = NSMutableDictionary.dictionary;
	return rygKeptUI;
}

#pragma mark - Update extraction

static void rygCaptureMessagesFromUpdate(id update, NSString *ownerPk, NSString *threadId) {
	NSSet *preserved = rygLogOn() ? rygGetPreservedIds() : nil;

	for (NSString *ivar in @[@"_insertMessages", @"_replaceMessages_messages"]) {
		NSArray *messages = rygIvar(update, ivar.UTF8String);
		if (![messages isKindOfClass:NSArray.class]) continue;

		for (id m in messages) {
			rygTrackMessage(m);
			rygDMCaptureNoteInsert(m);

			@try {
				if (preserved.count) {
					NSString *sid = rygServerIdFromMessage(m);
					if (sid.length && [preserved containsObject:sid]) {
						rygDMCaptureNotePreservedMessage(m, ownerPk, threadId);
					}
				}
			} @catch (__unused id e) {}
		}
	}
}

static void rygCaptureEditsFromUpdate(id update, NSString *ownerPk, NSString *threadId) {
	if (!rygLogOn()) return;

	NSString *sid = rygString(rygIvar(update, "_mutateMessage_messageId"));
	id mut = rygIvar(update, "_mutateMessage_contentMutation");
	if (sid.length && mut) {
		rygDMCaptureNoteEdit(sid, mut, ownerPk, threadId);
		rygDMCaptureNoteReaction(sid, mut, ownerPk, threadId);
	}

	NSArray *pairs = rygIvar(update, "_mutateMultipleMessages_contentMutations");
	if (![pairs isKindOfClass:NSArray.class]) return;

	for (id pair in pairs) {
		NSString *psid = rygString(rygIvar(pair, "_messageId")) ?: rygString(rygKVC(pair, @"messageId"));
		id pmut = rygIvar(pair, "_contentMutation") ?: rygKVC(pair, @"contentMutation");
		if (psid.length && pmut) {
			rygDMCaptureNoteEdit(psid, pmut, ownerPk, threadId);
			rygDMCaptureNoteReaction(psid, pmut, ownerPk, threadId);
		}
	}
}

static id rygMessageUpdateFromThreadUpdate(id threadUpdate) {
	return rygIvar(threadUpdate, "_messageUpdate") ?: rygKVC(threadUpdate, @"messageUpdate");
}

static NSString *rygThreadIdFromCacheUpdate(id cacheUpdate) {
	NSString *tid = rygString(rygKVC(cacheUpdate, @"threadId"));
	if (tid.length) return tid;

	tid = rygString(rygIvar(cacheUpdate, "_threadId"));
	if (tid.length) return tid;

	return rygString(rygIvar(rygIvar(cacheUpdate, "_threadUpdate"), "_removeThread_threadId"));
}

static NSArray *rygThreadUpdatesFromCacheUpdate(id cacheUpdate) {
	id updates = rygKVC(cacheUpdate, @"threadUpdates");
	if ([updates isKindOfClass:NSArray.class]) return updates;

	id single = rygIvar(cacheUpdate, "_threadUpdate");
	return single ? @[single] : @[];
}

#pragma mark - Processing

static BOOL rygProcessMessageUpdate(id update,
									NSString *ownerPk,
									NSString *threadId,
									id applicator,
									BOOL keepEnabled,
									BOOL logEnabled,
									NSMutableSet<NSString *> *preserved) {
	if (!update || !ownerPk.length) return NO;

	// Capture is best-effort and must never prevent the keep-deleted logic below from running.
	@try {
		rygCaptureMessagesFromUpdate(update, ownerPk, threadId);
		rygCaptureEditsFromUpdate(update, ownerPk, threadId);
	} @catch (__unused id e) {}

	NSArray *keys = rygIvar(update, "_removeMessages_messageKeys");
	if (![keys isKindOfClass:NSArray.class] || !keys.count) return NO;

	long long reason = rygIntIvar(update, "_removeMessages_reason", -1);

	if (reason == 2) {
		rygTrackDeleteForYouKeys(keys);
		return NO;
	}

	if (reason != 0) return NO;

	BOOL keepMine = rygKeepMineOn();

	NSMutableSet *pending = rygPendingLocalSet();
	BOOL localDelete = rygKeysIntersectSet(keys, pending) || atomic_load(&rygLocalDeleteInProgress) > 0;
	rygRemoveKeysFromSet(keys, pending);
	if (localDelete && !keepMine) return NO;

	if (rygKeysMarkedDeleteForYou(keys)) {
		rygRemoveDeleteForYouKeys(keys);
		return NO;
	}

	NSMutableArray *unsendKeys = NSMutableArray.array;
	NSMutableSet *bucket = keepEnabled ? rygBucket(ownerPk, YES) : nil;

	for (id key in keys) {
		NSString *sid = rygServerIdFromKey(key);
		if (!sid.length || rygIsReactionOrActionLog(sid)) continue;

		// An old unsend is gone from memory, so the kept copy is the only source.
		id recovered = rygRecoverMessage(sid);
		if (recovered && logEnabled) rygDMCaptureNoteInsert(recovered);

		NSString *senderPk = rygSenderPkMap()[sid];
		if (!senderPk.length) {
			senderPk = rygSenderPkFromMessage(rygCachedMessageForSid(applicator, sid, threadId))
					?: rygSenderPkFromMessage(recovered);
			if (senderPk.length) rygTrackInMap(rygSenderPkMap(), sid, senderPk, RYG_SENDER_MAP_MAX);
		}
		if (senderPk.length && [senderPk isEqualToString:ownerPk] && !keepMine) continue;

		[unsendKeys addObject:key];

		if (keepEnabled) {
			[bucket addObject:sid];
			[preserved addObject:sid];

			if (!rygThreadIdBySid) rygThreadIdBySid = NSMutableDictionary.dictionary;
			rygTrackInMap(rygThreadIdBySid, sid, threadId, RYG_SENDER_MAP_MAX);
		}
	}

	if (!unsendKeys.count) return NO;

	// Log capture only. This does not preserve the message bubble.
	if (logEnabled) rygDMCaptureNoteRemoveKeys(unsendKeys, applicator, ownerPk, threadId);

	// Only block IG's remove mutation when keep-deleted is enabled.
	if (keepEnabled) {
		rygSetIvar(update, "_removeMessages_messageKeys", nil);
		return YES;
	}

	return NO;
}

static NSSet<NSString *> *rygProcessCacheUpdate(id cacheUpdate, NSString *ownerPk, id applicator, BOOL keepEnabled, BOOL logEnabled) {
	NSMutableSet *preserved = NSMutableSet.set;
	NSString *threadId = rygThreadIdFromCacheUpdate(cacheUpdate);

	if (!cacheUpdate || !threadId.length || [RYGExcludedThreads shouldKeepDeletedBeBlockedForThreadId:threadId]) return preserved;

	if (!rygDeleteForYouKeys) rygDeleteForYouKeys = NSMutableDictionary.dictionary;
	rygPruneDeleteForYouKeys();

	for (id tu in rygThreadUpdatesFromCacheUpdate(cacheUpdate)) {
		id msgUpdate = rygMessageUpdateFromThreadUpdate(tu);
		if (msgUpdate) {
			rygProcessMessageUpdate(msgUpdate, ownerPk, threadId, applicator, keepEnabled, logEnabled, preserved);
		}
	}

	return preserved;
}

#pragma mark - Toast / indicator

static NSString *rygUnsentText(NSString *sender, NSString *deleter) {
	if (sender.length && deleter.length) {
		return [sender isEqualToString:deleter]
			? [NSString stringWithFormat:RYGLocalized(@"%@ unsent a message"), sender]
			: [NSString stringWithFormat:RYGLocalized(@"%@ unsent a message from %@"), deleter, sender];
	}
	if (sender.length) return [NSString stringWithFormat:RYGLocalized(@"Message from %@ was unsent"), sender];
	if (deleter.length) return [NSString stringWithFormat:RYGLocalized(@"%@ unsent a message"), deleter];
	return RYGLocalized(@"A message was unsent");
}

static void rygShowUnsentToastForChat(NSString *chat, NSString *ownerAccount) {
	NSString *body = chat.length
		? [NSString stringWithFormat:RYGLocalized(@"A message in %@ was unsent"), chat]
		: RYGLocalized(@"A message was unsent");

	RYGNotify(RYG_NOTIF_UNSENT_MESSAGE,
			  ownerAccount.length ? ownerAccount : body,
			  ownerAccount.length ? body : nil,
			  @"trash.fill",
			  RYGNotificationToneError);
}

static void rygShowUnsentToastNamingChat(NSString *threadId, NSString *ownerPk, NSString *ownerAccount) {
	if (!threadId.length) {
		rygShowUnsentToastForChat(nil, ownerAccount);
		return;
	}

	[RYGDirectThreadInfo fetchThreadId:threadId ownerPK:ownerPk completion:^(id thread) {
		NSDictionary *group = [RYGDirectThreadInfo groupInfoForThread:thread viewerPK:ownerPk];
		NSString *chat = [group[@"name"] isKindOfClass:NSString.class] ? group[@"name"] : nil;

		if (!chat.length) {
			NSDictionary<NSString *, NSDictionary *> *participants = [RYGDirectThreadInfo participantsForThread:thread];
			for (NSString *pk in participants) {
				if (ownerPk.length && [pk isEqualToString:ownerPk]) continue;
				NSString *username = participants[pk][@"username"];
				if (username.length) { chat = username; break; }
			}
		}

		rygShowUnsentToastForChat(chat, ownerAccount);
	}];
}

static void rygShowUnsentToast(NSString *sender, NSString *ownerAccount) {
	NSString *body = rygUnsentText(sender, sender);
	RYGNotify(RYG_NOTIF_UNSENT_MESSAGE,
			  ownerAccount.length ? ownerAccount : body,
			  ownerAccount.length ? body : nil,
			  @"trash.fill",
			  RYGNotificationToneError);
}

static UIView *rygAccessoryWrapper(UIView *view) {
	for (UIView *cur = view; cur && cur.superview; cur = cur.superview) {
		CGSize s = cur.frame.size;
		if (s.width >= 32.0 && s.width <= 64.0 && fabs(s.width - s.height) < 6.0) return cur;
	}
	return view;
}

static const void *kAccessoriesHiddenKey = &kAccessoriesHiddenKey;

static void rygSetTrailingAccessoriesHidden(id cell, BOOL hidden) {
	// Skip the walk when restoring a cell we never hid (the common case).
	if (!hidden && !objc_getAssociatedObject(cell, kAccessoriesHiddenKey)) return;
	objc_setAssociatedObject(cell, kAccessoriesHiddenKey, hidden ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	// Pre-434 path: the cell exposed accessory views via _tappableAccessoryViews.
	NSArray *views = rygIvar(cell, "_tappableAccessoryViews");
	if ([views isKindOfClass:NSArray.class]) {
		for (UIView *v in views) {
			if (![v isKindOfClass:UIView.class]) continue;
			UIView *wrap = rygAccessoryWrapper(v);
			wrap.hidden = hidden;
			if (wrap != v) v.hidden = hidden;
		}
		return;
	}

	// IG 434+
	if (![cell isKindOfClass:UIView.class]) return;
	Class shortcutCls = NSClassFromString(@"IGDirectMessageCellShortcutView");
	if (!shortcutCls) return;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:cell];
	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];
		for (UIView *sub in v.subviews) {
			if ([sub isKindOfClass:shortcutCls]) sub.hidden = hidden;
			else [stack addObject:sub];
		}
	}
}

static BOOL rygCellIsPreserved(id cell) {
	NSString *sid = rygCellServerId(cell);
	return sid.length && [rygGetPreservedIds() containsObject:sid];
}

static BOOL rygCellIsOutgoing(id cell) {
	NSString *sid = rygCellServerId(cell);
	NSString *senderPk = sid.length ? rygSenderPkMap()[sid] : nil;
	NSString *me = rygCurrentUserPk();
	return senderPk.length && me.length && [senderPk isEqualToString:me];
}

static UIView *rygMessageContentContainer(id cell) {
	UIView *parent = rygIvar(cell, "_messageContentContainerView");
	if (!parent && [cell respondsToSelector:@selector(messageContentContainerView)]) {
		@try { parent = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(messageContentContainerView)); }
		@catch (__unused id e) {}
	}
	return [parent isKindOfClass:UIView.class] ? parent : cell;
}

static const void *kBubbleDimmedKey = &kBubbleDimmedKey;

static void rygSetBubbleDimmed(id cell, BOOL dimmed) {
	if (!dimmed && !objc_getAssociatedObject(cell, kBubbleDimmedKey)) return;
	objc_setAssociatedObject(cell, kBubbleDimmedKey, dimmed ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	CGFloat alpha = dimmed ? rygUnsentAlpha() : 1.0;

	// Dim the content, not the container — the "Unsent" tag is a sibling and must stay crisp.
	UIView *container = rygMessageContentContainer(cell);
	container.alpha = 1.0;
	for (UIView *sub in container.subviews) {
		if (sub.tag == RYG_PRESERVED_TAG) continue;
		sub.alpha = alpha;
	}
}

static const void *kCellTintKey = &kCellTintKey;
static const void *kBubbleTintOrigKey = &kBubbleTintOrigKey;

static BOOL rygTintEnabled;
static atomic_bool rygTintEverApplied;

static UIColor *rygTintColorForView(UIView *view) {
	if (!atomic_load(&rygTintEverApplied)) return nil;

	for (UIView *v = view; v; v = v.superview) {
		UIColor *c = objc_getAssociatedObject(v, kCellTintKey);
		if (c) return c;
	}
	return nil;
}

BOOL RYGUnsentTintOwnsView(UIView *view) {
	return rygTintColorForView(view) != nil;
}

static BOOL rygIsClass(UIView *view, NSString *name) {
	Class cls = NSClassFromString(name);
	return cls && [view isKindOfClass:cls];
}

static void rygEachSubviewDeep(UIView *root, void (^block)(UIView *sub)) {
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];
		for (UIView *sub in v.subviews) {
			block(sub);
			[stack addObject:sub];
		}
	}
}

// Gradient colors and layer contents both draw over a layer background, so both give way.
static void rygTintSurface(UIView *view, UIColor *color) {
	CAGradientLayer *grad = [view.layer isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)view.layer : nil;
	NSDictionary *orig = objc_getAssociatedObject(view, kBubbleTintOrigKey);

	if (!color) {
		if (!orig) return;

		[CATransaction begin];
		[CATransaction setDisableActions:YES];
		view.layer.backgroundColor = orig[@"bg"] == NSNull.null ? NULL : ((UIColor *)orig[@"bg"]).CGColor;
		view.layer.contents = orig[@"contents"] == NSNull.null ? nil : orig[@"contents"];
		if (grad) grad.colors = orig[@"colors"] == NSNull.null ? nil : orig[@"colors"];
		[CATransaction commit];

		objc_setAssociatedObject(view, kBubbleTintOrigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[view setNeedsLayout];
		return;
	}

	if (!orig) {
		UIColor *bg = view.layer.backgroundColor ? [UIColor colorWithCGColor:view.layer.backgroundColor] : nil;
		objc_setAssociatedObject(view, kBubbleTintOrigKey,
								 @{ @"bg": bg ?: NSNull.null,
									@"contents": view.layer.contents ?: NSNull.null,
									@"colors": grad.colors ?: NSNull.null },
								 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	view.layer.contents = nil;
	if (grad) grad.colors = @[ (__bridge id)color.CGColor, (__bridge id)color.CGColor ];
	else view.layer.backgroundColor = color.CGColor;
	[CATransaction commit];
}

// Innermost first; painting anything but the first non-empty tier leaks a square behind the bubble.
static NSArray<NSArray<UIView *> *> *rygBubbleFillTiers(UIView *bubble) {
	NSMutableArray<UIView *> *gradients = NSMutableArray.array;
	NSMutableArray<UIView *> *wrappers = NSMutableArray.array;
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:bubble];

	// IG hides the gradient wrapper on plain bubbles; tinting a hidden branch shows nothing.
	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		for (UIView *sub in v.subviews) {
			if (sub.hidden || sub.alpha < 0.02) continue;

			if ([sub.layer isKindOfClass:CAGradientLayer.class]) [gradients addObject:sub];
			else if (rygIsClass(sub, @"IGDirectGradientView")) [wrappers addObject:sub];

			[stack addObject:sub];
		}
	}

	return @[ gradients, wrappers, @[ bubble ] ];
}

static BOOL rygHasNestedBubble(UIView *bubble) {
	Class cls = NSClassFromString(@"IGDirectMessageBubbleView");
	if (!cls) return NO;

	__block BOOL nested = NO;
	rygEachSubviewDeep(bubble, ^(UIView *sub) {
		if (!nested && [sub isKindOfClass:cls]) nested = YES;
	});
	return nested;
}

static void rygTintBubble(UIView *bubble, UIColor *color) {
	NSArray<NSArray<UIView *> *> *tiers = rygBubbleFillTiers(bubble);

	if (!color) {
		for (NSArray<UIView *> *tier in tiers)
			for (UIView *v in tier) rygTintSurface(v, nil);
		return;
	}

	NSArray<UIView *> *targets = nil;
	for (NSArray<UIView *> *tier in tiers) {
		if (tier.count) { targets = tier; break; }
	}

	for (NSArray<UIView *> *tier in tiers) {
		if (tier == targets) continue;
		for (UIView *v in tier) rygTintSurface(v, nil);
	}

	for (UIView *v in targets) rygTintSurface(v, color);
}

static void rygApplyBubbleTint(id cell, UIColor *color) {
	if (!rygTintEnabled) return;
	if (!color && !objc_getAssociatedObject(cell, kCellTintKey)) return;
	objc_setAssociatedObject(cell, kCellTintKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	if (color) atomic_store(&rygTintEverApplied, true);

	Class bubbleCls = NSClassFromString(@"IGDirectMessageBubbleView");
	if (!bubbleCls) return;

	UIView *container = rygMessageContentContainer(cell);
	NSMutableArray<UIView *> *bubbles = NSMutableArray.array;
	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:container];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		for (UIView *sub in v.subviews) {
			NSString *name = NSStringFromClass(sub.class);

			// The quoted message inside a reply belongs to whoever sent it, not to this one.
			if ([name containsString:@"ContextReply"] || [name containsString:@"RepliedTo"]) continue;

			if ([sub isKindOfClass:bubbleCls]) [bubbles addObject:sub];
			[stack addObject:sub];
		}
	}

	// Text messages nest a second bubble view; the outer one is a square wrapper.
	for (UIView *bubble in bubbles) rygTintBubble(bubble, rygHasNestedBubble(bubble) ? nil : color);
}

static void rygStyleUnsentLabel(RYGChromeLabel *label) {
	label.text = rygUnsentLabelText();
	label.font = [UIFont italicSystemFontOfSize:rygUnsentLabelSize()];
	label.textColor = rygUnsentLabelColor();
}

static void rygPinUnsentLabel(RYGChromeLabel *label, UIView *bubble, BOOL outgoing) {
	NSString *pos = rygUnsentLabelPosition();

	if ([pos isEqualToString:@"above"] || [pos isEqualToString:@"below"]) {
		NSLayoutConstraint *vertical = [pos isEqualToString:@"above"]
			? [label.bottomAnchor constraintEqualToAnchor:bubble.topAnchor constant:-2.0]
			: [label.topAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:2.0];

		[NSLayoutConstraint activateConstraints:@[
			vertical,
			outgoing ? [label.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor]
					 : [label.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor],
		]];
		return;
	}

	NSLayoutConstraint *horizontal = outgoing
		? [label.trailingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:-4.0]
		: [label.leadingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:4.0];

	[NSLayoutConstraint activateConstraints:@[
		horizontal,
		[label.centerYAnchor constraintEqualToAnchor:bubble.centerYAnchor],
	]];
}

static const void *kLabelPositionKey = &kLabelPositionKey;

static void rygUpdateCellIndicator(id cell) {
	if (![cell isKindOfClass:UIView.class]) return;

	UIView *view = cell;
	UIView *old = [view viewWithTag:RYG_PRESERVED_TAG];
	BOOL marked = rygIndicatorOn() && rygCellIsPreserved(cell);
	BOOL wantsLabel = marked && rygUnsentLabelOn();

	rygSetBubbleDimmed(cell, marked && rygUnsentDimOn());
	rygApplyBubbleTint(cell, marked && rygUnsentTintOn() ? rygUnsentTintColor() : nil);
	rygSetTrailingAccessoriesHidden(cell, marked && rygUnsentHideAccessoriesOn());

	if (!wantsLabel) {
		if (old) {
			[old removeFromSuperview];
			objc_setAssociatedObject(cell, kLabelPositionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		return;
	}

	NSString *pos = rygUnsentLabelPosition();

	if ([old isKindOfClass:RYGChromeLabel.class] &&
		[pos isEqualToString:objc_getAssociatedObject(cell, kLabelPositionKey)]) {
		rygStyleUnsentLabel((RYGChromeLabel *)old);
		return;
	}

	[old removeFromSuperview];

	UIView *bubble = rygMessageContentContainer(cell);

	// Tag rides on the bubble so it tracks IG's long-press move; a cell-level sibling desyncs.
	bubble.clipsToBounds = NO;

	RYGChromeLabel *label = [[RYGChromeLabel alloc] initWithText:rygUnsentLabelText()];
	label.tag = RYG_PRESERVED_TAG;
	rygStyleUnsentLabel(label);
	[bubble addSubview:label];

	rygPinUnsentLabel(label, bubble, rygCellIsOutgoing(cell));
	objc_setAssociatedObject(cell, kLabelPositionKey, pos, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void rygRefreshVisibleCellIndicators(void) {
	if (!rygIndicatorOn()) return;

	Class cls = NSClassFromString(@"_TtC19IGDirectMessageCell19IGDirectMessageCell")
				?: NSClassFromString(@"IGDirectMessageCell");
	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	if (!cls || !window) return;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		if ([v isKindOfClass:cls]) {
			rygUpdateCellIndicator(v);
			continue;
		}

		for (UIView *sub in v.subviews) [stack addObject:sub];
	}
}

#pragma mark - Hooks

static void (*orig_applyUpdates)(id, SEL, id, id, id);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
	rygDirectUserResolverSetActiveApplicator(self);

	BOOL keepEnabled = rygKeepOn();
	BOOL logEnabled = rygLogOn();

	if (!keepEnabled && !logEnabled) {
		orig_applyUpdates(self, _cmd, updates, completion, userAccess);
		return;
	}

	NSString *ownerPk = rygOwnerPkFromApplicator(self);
	NSMutableSet *preserved = NSMutableSet.set;

	if (ownerPk.length && [updates isKindOfClass:NSArray.class]) {
		for (id update in (NSArray *)updates) {
			NSSet *set = rygProcessCacheUpdate(update, ownerPk, self, keepEnabled, logEnabled);
			if (set.count) [preserved unionSet:set];
		}
	}

	if (preserved.count) rygSavePreservedIds();

	orig_applyUpdates(self, _cmd, updates, completion, userAccess);

	if (!preserved.count) return;

	NSString *sid = preserved.anyObject;
	NSString *senderName = sid.length ? rygSenderNameMap()[sid] : nil;
	NSString *senderPk = sid.length ? rygSenderPkMap()[sid] : nil;

	if (!senderName.length && senderPk.length) {
		senderName = rygDirectUserResolverUsernameForPK(senderPk);
		if (senderName.length) rygTrackInMap(rygSenderNameMap(), sid, senderName, RYG_SENDER_MAP_MAX);
	}

	NSString *currentPk = rygCurrentUserPk();
	BOOL foreground = currentPk.length && [currentPk isEqualToString:ownerPk];
	BOOL toastOn = [RYGUtils getBoolPref:@"unsent_message_toast"];
	NSString *ownerName = foreground ? nil : rygOwnerUsernameFromApplicator(self);

	dispatch_async(dispatch_get_main_queue(), ^{
		if (foreground) rygRefreshVisibleCellIndicators();
		if (!toastOn) return;

		if (senderName.length) rygShowUnsentToast(senderName, ownerName);
		else rygShowUnsentToastNamingChat(sid.length ? rygThreadIdBySid[sid] : nil, ownerPk, ownerName);
	});
}

static void (*orig_removeMutationExecute)(id, SEL, id, id);
static void new_removeMutationExecute(id self, SEL _cmd, id handler, id pkg) {
	NSArray *keys = rygIvar(self, "_messageKeys");
	if ([keys isKindOfClass:NSArray.class] && keys.count) {
		rygTrackPendingLocalKeys(keys);
	}

	atomic_fetch_add(&rygLocalDeleteInProgress, 1);
	orig_removeMutationExecute(self, _cmd, handler, pkg);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		atomic_fetch_sub(&rygLocalDeleteInProgress, 1);
	});
}

static void (*orig_configureCell)(id, SEL, id, id, id);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
	orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);

	NSString *sid = rygCellServerId(self);
	if (sid.length) {
		SEL sel = NSSelectorFromString(@"messageMetadata");
		id meta = nil;

		if ([vm respondsToSelector:sel]) {
			@try { meta = ((id (*)(id, SEL))objc_msgSend)(vm, sel); }
			@catch (__unused id e) {}
		}

		NSString *pk = rygString(rygIvar(meta, "_senderPk"));
		if (pk.length) rygTrackInMap(rygSenderPkMap(), sid, pk, RYG_SENDER_MAP_MAX);
	}

	rygUpdateCellIndicator(self);
}

static void (*orig_cellLayoutSubviews)(id, SEL);
static void new_cellLayoutSubviews(id self, SEL _cmd) {
	orig_cellLayoutSubviews(self, _cmd);
	rygUpdateCellIndicator(self);
}

// IG paints the bubble in its own layout pass, after the cell's, so every repaint re-asserts.
static void rygReassertTint(UIView *view) {
	if (!objc_getAssociatedObject(view, kBubbleTintOrigKey)) return;
	rygTintSurface(view, rygTintColorForView(view));
}

static void (*orig_directGradientLayout)(id, SEL);
static void new_directGradientLayout(id self, SEL _cmd) {
	orig_directGradientLayout(self, _cmd);
	rygReassertTint(self);
}

static void (*orig_gradientLayout)(id, SEL);
static void new_gradientLayout(id self, SEL _cmd) {
	orig_gradientLayout(self, _cmd);
	rygReassertTint(self);
}

static void (*orig_bubbleLayout)(id, SEL);
static void new_bubbleLayout(id self, SEL _cmd) {
	orig_bubbleLayout(self, _cmd);

	UIView *bubble = self;
	UIColor *tint = rygTintColorForView(bubble);

	if (!tint) {
		if (objc_getAssociatedObject(bubble, kBubbleTintOrigKey)) rygTintBubble(bubble, nil);
		return;
	}

	rygTintBubble(bubble, rygHasNestedBubble(bubble) ? nil : tint);
}

static void (*orig_bubbleSetBg)(id, SEL, UIColor *);
static void new_bubbleSetBg(id self, SEL _cmd, UIColor *color) {
	orig_bubbleSetBg(self, _cmd, color);

	UIView *bubble = self;
	NSDictionary *orig = objc_getAssociatedObject(bubble, kBubbleTintOrigKey);
	if (!orig) return;

	NSMutableDictionary *updated = [orig mutableCopy];
	updated[@"bg"] = color ?: (id)NSNull.null;
	objc_setAssociatedObject(bubble, kBubbleTintOrigKey, updated, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	rygReassertTint(bubble);
}

static id (*orig_actionLogInit)(id, SEL, id, id, id, id, id, BOOL, BOOL, id);
static id new_actionLogInit(id self, SEL _cmd, id message, id title, id attrs, id parts, id type, BOOL collapsible, BOOL hidden, id genAI) {
	id result = orig_actionLogInit(self, _cmd, message, title, attrs, parts, type, collapsible, hidden, genAI);

	@try {
		SEL sel = @selector(messageId);
		if ([result respondsToSelector:sel]) {
			NSString *sid = rygString(((id (*)(id, SEL))objc_msgSend)(result, sel));
			if (sid.length) rygTrackInMap(rygContentClassMap(), sid, @"IGDirectThreadActionLog", RYG_CONTENT_MAP_MAX);
		}
	} @catch (__unused id e) {}

	return result;
}

static id (*orig_uiSetInit)(id, SEL, id, id, id, id);
static id new_uiSetInit(id self, SEL _cmd, id sorted, id bySid, id byContext, id newest) {
	if (rygKeepOn()) rygReinjectPreserved(rygKeptUICache(), NO, (NSArray **)&sorted, (NSDictionary **)&bySid);
	return orig_uiSetInit(self, _cmd, sorted, bySid, byContext, newest);
}

static id (*orig_pubSetInit)(id, SEL, id, id, id, BOOL);
static id new_pubSetInit(id self, SEL _cmd, id sorted, id bySid, id byContext, BOOL hasEB) {
	if (rygKeepOn()) {
		rygRememberPublishedMessages(bySid);
		if ([sorted isKindOfClass:NSArray.class] && [sorted count]) {
			[RYGKeptMessageStore mirrorMessages:bySid
									   threadId:rygMessageThreadId([sorted firstObject])
										ownerPK:rygCurrentUserPk()];
		}
		rygReinjectPreserved(rygKeptPublishedCache(), YES, (NSArray **)&sorted, (NSDictionary **)&bySid);
	}
	return orig_pubSetInit(self, _cmd, sorted, bySid, byContext, hasEB);
}

static id (*orig_removeItemUpdates)(id, SEL, id, id, id);
static id new_removeItemUpdates(id self, SEL _cmd, id threadId, id itemId, id sequenceId) {
	if (rygKeepOn()) rygRecoverMessage(rygString(itemId));
	return orig_removeItemUpdates(self, _cmd, threadId, itemId, sequenceId);
}

static void rygHook(Class cls, SEL sel, IMP imp, IMP *orig) {
	BOOL ok = cls && class_getInstanceMethod(cls, sel) != NULL;

	if (ok) MSHookMessageEx(cls, sel, imp, orig);
}

#pragma mark - Visual (view-once) on-open capture

static void (*orig_visualViewerDidAppear)(id, SEL, BOOL);
static void new_visualViewerDidAppear(id self, SEL _cmd, BOOL animated) {
	orig_visualViewerDidAppear(self, _cmd, animated);
	if (!rygLogOn()) return;

	@try {
		// viewer._dataSource._dataSource._currentMessage = IGDirectVisualMessage
		id ds = rygIvar(self, "_dataSource");
		id playlist = rygIvar(ds, "_dataSource");
		id vmsg = rygIvar(playlist, "_currentMessage") ?: rygIvar(self, "_initialVisualMessage");

		id attr = rygIvar(self, "_attributionDelegate");
		id meta = rygIvar(attr, "_contextIdentifier");

		rygDMCaptureVisualMessageOnOpen(vmsg, meta, rygCurrentUserPk());
	} @catch (__unused id e) {}
}

%ctor {
	rygHook(NSClassFromString(@"IGDirectCacheUpdatesApplicator"),
			NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:"),
			(IMP)new_applyUpdates,
			(IMP *)&orig_applyUpdates);

	rygHook(NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor"),
			NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:"),
			(IMP)new_removeMutationExecute,
			(IMP *)&orig_removeMutationExecute);

	Class cellCls = NSClassFromString(@"_TtC19IGDirectMessageCell19IGDirectMessageCell")
					?: NSClassFromString(@"IGDirectMessageCell");
	rygHook(cellCls,
			NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:"),
			(IMP)new_configureCell,
			(IMP *)&orig_configureCell);
	rygHook(cellCls,
			@selector(layoutSubviews),
			(IMP)new_cellLayoutSubviews,
			(IMP *)&orig_cellLayoutSubviews);

	rygTintEnabled = rygUnsentTintOn();

	if (rygTintEnabled) {
		rygHook(NSClassFromString(@"IGDirectMessageBubbleView"),
				@selector(layoutSubviews),
				(IMP)new_bubbleLayout,
				(IMP *)&orig_bubbleLayout);
		rygHook(NSClassFromString(@"IGDirectMessageBubbleView"),
				@selector(setBackgroundColor:),
				(IMP)new_bubbleSetBg,
				(IMP *)&orig_bubbleSetBg);
		rygHook(NSClassFromString(@"IGDirectGradientView"),
				@selector(layoutSubviews),
				(IMP)new_directGradientLayout,
				(IMP *)&orig_directGradientLayout);
		rygHook(NSClassFromString(@"IGGradientView"),
				@selector(layoutSubviews),
				(IMP)new_gradientLayout,
				(IMP *)&orig_gradientLayout);
	}

	rygHook(NSClassFromString(@"IGDirectThreadActionLog"),
			NSSelectorFromString(@"initWithMessage:title:textAttributes:textParts:actionLogType:collapsible:hidden:genAIMetadata:"),
			(IMP)new_actionLogInit,
			(IMP *)&orig_actionLogInit);

	rygHook(NSClassFromString(@"IGDirectVisualMessageViewerController"),
			@selector(viewDidAppear:),
			(IMP)new_visualViewerDidAppear,
			(IMP *)&orig_visualViewerDidAppear);

	rygHook(NSClassFromString(@"IGDThreadDeltaUpdateFactory"),
			NSSelectorFromString(@"removeItemUpdatesForThreadId:itemId:sequenceId:"),
			(IMP)new_removeItemUpdates,
			(IMP *)&orig_removeItemUpdates);

	rygHook(NSClassFromString(@"IGDirectUIMessageSet"),
			NSSelectorFromString(@"initWithSortedMessages:messagesByServerId:messagesByClientContext:newestPublishedMessage:"),
			(IMP)new_uiSetInit,
			(IMP *)&orig_uiSetInit);

	rygHook(NSClassFromString(@"IGDirectPublishedMessageSet"),
			NSSelectorFromString(@"initWithSortedMessages:messagesByServerId:messagesByClientContext:hasEBMessage:"),
			(IMP)new_pubSetInit,
			(IMP *)&orig_pubSetInit);

	if (!rygIndicatorOn()) {
		rygPreservedByPk = NSMutableDictionary.dictionary;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:RYG_PRESERVED_IDS_KEY];
		[NSUserDefaults.standardUserDefaults removeObjectForKey:RYG_PRESERVED_LEGACY_KEY];
	}
}