// Local-only DM seen: doctors the viewer's watermark entry at the metadata getter so
// opened chats render read on-device while the server receipt stays blocked.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "RYGExcludedThreads.h"
#import "RYGDMLocalSeen.h"
#import "../../Utils.h"

static NSString *lsStr(id v) {
	if (!v) return nil;
	if ([v isKindOfClass:NSString.class]) return v;
	if ([v isKindOfClass:NSNumber.class]) return [v stringValue];
	return [v description];
}
static id lsCall(id o, SEL s) {
	if (!o || ![o respondsToSelector:s]) return nil;
	return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
static double lsTs(id dateObj) { return [dateObj isKindOfClass:NSDate.class] ? [(NSDate *)dateObj timeIntervalSince1970] : 0; }

static const void *kLSTidKey = &kLSTidKey;
static const void *kLSViewerKey = &kLSViewerKey;
static const void *kLSScanKey = &kLSScanKey;
static const void *kLSOursKey = &kLSOursKey;
static const void *kLSDoctoredKey = &kLSDoctoredKey;

static inline BOOL lsEnabled(void) {
	return [RYGUtils getBoolPref:@"remove_lastseen"] && [RYGUtils getBoolPref:@"dm_local_seen"];
}

static BOOL lsIsActiveForViewer(NSString *tid, NSString *viewer) {
	if (!tid.length || ![[RYGExcludedThreads activeThreadId] isEqualToString:tid]) return NO;

	NSString *activePK = [RYGExcludedThreads activeViewerPK];
	if (!activePK.length || !viewer.length) return YES;
	return [activePK isEqualToString:viewer];
}

static NSDictionary *lsScanThread(id thread, NSString *viewer) {
	id set = lsCall(thread, @selector(publishedMessagesInCurrentThreadRange));
	if (!set) return nil;

	NSDictionary *cached = objc_getAssociatedObject(thread, kLSScanKey);
	if (cached && [cached[@"setPtr"] unsignedLongValue] == (unsigned long)(__bridge void *)set) return cached;

	double newestIn = 0, newestAny = 0;
	NSString *newestInSid = nil, *newestAnySid = nil;

	id seq = [set respondsToSelector:@selector(objectEnumerator)] ? set
		   : (lsCall(set, @selector(allMessages)) ?: lsCall(set, @selector(messages)) ?: lsCall(set, @selector(array)));
	if ([seq respondsToSelector:@selector(objectEnumerator)]) {
		NSArray *snapshot = [seq respondsToSelector:@selector(allObjects)] ? [seq allObjects] : ([seq isKindOfClass:NSArray.class] ? [(NSArray *)seq copy] : nil);
		for (id m in (snapshot ?: seq)) {
			id md = lsCall(m, @selector(metadata));
			NSString *sid = lsStr(lsCall(md, @selector(serverId)));
			NSString *sender = lsStr(lsCall(md, @selector(senderPk)));
			double ts = lsTs(lsCall(md, @selector(serverTimestamp)));
			if (!sid.length || ts <= 0) continue;
			if (ts > newestAny) { newestAny = ts; newestAnySid = sid; }
			if (![sender isEqualToString:viewer] && ts > newestIn) { newestIn = ts; newestInSid = sid; }
		}
	}

	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	out[@"setPtr"] = @((unsigned long)(__bridge void *)set);
	out[@"inTs"] = @(newestIn);
	out[@"anyTs"] = @(newestAny);
	if (newestInSid) out[@"inSid"] = newestInSid;
	if (newestAnySid) out[@"anySid"] = newestAnySid;

	objc_setAssociatedObject(thread, kLSScanKey, out, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return out;
}

static NSDictionary *lsHonestDict(id meta) {
	Ivar iv = class_getInstanceVariable([meta class], "_lastSeenMessageIdsForUserIds");
	id d = iv ? object_getIvar(meta, iv) : nil;
	return [d isKindOfClass:NSDictionary.class] ? d : nil;
}

static id lsMakeFakeInfo(id templateInfo, NSString *sid, double ts) {
	Class cls = templateInfo ? [templateInfo class] : NSClassFromString(@"IGDirectLastSeenMessageInfo");
	if (!cls) return nil;

	id info = [[cls alloc] init];
	if (!info) return nil;

	@try {
		[info setValue:sid forKey:@"messageId"];
		[info setValue:[NSDate dateWithTimeIntervalSince1970:ts] forKey:@"sentTimestamp"];
		[info setValue:[NSDate date] forKey:@"seenAtTimestamp"];
	} @catch (__unused id e) {
		return nil;
	}

	objc_setAssociatedObject(info, kLSOursKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return info;
}

// The loaded message window lags the inbox row on threads we never opened.
static double lsNewestActivityTs(id thread) {
	Ivar iv = class_getInstanceVariable([thread class], "_latestMessageEligibleForInboxSnippet");
	id snippet = iv ? object_getIvar(thread, iv) : nil;
	double ts = lsTs(lsCall(lsCall(snippet, @selector(metadata)), @selector(serverTimestamp)));
	if (ts > 0) return ts;
	return lsTs(lsCall(thread, @selector(primarySortingDate)));
}

%hook IGDirectPublishedThread

- (BOOL)isUnread {
	BOOL orig = %orig;
	@try {
		if (!orig || !lsEnabled()) return orig;

		NSString *tid = lsStr(lsCall(self, @selector(threadId)));
		NSString *viewer = lsStr(lsCall(self, @selector(viewerId)));
		if (!tid.length) return orig;

		double activity = lsNewestActivityTs(self);
		if (activity <= 0) return orig;

		if (lsIsActiveForViewer(tid, viewer)) [RYGDMLocalSeen recordThreadId:tid coveredTs:activity pk:viewer];

		double localSeen = [RYGDMLocalSeen localSeenTsForThreadId:tid pk:viewer];
		if (localSeen <= 0 || activity > localSeen + 1.0) return orig;

		return NO;
	} @catch (__unused id e) {}
	return orig;
}

- (id)metadata {
	id meta = %orig;
	@try {
		if (meta && lsEnabled()) {
			NSString *tid = lsStr(lsCall(self, @selector(threadId)));
			NSString *viewer = lsStr(lsCall(self, @selector(viewerId)));
			if (tid.length) objc_setAssociatedObject(meta, kLSTidKey, tid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			if (viewer.length) objc_setAssociatedObject(meta, kLSViewerKey, viewer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

			if (lsIsActiveForViewer(tid, viewer)) {
				double activity = lsNewestActivityTs(self);
				if (activity > 0) [RYGDMLocalSeen recordThreadId:tid coveredTs:activity pk:viewer];
			}

			if (tid.length && viewer.length && [RYGDMLocalSeen localSeenTsForThreadId:tid pk:viewer] > 0) {
				NSDictionary *scan = lsScanThread(self, viewer);
				if (scan) objc_setAssociatedObject(meta, kLSScanKey, scan, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			}
		}
	} @catch (__unused id e) {}
	return meta;
}

%end

%hook IGDirectThreadMetadata

- (NSDictionary *)lastSeenMessageIdsForUserIds {
	NSDictionary *orig = %orig;
	@try {
		if (!lsEnabled()) return orig;

		NSString *tid = objc_getAssociatedObject(self, kLSTidKey);
		NSString *viewer = objc_getAssociatedObject(self, kLSViewerKey);
		NSDictionary *scan = objc_getAssociatedObject(self, kLSScanKey);
		if (!tid.length || !viewer.length || !scan) return orig;

		double localSeen = [RYGDMLocalSeen localSeenTsForThreadId:tid pk:viewer];
		if (localSeen <= 0) return orig;

		double newestIn = [scan[@"inTs"] doubleValue];
		double newestAny = [scan[@"anyTs"] doubleValue];
		NSString *anySid = scan[@"anySid"];

		if (newestIn <= 0 || !anySid.length) return orig;
		if (newestIn > localSeen + 1.0) return orig;

		id ownInfo = orig[viewer];
		double ownTs = lsTs(lsCall(ownInfo, @selector(sentTimestamp)));
		if (ownTs + 1.0 >= newestAny) return orig;

		NSDictionary *cached = objc_getAssociatedObject(self, kLSDoctoredKey);
		if (cached && [lsStr(lsCall(cached[viewer], @selector(messageId))) isEqualToString:anySid]) return cached;

		id fake = lsMakeFakeInfo(ownInfo, anySid, newestAny);
		if (!fake) return orig;

		NSMutableDictionary *doctored = [(orig ?: @{}) mutableCopy];
		doctored[viewer] = fake;
		NSDictionary *result = [doctored copy];
		objc_setAssociatedObject(self, kLSDoctoredKey, result, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return result;
	} @catch (__unused id e) {}
	return orig;
}

%end

static void lsObserveThread(id thread) {
	@try {
		if (!thread) return;
		NSString *tid = lsStr(lsCall(thread, @selector(threadId)));
		NSString *viewer = lsStr(lsCall(thread, @selector(viewerId)));
		if (!tid.length || !viewer.length) return;

		NSDictionary *scan = lsScanThread(thread, viewer);
		double newestIn = [scan[@"inTs"] doubleValue];
		double newestAny = [scan[@"anyTs"] doubleValue];

		if (newestIn > 0) [RYGDMLocalSeen noteNewestIncomingTs:newestIn forThreadId:tid pk:viewer];

		id meta = lsCall(thread, @selector(metadata));
		NSDictionary *honest = lsHonestDict(meta);
		id myInfo = honest[viewer];
		BOOL ours = myInfo && [objc_getAssociatedObject(myInfo, kLSOursKey) boolValue];
		double mySentTs = lsTs(lsCall(myInfo, @selector(sentTimestamp)));

		if (!ours && mySentTs > 0) [RYGDMLocalSeen seedServerSeenThreadId:tid ts:mySentTs pk:viewer];

		double activity = MAX(newestAny, lsNewestActivityTs(thread));
		if (lsEnabled() && activity > 0 && lsIsActiveForViewer(tid, viewer)) {
			[RYGDMLocalSeen recordThreadId:tid coveredTs:activity pk:viewer];
		}
	} @catch (__unused id e) {}
}

%hook IGDirectCacheUpdatesApplicator

- (void)_applyThreadUpdates:(id)updates completion:(id)completion userAccess:(id)access {
	%orig;
	if (!lsEnabled()) return;
	@try {
		Ivar civ = class_getInstanceVariable(object_getClass(self), "_cache");
		id cache = civ ? object_getIvar(self, civ) : nil;
		SEL fetch = NSSelectorFromString(@"fetchThreadWithThreadId:completion:");
		if (!cache || ![cache respondsToSelector:fetch]) return;

		NSArray *arr = [updates isKindOfClass:NSArray.class] ? updates : @[updates];
		NSMutableArray *tids = [NSMutableArray array];
		for (id u in arr) {
			NSString *tid = lsStr(lsCall(u, @selector(threadId)));
			if (tid && ![tids containsObject:tid]) [tids addObject:tid];
		}
		if (!tids.count) return;

		dispatch_async(dispatch_get_main_queue(), ^{
			@try {
				for (NSString *tid in tids) {
					void (^cb)(id) = ^(id thread) { dispatch_async(dispatch_get_main_queue(), ^{ lsObserveThread(thread); }); };
					cb = [cb copy];
					((void (*)(id, SEL, id, id))objc_msgSend)(cache, fetch, tid, cb);
				}
			} @catch (__unused id e) {}
		});
	} @catch (__unused id e) {}
}

%end
