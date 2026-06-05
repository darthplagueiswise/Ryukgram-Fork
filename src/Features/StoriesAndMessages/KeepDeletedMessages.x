#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "SCIExcludedThreads.h"
#import "SCIDirectUserResolver.h"
#import "../DeletedMessages/SCIDeletedMessagesCapture.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <stdatomic.h>

#define SCI_SENDER_MAP_MAX			3000
#define SCI_CONTENT_MAP_MAX			2500
#define SCI_PRESERVED_MAX			200
#define SCI_PRESERVED_IDS_KEY		@"SCIPreservedMsgIdsByPk"
#define SCI_PRESERVED_LEGACY_KEY	@"SCIPreservedMsgIds"
#define SCI_PRESERVED_TAG			1399

static atomic_int sciLocalDeleteInProgress = 0;

static NSMutableDictionary<NSString *, NSDate *> *sciDeleteForYouKeys;
static NSMutableSet<NSString *> *sciPendingLocalSids;
static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sciPreservedByPk;
static NSMutableDictionary<NSString *, NSString *> *sciSenderPkBySid;
static NSMutableDictionary<NSString *, NSString *> *sciSenderNameBySid;
static NSMutableDictionary<NSString *, NSString *> *sciContentClassBySid;

static void sciUpdateCellIndicator(id cell);

#pragma mark - Prefs / runtime helpers

static inline BOOL sciKeepOn(void) { return [SCIUtils getBoolPref:@"keep_deleted_message"]; }
static inline BOOL sciLogOn(void) { return [SCIUtils getBoolPref:@"deleted_messages_log_enabled"]; }
static inline BOOL sciIndicatorOn(void) { return [SCIUtils getBoolPref:@"indicate_unsent_messages"]; }

static id sciIvar(id obj, const char *name) {
	if (!obj || !name) return nil;
	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;
		@try { return object_getIvar(obj, iv); }
		@catch (__unused id e) { return nil; }
	}
	return nil;
}

static void sciSetIvar(id obj, const char *name, id value) {
	if (!obj || !name) return;
	for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
		Ivar iv = class_getInstanceVariable(c, name);
		if (!iv) continue;
		@try { object_setIvar(obj, iv, value); } @catch (__unused id e) {}
		return;
	}
}

static long long sciIntIvar(id obj, const char *name, long long fallback) {
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

static id sciKVC(id obj, NSString *key) {
	if (!obj || !key.length) return nil;
	@try {
		id v = [obj valueForKey:key];
		return v == NSNull.null ? nil : v;
	} @catch (__unused id e) {
		return nil;
	}
}

static NSString *sciString(id v) {
	if ([v isKindOfClass:NSString.class]) return [(NSString *)v length] ? v : nil;
	if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
	return nil;
}

static NSString *sciFirstIvarString(id obj, NSArray<NSString *> *names) {
	for (NSString *n in names) {
		NSString *s = sciString(sciIvar(obj, n.UTF8String));
		if (s.length) return s;
	}
	return nil;
}

#pragma mark - Message ids / metadata

static NSString *sciServerIdFromKey(id key) {
	return sciFirstIvarString(key, @[@"_messageServerId", @"_serverId"]);
}

static NSString *sciServerIdFromMetadata(id meta) {
	NSString *sid = sciFirstIvarString(meta, @[@"_serverId", @"_messageServerId"]);
	return sid.length ? sid : sciServerIdFromKey(sciIvar(meta, "_key"));
}

static NSString *sciServerIdFromMessage(id message) {
	NSString *sid = sciServerIdFromMetadata(sciIvar(message, "_metadata"));
	return sid.length ? sid : sciServerIdFromMetadata(message);
}

static NSString *sciSenderPkFromMessage(id message) {
	id meta = sciIvar(message, "_metadata");
	NSString *pk = sciString(sciIvar(meta, "_senderPk"));
	return pk.length ? pk : sciString(sciIvar(message, "_senderPk"));
}

static NSString *sciCellServerId(id cell) {
	id vm = sciIvar(cell, "_viewModel");

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

	return sciServerIdFromMetadata(meta);
}

#pragma mark - Small stores

static void sciTrimMap(NSMutableDictionary *map, NSUInteger max) {
	if (map.count <= max) return;

	NSArray *keys = map.allKeys;
	NSUInteger drop = MAX((NSUInteger)1, keys.count / 10);
	for (NSUInteger i = 0; i < drop && i < keys.count; i++) {
		[map removeObjectForKey:keys[i]];
	}
}

static NSMutableDictionary<NSString *, NSString *> *sciSenderPkMap(void) {
	if (!sciSenderPkBySid) sciSenderPkBySid = NSMutableDictionary.dictionary;
	return sciSenderPkBySid;
}

static NSMutableDictionary<NSString *, NSString *> *sciSenderNameMap(void) {
	if (!sciSenderNameBySid) sciSenderNameBySid = NSMutableDictionary.dictionary;
	return sciSenderNameBySid;
}

static NSMutableDictionary<NSString *, NSString *> *sciContentClassMap(void) {
	if (!sciContentClassBySid) sciContentClassBySid = NSMutableDictionary.dictionary;
	return sciContentClassBySid;
}

static void sciTrackInMap(NSMutableDictionary<NSString *, NSString *> *map,
						  NSString *sid,
						  NSString *value,
						  NSUInteger max) {
	if (!sid.length || !value.length) return;
	map[sid] = value;
	sciTrimMap(map, max);
}

static NSMutableSet<NSString *> *sciPendingLocalSet(void) {
	if (!sciPendingLocalSids) sciPendingLocalSids = NSMutableSet.set;
	return sciPendingLocalSids;
}

static void sciTrackMessage(id message) {
	NSString *sid = sciServerIdFromMessage(message);
	if (!sid.length) return;

	NSString *pk = sciSenderPkFromMessage(message);
	if (pk.length) sciTrackInMap(sciSenderPkMap(), sid, pk, SCI_SENDER_MAP_MAX);

	sciTrackInMap(sciContentClassMap(), sid, NSStringFromClass([message class]), SCI_CONTENT_MAP_MAX);
}

static BOOL sciIsReactionOrActionLog(NSString *sid) {
	NSString *cls = sid.length ? sciContentClassMap()[sid] : nil;
	return [cls localizedCaseInsensitiveContainsString:@"reaction"] ||
		   [cls localizedCaseInsensitiveContainsString:@"actionlog"];
}

#pragma mark - Owner / preserved ids

static NSString *sciUserPK(id user) {
	return sciDirectUserResolverPKFromUser(user);
}

static NSString *sciOwnerPkFromApplicator(id applicator) {
	return sciUserPK(sciIvar(applicator, "_user"));
}

static NSString *sciUsernameFromUser(id user) {
	if (!user) return nil;

	id fc = sciIvar(user, "_fieldCache");
	if ([fc isKindOfClass:NSDictionary.class]) {
		NSString *u = sciString(fc[@"username"]);
		if (u.length) return u;
	}

	return sciString(sciKVC(user, @"username"));
}

static NSString *sciOwnerUsernameFromApplicator(id applicator) {
	return sciUsernameFromUser(sciIvar(applicator, "_user"));
}

static NSString *sciCurrentUserPk(void) {
	@try {
		for (UIWindow *w in UIApplication.sharedApplication.windows) {
			id session = sciKVC(w, @"userSession");
			NSString *pk = sciUserPK(sciKVC(session, @"user"));
			if (pk.length) return pk;
		}
	} @catch (__unused id e) {}
	return nil;
}

static NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *sciPreservedStore(void) {
	if (sciPreservedByPk) return sciPreservedByPk;

	sciPreservedByPk = NSMutableDictionary.dictionary;

	NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:SCI_PRESERVED_IDS_KEY];
	if ([saved isKindOfClass:NSDictionary.class]) {
		for (NSString *pk in saved) {
			NSArray *arr = [saved[pk] isKindOfClass:NSArray.class] ? saved[pk] : nil;
			if (arr.count) sciPreservedByPk[pk] = [NSMutableSet setWithArray:arr];
		}
	}

	NSArray *legacy = [NSUserDefaults.standardUserDefaults arrayForKey:SCI_PRESERVED_LEGACY_KEY];
	NSString *currentPk = legacy.count ? sciCurrentUserPk() : nil;
	if (legacy.count && currentPk.length) {
		NSMutableSet *bucket = sciPreservedByPk[currentPk] ?: NSMutableSet.set;
		[bucket addObjectsFromArray:legacy];
		sciPreservedByPk[currentPk] = bucket;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
	}

	return sciPreservedByPk;
}

static NSMutableSet<NSString *> *sciBucket(NSString *pk, BOOL create) {
	if (!pk.length) return nil;

	NSMutableDictionary *store = sciPreservedStore();
	NSMutableSet *bucket = store[pk];

	if (!bucket && create) {
		bucket = NSMutableSet.set;
		store[pk] = bucket;
	}
	return bucket;
}

NSMutableSet *sciGetPreservedIds(void) {
	NSString *pk = sciCurrentUserPk();
	return pk.length ? (sciBucket(pk, YES) ?: NSMutableSet.set) : NSMutableSet.set;
}

static void sciSavePreservedIds(void) {
	NSMutableDictionary *out = NSMutableDictionary.dictionary;

	for (NSString *pk in sciPreservedStore()) {
		NSMutableSet *set = sciPreservedByPk[pk];

		while (set.count > SCI_PRESERVED_MAX) {
			[set removeObject:set.anyObject];
		}

		if (set.count) out[pk] = set.allObjects;
	}

	NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
	if (out.count) [d setObject:out forKey:SCI_PRESERVED_IDS_KEY];
	else [d removeObjectForKey:SCI_PRESERVED_IDS_KEY];
}

void sciClearPreservedIds(void) {
	NSString *pk = sciCurrentUserPk();
	if (!pk.length) return;

	[sciPreservedStore() removeObjectForKey:pk];
	sciSavePreservedIds();
}

#pragma mark - Delete-for-you / local delete tracking

static void sciPruneDeleteForYouKeys(void) {
	if (!sciDeleteForYouKeys.count) return;

	NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-10.0];
	for (NSString *sid in sciDeleteForYouKeys.allKeys) {
		if ([sciDeleteForYouKeys[sid] compare:cutoff] == NSOrderedAscending) {
			[sciDeleteForYouKeys removeObjectForKey:sid];
		}
	}
}

static BOOL sciKeysIntersectSet(NSArray *keys, NSSet *set) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length && [set containsObject:sid]) return YES;
	}
	return NO;
}

static void sciRemoveKeysFromSet(NSArray *keys, NSMutableSet *set) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) [set removeObject:sid];
	}
}

static BOOL sciKeysMarkedDeleteForYou(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length && sciDeleteForYouKeys[sid]) return YES;
	}
	return NO;
}

static void sciRemoveDeleteForYouKeys(NSArray *keys) {
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) [sciDeleteForYouKeys removeObjectForKey:sid];
	}
}

static void sciTrackDeleteForYouKeys(NSArray *keys) {
	if (!sciDeleteForYouKeys) sciDeleteForYouKeys = NSMutableDictionary.dictionary;

	NSDate *now = NSDate.date;
	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) sciDeleteForYouKeys[sid] = now;
	}
}

static void sciTrackPendingLocalKeys(NSArray *keys) {
	NSMutableSet *pending = sciPendingLocalSet();

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (sid.length) [pending addObject:sid];
	}

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		sciRemoveKeysFromSet(keys, pending);
	});
}

#pragma mark - Update extraction

static void sciCaptureMessagesFromUpdate(id update, NSString *ownerPk, NSString *threadId) {
	NSSet *preserved = sciLogOn() ? sciGetPreservedIds() : nil;

	for (NSString *ivar in @[@"_insertMessages", @"_replaceMessages_messages"]) {
		NSArray *messages = sciIvar(update, ivar.UTF8String);
		if (![messages isKindOfClass:NSArray.class]) continue;

		for (id m in messages) {
			sciTrackMessage(m);
			sciDMCaptureNoteInsert(m);

			@try {
				if (preserved.count) {
					NSString *sid = sciServerIdFromMessage(m);
					if (sid.length && [preserved containsObject:sid]) {
						sciDMCaptureNotePreservedMessage(m, ownerPk, threadId);
					}
				}
			} @catch (__unused id e) {}
		}
	}
}

static void sciCaptureEditsFromUpdate(id update, NSString *ownerPk, NSString *threadId) {
	if (!sciLogOn()) return;

	NSString *sid = sciString(sciIvar(update, "_mutateMessage_messageId"));
	id mut = sciIvar(update, "_mutateMessage_contentMutation");
	if (sid.length && mut) {
		sciDMCaptureNoteEdit(sid, mut, ownerPk, threadId);
		sciDMCaptureNoteReaction(sid, mut, ownerPk, threadId);
	}

	NSArray *pairs = sciIvar(update, "_mutateMultipleMessages_contentMutations");
	if (![pairs isKindOfClass:NSArray.class]) return;

	for (id pair in pairs) {
		NSString *psid = sciString(sciIvar(pair, "_messageId")) ?: sciString(sciKVC(pair, @"messageId"));
		id pmut = sciIvar(pair, "_contentMutation") ?: sciKVC(pair, @"contentMutation");
		if (psid.length && pmut) {
			sciDMCaptureNoteEdit(psid, pmut, ownerPk, threadId);
			sciDMCaptureNoteReaction(psid, pmut, ownerPk, threadId);
		}
	}
}

static id sciMessageUpdateFromThreadUpdate(id threadUpdate) {
	return sciIvar(threadUpdate, "_messageUpdate") ?: sciKVC(threadUpdate, @"messageUpdate");
}

static NSString *sciThreadIdFromCacheUpdate(id cacheUpdate) {
	NSString *tid = sciString(sciKVC(cacheUpdate, @"threadId"));
	if (tid.length) return tid;

	tid = sciString(sciIvar(cacheUpdate, "_threadId"));
	if (tid.length) return tid;

	return sciString(sciIvar(sciIvar(cacheUpdate, "_threadUpdate"), "_removeThread_threadId"));
}

static NSArray *sciThreadUpdatesFromCacheUpdate(id cacheUpdate) {
	id updates = sciKVC(cacheUpdate, @"threadUpdates");
	if ([updates isKindOfClass:NSArray.class]) return updates;

	id single = sciIvar(cacheUpdate, "_threadUpdate");
	return single ? @[single] : @[];
}

#pragma mark - Processing

static BOOL sciProcessMessageUpdate(id update,
									NSString *ownerPk,
									NSString *threadId,
									id applicator,
									BOOL keepEnabled,
									BOOL logEnabled,
									NSMutableSet<NSString *> *preserved) {
	if (!update || !ownerPk.length) return NO;

	// Capture is best-effort and must never prevent the keep-deleted logic below from running.
	@try {
		sciCaptureMessagesFromUpdate(update, ownerPk, threadId);
		sciCaptureEditsFromUpdate(update, ownerPk, threadId);
	} @catch (__unused id e) {}

	NSArray *keys = sciIvar(update, "_removeMessages_messageKeys");
	if (![keys isKindOfClass:NSArray.class] || !keys.count) return NO;

	long long reason = sciIntIvar(update, "_removeMessages_reason", -1);

	if (reason == 2) {
		sciTrackDeleteForYouKeys(keys);
		return NO;
	}

	if (reason != 0) return NO;

	NSMutableSet *pending = sciPendingLocalSet();
	if (sciKeysIntersectSet(keys, pending)) {
		sciRemoveKeysFromSet(keys, pending);
		return NO;
	}

	if (atomic_load(&sciLocalDeleteInProgress) > 0) return NO;

	if (sciKeysMarkedDeleteForYou(keys)) {
		sciRemoveDeleteForYouKeys(keys);
		return NO;
	}

	NSMutableArray *unsendKeys = NSMutableArray.array;
	NSMutableSet *bucket = keepEnabled ? sciBucket(ownerPk, YES) : nil;

	for (id key in keys) {
		NSString *sid = sciServerIdFromKey(key);
		if (!sid.length || sciIsReactionOrActionLog(sid)) continue;

		NSString *senderPk = sciSenderPkMap()[sid];
		if (senderPk.length && [senderPk isEqualToString:ownerPk]) continue;

		[unsendKeys addObject:key];

		if (keepEnabled) {
			[bucket addObject:sid];
			[preserved addObject:sid];
		}
	}

	if (!unsendKeys.count) return NO;

	// Log capture only. This does not preserve the message bubble.
	if (logEnabled) sciDMCaptureNoteRemoveKeys(unsendKeys, applicator, ownerPk, threadId);

	// Only block IG's remove mutation when keep-deleted is enabled.
	if (keepEnabled) {
		sciSetIvar(update, "_removeMessages_messageKeys", nil);
		return YES;
	}

	return NO;
}

static NSSet<NSString *> *sciProcessCacheUpdate(id cacheUpdate, NSString *ownerPk, id applicator, BOOL keepEnabled, BOOL logEnabled) {
	NSMutableSet *preserved = NSMutableSet.set;
	NSString *threadId = sciThreadIdFromCacheUpdate(cacheUpdate);

	if (!cacheUpdate || !threadId.length || [SCIExcludedThreads shouldKeepDeletedBeBlockedForThreadId:threadId]) return preserved;

	if (!sciDeleteForYouKeys) sciDeleteForYouKeys = NSMutableDictionary.dictionary;
	sciPruneDeleteForYouKeys();

	for (id tu in sciThreadUpdatesFromCacheUpdate(cacheUpdate)) {
		id msgUpdate = sciMessageUpdateFromThreadUpdate(tu);
		if (msgUpdate) {
			sciProcessMessageUpdate(msgUpdate, ownerPk, threadId, applicator, keepEnabled, logEnabled, preserved);
		}
	}

	return preserved;
}

#pragma mark - Toast / indicator

static NSString *sciUnsentText(NSString *sender, NSString *deleter) {
	if (sender.length && deleter.length) {
		return [sender isEqualToString:deleter]
			? [NSString stringWithFormat:SCILocalized(@"%@ unsent a message"), sender]
			: [NSString stringWithFormat:SCILocalized(@"%@ unsent a message from %@"), deleter, sender];
	}
	if (sender.length) return [NSString stringWithFormat:SCILocalized(@"Message from %@ was unsent"), sender];
	if (deleter.length) return [NSString stringWithFormat:SCILocalized(@"%@ unsent a message"), deleter];
	return SCILocalized(@"A message was unsent");
}

static void sciShowUnsentToast(NSString *sender, NSString *ownerAccount) {
	NSString *body = sciUnsentText(sender, sender);
	SCINotify(SCI_NOTIF_UNSENT_MESSAGE,
			  ownerAccount.length ? ownerAccount : body,
			  ownerAccount.length ? body : nil,
			  @"trash.fill",
			  SCINotificationToneError);
}

static UIView *sciAccessoryWrapper(UIView *view) {
	for (UIView *cur = view; cur && cur.superview; cur = cur.superview) {
		CGSize s = cur.frame.size;
		if (s.width >= 32.0 && s.width <= 64.0 && fabs(s.width - s.height) < 6.0) return cur;
	}
	return view;
}

static void sciSetTrailingAccessoriesHidden(id cell, BOOL hidden) {
	NSArray *views = sciIvar(cell, "_tappableAccessoryViews");
	if (![views isKindOfClass:NSArray.class]) return;

	for (UIView *v in views) {
		if (![v isKindOfClass:UIView.class]) continue;

		UIView *wrap = sciAccessoryWrapper(v);
		wrap.hidden = hidden;
		if (wrap != v) v.hidden = hidden;
	}
}

static BOOL sciCellIsPreserved(id cell) {
	NSString *sid = sciCellServerId(cell);
	return sid.length && [sciGetPreservedIds() containsObject:sid];
}

static void sciUpdateCellIndicator(id cell) {
	if (![cell isKindOfClass:UIView.class]) return;

	UIView *view = cell;
	UIView *old = [view viewWithTag:SCI_PRESERVED_TAG];

	if (!sciIndicatorOn() || !sciCellIsPreserved(cell)) {
		if (old) [old removeFromSuperview];
		sciSetTrailingAccessoriesHidden(cell, NO);
		return;
	}

	sciSetTrailingAccessoriesHidden(cell, YES);
	if (old) return;

	UIView *parent = sciIvar(cell, "_messageContentContainerView") ?: view;

	UILabel *label = UILabel.new;
	label.tag = SCI_PRESERVED_TAG;
	label.text = SCILocalized(@"Unsent");
	label.font = [UIFont italicSystemFontOfSize:10.0];
	label.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[parent addSubview:label];

	[NSLayoutConstraint activateConstraints:@[
		[label.leadingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:4.0],
		[label.centerYAnchor constraintEqualToAnchor:parent.centerYAnchor],
	]];
}

static void sciRefreshVisibleCellIndicators(void) {
	if (!sciIndicatorOn()) return;

	Class cls = NSClassFromString(@"IGDirectMessageCell");
	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	if (!cls || !window) return;

	NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:window];

	while (stack.count) {
		UIView *v = stack.lastObject;
		[stack removeLastObject];

		if ([v isKindOfClass:cls]) {
			sciUpdateCellIndicator(v);
			continue;
		}

		for (UIView *sub in v.subviews) [stack addObject:sub];
	}
}

#pragma mark - Hooks

static void (*orig_applyUpdates)(id, SEL, id, id, id);
static void new_applyUpdates(id self, SEL _cmd, id updates, id completion, id userAccess) {
	sciDirectUserResolverSetActiveApplicator(self);

	BOOL keepEnabled = sciKeepOn();
	BOOL logEnabled = sciLogOn();

	if (!keepEnabled && !logEnabled) {
		orig_applyUpdates(self, _cmd, updates, completion, userAccess);
		return;
	}

	NSString *ownerPk = sciOwnerPkFromApplicator(self);
	NSMutableSet *preserved = NSMutableSet.set;

	if (ownerPk.length && [updates isKindOfClass:NSArray.class]) {
		for (id update in (NSArray *)updates) {
			NSSet *set = sciProcessCacheUpdate(update, ownerPk, self, keepEnabled, logEnabled);
			if (set.count) [preserved unionSet:set];
		}
	}

	if (preserved.count) sciSavePreservedIds();

	orig_applyUpdates(self, _cmd, updates, completion, userAccess);

	if (!preserved.count) return;

	NSString *sid = preserved.anyObject;
	NSString *senderName = sid.length ? sciSenderNameMap()[sid] : nil;
	NSString *senderPk = sid.length ? sciSenderPkMap()[sid] : nil;

	if (!senderName.length && senderPk.length) {
		senderName = sciDirectUserResolverUsernameForPK(senderPk);
		if (senderName.length) sciTrackInMap(sciSenderNameMap(), sid, senderName, SCI_SENDER_MAP_MAX);
	}

	NSString *currentPk = sciCurrentUserPk();
	BOOL foreground = currentPk.length && [currentPk isEqualToString:ownerPk];
	BOOL toastOn = [SCIUtils getBoolPref:@"unsent_message_toast"];
	NSString *ownerName = foreground ? nil : sciOwnerUsernameFromApplicator(self);

	dispatch_async(dispatch_get_main_queue(), ^{
		if (foreground) sciRefreshVisibleCellIndicators();
		if (toastOn) sciShowUnsentToast(senderName, ownerName);
	});
}

static void (*orig_removeMutationExecute)(id, SEL, id, id);
static void new_removeMutationExecute(id self, SEL _cmd, id handler, id pkg) {
	NSArray *keys = sciIvar(self, "_messageKeys");
	if ([keys isKindOfClass:NSArray.class] && keys.count) {
		sciTrackPendingLocalKeys(keys);
	}

	atomic_fetch_add(&sciLocalDeleteInProgress, 1);
	orig_removeMutationExecute(self, _cmd, handler, pkg);

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		atomic_fetch_sub(&sciLocalDeleteInProgress, 1);
	});
}

static void (*orig_configureCell)(id, SEL, id, id, id);
static void new_configureCell(id self, SEL _cmd, id vm, id ringSpec, id launcherSet) {
	orig_configureCell(self, _cmd, vm, ringSpec, launcherSet);

	NSString *sid = sciCellServerId(self);
	if (sid.length) {
		SEL sel = NSSelectorFromString(@"messageMetadata");
		id meta = nil;

		if ([vm respondsToSelector:sel]) {
			@try { meta = ((id (*)(id, SEL))objc_msgSend)(vm, sel); }
			@catch (__unused id e) {}
		}

		NSString *pk = sciString(sciIvar(meta, "_senderPk"));
		if (pk.length) sciTrackInMap(sciSenderPkMap(), sid, pk, SCI_SENDER_MAP_MAX);
	}

	sciUpdateCellIndicator(self);
}

static void (*orig_cellLayoutSubviews)(id, SEL);
static void new_cellLayoutSubviews(id self, SEL _cmd) {
	orig_cellLayoutSubviews(self, _cmd);
	if (sciIndicatorOn()) sciUpdateCellIndicator(self);
}

static id (*orig_actionLogInit)(id, SEL, id, id, id, id, id, BOOL, BOOL, id);
static id new_actionLogInit(id self, SEL _cmd, id message, id title, id attrs, id parts, id type, BOOL collapsible, BOOL hidden, id genAI) {
	id result = orig_actionLogInit(self, _cmd, message, title, attrs, parts, type, collapsible, hidden, genAI);

	@try {
		SEL sel = @selector(messageId);
		if ([result respondsToSelector:sel]) {
			NSString *sid = sciString(((id (*)(id, SEL))objc_msgSend)(result, sel));
			if (sid.length) sciTrackInMap(sciContentClassMap(), sid, @"IGDirectThreadActionLog", SCI_CONTENT_MAP_MAX);
		}
	} @catch (__unused id e) {}

	return result;
}

static void sciHook(Class cls, SEL sel, IMP imp, IMP *orig) {
	if (cls && class_getInstanceMethod(cls, sel)) {
		MSHookMessageEx(cls, sel, imp, orig);
	}
}

#pragma mark - Visual (view-once) on-open capture

static void (*orig_visualViewerDidAppear)(id, SEL, BOOL);
static void new_visualViewerDidAppear(id self, SEL _cmd, BOOL animated) {
	orig_visualViewerDidAppear(self, _cmd, animated);
	if (!sciLogOn()) return;

	@try {
		// viewer._dataSource._dataSource._currentMessage = IGDirectVisualMessage
		id ds = sciIvar(self, "_dataSource");
		id playlist = sciIvar(ds, "_dataSource");
		id vmsg = sciIvar(playlist, "_currentMessage") ?: sciIvar(self, "_initialVisualMessage");

		id attr = sciIvar(self, "_attributionDelegate");
		id meta = sciIvar(attr, "_contextIdentifier");

		sciDMCaptureVisualMessageOnOpen(vmsg, meta, sciCurrentUserPk());
	} @catch (__unused id e) {}
}

%ctor {
	sciHook(NSClassFromString(@"IGDirectCacheUpdatesApplicator"),
			NSSelectorFromString(@"_applyThreadUpdates:completion:userAccess:"),
			(IMP)new_applyUpdates,
			(IMP *)&orig_applyUpdates);

	sciHook(NSClassFromString(@"IGDirectMessageOutgoingUpdateRemoveMessagesMutationProcessor"),
			NSSelectorFromString(@"executeWithResultHandler:accessoryPackage:"),
			(IMP)new_removeMutationExecute,
			(IMP *)&orig_removeMutationExecute);

	Class cellCls = NSClassFromString(@"IGDirectMessageCell");
	sciHook(cellCls,
			NSSelectorFromString(@"configureWithViewModel:ringViewSpecFactory:launcherSet:"),
			(IMP)new_configureCell,
			(IMP *)&orig_configureCell);
	sciHook(cellCls,
			@selector(layoutSubviews),
			(IMP)new_cellLayoutSubviews,
			(IMP *)&orig_cellLayoutSubviews);

	sciHook(NSClassFromString(@"IGDirectThreadActionLog"),
			NSSelectorFromString(@"initWithMessage:title:textAttributes:textParts:actionLogType:collapsible:hidden:genAIMetadata:"),
			(IMP)new_actionLogInit,
			(IMP *)&orig_actionLogInit);

	sciHook(NSClassFromString(@"IGDirectVisualMessageViewerController"),
			@selector(viewDidAppear:),
			(IMP)new_visualViewerDidAppear,
			(IMP *)&orig_visualViewerDidAppear);

	if (!sciIndicatorOn()) {
		sciPreservedByPk = NSMutableDictionary.dictionary;
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_IDS_KEY];
		[NSUserDefaults.standardUserDefaults removeObjectForKey:SCI_PRESERVED_LEGACY_KEY];
	}
}