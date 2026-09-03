#import "RYGFollowRequestTracker.h"
#import "../../InstagramHeaders.h"
#import <UIKit/UIKit.h>
#import "RYGFollowRequestStorage.h"
#import "RYGFollowRequestModels.h"
#import "RYGFollowRequestsViewController.h"
#import "../../Utils.h"
#import "../../Networking/RYGInstagramAPI.h"
#import "../../Localization/RYGLocalization.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import "../../Background/RYGBackgroundActivity.h"
#import <objc/runtime.h>

// IG throttles /friendships/ — small batches with a cushion between them.
static const NSInteger kBatchCap = 50;
static const NSTimeInterval kBatchDelay = 1.5;
static const NSTimeInterval kMinCheckThrottle = 45;
static const NSTimeInterval kConfirmDelay = 2.0;
// IG can briefly report no outgoing request right after sending — don't mark a
// fresh request Rejected within this window (Accepted via following=YES is exact).
static const NSTimeInterval kRejectGrace = 60;

static id rygFieldCacheValue(id obj, NSString *key) {
	if (!obj || !key) return nil;
	Ivar fc = NULL;
	for (Class c = [obj class]; c && !fc; c = class_getSuperclass(c)) fc = class_getInstanceVariable(c, "_fieldCache");
	if (!fc) return nil;
	NSDictionary *dict = object_getIvar(obj, fc);
	if (![dict isKindOfClass:NSDictionary.class]) return nil;
	id v = dict[key];
	return (!v || [v isKindOfClass:NSNull.class]) ? nil : v;
}

static NSString *rygStr(id v) {
	if ([v isKindOfClass:NSString.class]) return v;
	if ([v respondsToSelector:@selector(stringValue)]) return [v stringValue];
	return nil;
}

static BOOL rygBoxedBool(id v) {
	if (!v || v == (id)NSNull.null) return NO;
	return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

// friendship_status is an IGAPIRelationshipInfoDict with a -following getter.
static BOOL rygAlreadyFollowing(id igUser) {
	id fs = rygFieldCacheValue(igUser, @"friendship_status");
	if (fs && [fs respondsToSelector:@selector(following)]) return rygBoxedBool([fs following]);
	return NO;
}

@interface RYGFollowRequestTracker ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL isChecking;
@property (nonatomic, strong) NSDate *lastCheckDate;
@end

@implementation RYGFollowRequestTracker

+ (instancetype)shared {
	static RYGFollowRequestTracker *s; static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [self new]; });
	return s;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(appBecameActive)
												   name:UIApplicationDidBecomeActiveNotification object:nil];
	}
	return self;
}

#pragma mark - Prefs

- (BOOL)enabled { return [RYGUtils getBoolPref:@"follow_requests_enabled"]; }
- (BOOL)trackOutgoing { return [RYGUtils getBoolPref:@"follow_requests_track_outgoing"]; }
- (BOOL)trackIncoming { return [RYGUtils getBoolPref:@"follow_requests_track_incoming"]; }

- (NSTimeInterval)checkInterval {
	NSString *v = [RYGUtils getStringPref:@"follow_requests_check_interval"];
	return v.length ? v.doubleValue : 0;
}

#pragma mark - Lifecycle

- (void)appBecameActive {
	[self refreshFromPrefs];
	[self checkNowForced:NO completion:nil];
}

- (void)refreshFromPrefs {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.timer invalidate];
		self.timer = nil;
		if (![self enabled]) return;
		NSTimeInterval interval = [self checkInterval];
		if (interval <= 0) return; // event-driven only (foreground / list open / manual)
		self.timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self
													selector:@selector(timerFired) userInfo:nil repeats:YES];
	});
}

- (void)timerFired { [self checkNowForced:NO completion:nil]; }

#pragma mark - Capture: outgoing (you → them)

- (void)captureFollowForUser:(id)igUser {
	if (![self enabled] || ![self trackOutgoing] || !igUser) return;
	NSString *pk = rygStr(rygFieldCacheValue(igUser, @"strong_id__")) ?: rygStr(rygFieldCacheValue(igUser, @"pk"));
	if (!pk.length) return;
	NSString *username = rygStr(rygFieldCacheValue(igUser, @"username"));
	NSString *fullName = rygStr(rygFieldCacheValue(igUser, @"full_name"));
	NSString *picURL = rygStr(rygFieldCacheValue(igUser, @"profile_pic_url"));
	NSString *picID = rygStr(rygFieldCacheValue(igUser, @"profile_pic_id"));
	id privVal = rygFieldCacheValue(igUser, @"is_private");
	NSString *owner = [RYGUtils currentUserPK] ?: @"anon";

	// Tapping "Following" on an account you already follow fires this same hook — not a new request.
	if (rygAlreadyFollowing(igUser)) return;

	// Private → pending request; public follows instantly and isn't a request.
	// Privacy unknown → confirm via one API call.
	if (privVal != nil) {
		if ([privVal boolValue]) [self recordSentPK:pk username:username fullName:fullName picURL:picURL picID:picID isPrivate:YES owner:owner];
	} else {
		[self confirmAndRecordPK:pk username:username fullName:fullName picURL:picURL picID:picID owner:owner];
	}
}

- (void)recordSentPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID isPrivate:(BOOL)isPrivate owner:(NSString *)owner {
	if ([RYGFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner]) return;
	RYGFollowRequest *r = [RYGFollowRequest new];
	r.userPK = pk; r.username = username; r.fullName = fullName;
	r.profilePicURL = picURL; r.profilePicID = picID; r.isPrivate = isPrivate;
	r.type = RYGFollowRequestTypeSent;
	[RYGFollowRequestStorage recordRequest:r forOwnerPK:owner];
}

- (void)recordManualFollowForPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID {
	if (![self enabled] || ![self trackOutgoing] || !pk.length) return;
	[self confirmAndRecordPK:pk username:username fullName:fullName picURL:picURL picID:picID owner:([RYGUtils currentUserPK] ?: @"anon")];
}

// Confirm a tapped follow actually became a pending request before recording it.
- (void)confirmAndRecordPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID owner:(NSString *)owner {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kConfirmDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[RYGInstagramAPI fetchFriendshipStatusesForPKs:@[pk] completion:^(NSDictionary *statuses, NSError *error) {
			NSDictionary *st = statuses[pk];
			if (![st[@"outgoing_request"] boolValue] || [st[@"following"] boolValue]) return;
			[self recordSentPK:pk username:username fullName:fullName picURL:picURL picID:picID isPrivate:[st[@"is_private"] boolValue] owner:owner];
		}];
	});
}

- (void)captureCancelForUser:(id)igUser {
	if (![self enabled] || ![self trackOutgoing] || !igUser) return;
	NSString *pk = rygStr(rygFieldCacheValue(igUser, @"strong_id__")) ?: rygStr(rygFieldCacheValue(igUser, @"pk"));
	if (!pk.length) return;
	NSString *owner = [RYGUtils currentUserPK] ?: @"anon";
	// Only a pending request can be cancelled; unfollowing an accepted account isn't one.
	if ([RYGFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner])
		[RYGFollowRequestStorage resolveTargetPK:pk fromType:RYGFollowRequestTypeSent toType:RYGFollowRequestTypeCancelled ownerPK:owner];
}

#pragma mark - Capture: incoming (them → you)

- (void)captureIgnoreIncomingPK:(NSString *)pk {
	if (![self enabled] || ![self trackIncoming] || !pk.length) return;
	NSString *owner = [RYGUtils currentUserPK] ?: @"anon";
	[RYGFollowRequestStorage markIgnoredPK:pk ownerPK:owner];
	[RYGFollowRequestStorage resolveTargetPK:pk fromType:RYGFollowRequestTypeReceived toType:RYGFollowRequestTypeIgnored ownerPK:owner];
}

#pragma mark - Poll (both directions)

- (void)checkNowWithCompletion:(void (^)(void))completion {
	[self checkNowForced:YES completion:^(NSInteger changed) { if (completion) completion(); }];
}

- (void)checkNowForced:(BOOL)force completion:(void (^)(NSInteger changed))completion {
	if (![self enabled] || self.isChecking) { if (completion) completion(0); return; }
	if (!force && self.lastCheckDate && -[self.lastCheckDate timeIntervalSinceNow] < kMinCheckThrottle) {
		if (completion) completion(0);
		return;
	}
	NSString *owner = [RYGUtils currentUserPK];
	if (!owner.length) { if (completion) completion(0); return; }

	self.lastCheckDate = [NSDate date];
	self.isChecking = YES;
	// Keep the poll alive if the app is backgrounded mid-check (batches are spaced apart).
	[RYGBackgroundActivity setSource:@"follow_requests" active:YES];
	__block NSInteger total = 0;
	dispatch_group_t g = dispatch_group_create();
	if ([self trackOutgoing]) {
		dispatch_group_enter(g);
		[self runOutgoingForOwner:owner completion:^(NSInteger c) { total += c; dispatch_group_leave(g); }];
	}
	if ([self trackIncoming]) {
		dispatch_group_enter(g);
		[self runIncomingForOwner:owner completion:^(NSInteger c) { total += c; dispatch_group_leave(g); }];
	}
	dispatch_group_notify(g, dispatch_get_main_queue(), ^{
		self.isChecking = NO;
		[RYGBackgroundActivity setSource:@"follow_requests" active:NO];
		if (completion) completion(total);
	});
}

#pragma mark - Outgoing engine

- (void)runOutgoingForOwner:(NSString *)owner completion:(void (^)(NSInteger))completion {
	NSArray<NSString *> *pending = [RYGFollowRequestStorage pendingTargetPKsForOwnerPK:owner];
	if (!pending.count) { completion(0); return; } // no calls when nothing is pending
	NSMutableArray<NSArray *> *batches = [NSMutableArray array];
	for (NSUInteger i = 0; i < pending.count; i += kBatchCap)
		[batches addObject:[pending subarrayWithRange:NSMakeRange(i, MIN(kBatchCap, pending.count - i))]];
	__block NSInteger changed = 0;
	[self runOutgoingBatches:batches index:0 owner:owner changed:&changed completion:completion];
}

- (void)runOutgoingBatches:(NSArray<NSArray *> *)batches index:(NSUInteger)idx owner:(NSString *)owner changed:(NSInteger *)changedPtr completion:(void (^)(NSInteger))completion {
	if (idx >= batches.count) { completion(*changedPtr); return; }
	NSInteger *cp = changedPtr;
	[RYGInstagramAPI fetchFriendshipStatusesForPKs:batches[idx] completion:^(NSDictionary *statuses, NSError *error) {
		for (NSString *pk in batches[idx]) {
			NSDictionary *st = statuses[pk];
			if (![st isKindOfClass:NSDictionary.class]) continue;
			if ([st[@"following"] boolValue]) { if ([self resolveOutgoingPK:pk type:RYGFollowRequestTypeAccepted owner:owner]) (*cp)++; }
			else if (![st[@"outgoing_request"] boolValue]) { if ([self resolveOutgoingPK:pk type:RYGFollowRequestTypeRejected owner:owner]) (*cp)++; }
		}
		NSUInteger next = idx + 1;
		if (next < batches.count)
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBatchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self runOutgoingBatches:batches index:next owner:owner changed:cp completion:completion];
			});
		else completion(*cp);
	}];
}

- (BOOL)resolveOutgoingPK:(NSString *)pk type:(RYGFollowRequestType)type owner:(NSString *)owner {
	if (type == RYGFollowRequestTypeRejected) {
		RYGFollowRequest *p = [RYGFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner];
		if (p && [NSDate date].timeIntervalSince1970 - p.sentAt < kRejectGrace) return NO;
	}
	RYGFollowRequest *r = [RYGFollowRequestStorage resolveTargetPK:pk fromType:RYGFollowRequestTypeSent toType:type ownerPK:owner];
	if (!r) return NO;
	BOOL accepted = (type == RYGFollowRequestTypeAccepted);
	BOOL notify = accepted ? [RYGUtils getBoolPref:@"follow_requests_notify_accepted"] : [RYGUtils getBoolPref:@"follow_requests_notify_rejected"];
	if (notify) {
		NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
		[self notify:accepted ? RYG_NOTIF_FOLLOW_REQ_ACCEPTED : RYG_NOTIF_FOLLOW_REQ_REJECTED
			   title:accepted ? RYGLocalized(@"Follow request accepted") : RYGLocalized(@"Follow request declined")
			subtitle:accepted ? [NSString stringWithFormat:RYGLocalized(@"%@ accepted your request"), handle]
							   : [NSString stringWithFormat:RYGLocalized(@"%@ is no longer pending"), handle]
			   scope:RYGFollowRequestDirectionOutgoing success:accepted];
	}
	return YES;
}

#pragma mark - Incoming engine

- (void)runIncomingForOwner:(NSString *)owner completion:(void (^)(NSInteger))completion {
	[RYGInstagramAPI fetchPendingFollowRequestsWithCompletion:^(NSArray<NSDictionary *> *users, NSError *error) {
		if (error) { completion(0); return; }
		BOOL seeded = [RYGFollowRequestStorage incomingSeededForOwnerPK:owner];
		NSDictionary<NSString *, NSNumber *> *old = [RYGFollowRequestStorage incomingSnapshotForOwnerPK:owner];
		NSMutableDictionary<NSString *, NSNumber *> *snap = [NSMutableDictionary dictionary];
		NSMutableSet *currentPKs = [NSMutableSet set];
		NSTimeInterval now = [NSDate date].timeIntervalSince1970;
		NSInteger changed = 0;

		for (NSDictionary *u in users) {
			NSString *pk = rygStr(u[@"pk"]) ?: rygStr(u[@"pk_id"]) ?: rygStr(u[@"id"]);
			if (!pk.length) continue;
			[currentPKs addObject:pk];
			snap[pk] = old[pk] ?: @(now);
			if (old[pk] != nil) continue;

			// Resolved record (often a mis-classified Withdrawn) back in the live inbox — restore, don't dup.
			if ([RYGFollowRequestStorage restoreIncomingToReceivedForTargetPK:pk ownerPK:owner]) { changed++; continue; }

			RYGFollowRequest *r = [RYGFollowRequest new];
			r.userPK = pk;
			r.username = rygStr(u[@"username"]);
			r.fullName = rygStr(u[@"full_name"]);
			r.profilePicURL = rygStr(u[@"profile_pic_url"]);
			r.profilePicID = rygStr(u[@"profile_pic_id"]);
			r.isPrivate = [u[@"is_private"] boolValue];
			r.type = RYGFollowRequestTypeReceived;
			[RYGFollowRequestStorage recordRequest:r forOwnerPK:owner];
			changed++;
			// Seeding pass records existing requests silently; only later arrivals notify.
			if (seeded && [RYGUtils getBoolPref:@"follow_requests_notify_received"]) {
				NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
				[self notify:RYG_NOTIF_FOLLOW_REQ_RECEIVED title:RYGLocalized(@"New follow request")
					subtitle:[NSString stringWithFormat:RYGLocalized(@"%@ asked to follow you"), handle]
					   scope:RYGFollowRequestDirectionIncoming success:NO];
			}
		}

		NSMutableArray *vanished = [NSMutableArray array];
		for (NSString *pk in old) if (![currentPKs containsObject:pk]) [vanished addObject:pk];

		if (!seeded) [RYGFollowRequestStorage setIncomingSeededForOwnerPK:owner];

		if (!vanished.count) {
			[RYGFollowRequestStorage setIncomingSnapshot:snap forOwnerPK:owner];
			completion(changed);
			return;
		}
		// Verify each vanished pk before classifying — a partial list must not mass-withdraw.
		[self resolveVanishedIncoming:vanished owner:owner snapshot:snap oldTimestamps:old baseChanged:changed completion:completion];
	}];
}

// A vanished incoming pk was approved/ignored/withdrawn, or is still pending and fell off a partial list.
// Only /friendships/show/ carries incoming_request/followed_by to tell them apart (show_many drops them).
- (void)resolveVanishedIncoming:(NSArray<NSString *> *)vanished owner:(NSString *)owner snapshot:(NSMutableDictionary<NSString *, NSNumber *> *)snap oldTimestamps:(NSDictionary<NSString *, NSNumber *> *)old baseChanged:(NSInteger)base completion:(void (^)(NSInteger))completion {
	NSArray *batch = vanished.count > kBatchCap ? [vanished subarrayWithRange:NSMakeRange(0, kBatchCap)] : vanished;
	__block NSInteger changed = base;
	[self resolveVanishedIncomingBatch:batch index:0 owner:owner snapshot:snap oldTimestamps:old changed:&changed completion:completion];
}

- (void)resolveVanishedIncomingBatch:(NSArray<NSString *> *)batch index:(NSUInteger)idx owner:(NSString *)owner snapshot:(NSMutableDictionary<NSString *, NSNumber *> *)snap oldTimestamps:(NSDictionary<NSString *, NSNumber *> *)old changed:(NSInteger *)changedPtr completion:(void (^)(NSInteger))completion {
	if (idx >= batch.count) {
		[RYGFollowRequestStorage setIncomingSnapshot:snap forOwnerPK:owner];
		completion(*changedPtr);
		return;
	}
	NSString *pk = batch[idx];
	NSInteger *cp = changedPtr;
	void (^next)(void) = ^{
		NSUInteger n = idx + 1;
		if (n < batch.count)
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBatchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self resolveVanishedIncomingBatch:batch index:n owner:owner snapshot:snap oldTimestamps:old changed:cp completion:completion];
			});
		else {
			[RYGFollowRequestStorage setIncomingSnapshot:snap forOwnerPK:owner];
			completion(*cp);
		}
	};
	[RYGInstagramAPI fetchFriendshipForPK:pk completion:^(NSDictionary *st, NSError *error) {
		// Couldn't read a real status — don't classify, keep it pending, retry next poll.
		if (![st isKindOfClass:NSDictionary.class]) { snap[pk] = old[pk] ?: @([NSDate date].timeIntervalSince1970); next(); return; }

		// Authoritative: still requesting to follow you — it only fell off a partial list. Keep as-is.
		if ([st[@"incoming_request"] boolValue]) { snap[pk] = old[pk] ?: @([NSDate date].timeIntervalSince1970); next(); return; }

		RYGFollowRequestType type;
		if ([st[@"followed_by"] boolValue]) { type = RYGFollowRequestTypeApproved; [RYGFollowRequestStorage consumeIgnoredPK:pk ownerPK:owner]; }
		else if ([RYGFollowRequestStorage consumeIgnoredPK:pk ownerPK:owner]) type = RYGFollowRequestTypeIgnored;
		else type = RYGFollowRequestTypeWithdrawn;

		RYGFollowRequest *r = [RYGFollowRequestStorage resolveTargetPK:pk fromType:RYGFollowRequestTypeReceived toType:type ownerPK:owner];
		if (r) {
			(*cp)++;
			if (type == RYGFollowRequestTypeWithdrawn && [RYGUtils getBoolPref:@"follow_requests_notify_withdrawn"]) {
				NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
				[self notify:RYG_NOTIF_FOLLOW_REQ_WITHDRAWN title:RYGLocalized(@"Follow request withdrawn")
					subtitle:[NSString stringWithFormat:RYGLocalized(@"%@ withdrew their request"), handle]
					   scope:RYGFollowRequestDirectionIncoming success:NO];
			}
		}
		next();
	}];
}

#pragma mark - Notify

// Pill when foregrounded, single mirrored local notification when not; tap opens the list.
- (void)notify:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)sub scope:(RYGFollowRequestDirection)scope success:(BOOL)success {
	dispatch_async(dispatch_get_main_queue(), ^{
		RYGNotifyTap(actionID, title, sub, nil, success ? RYGNotificationToneSuccess : RYGNotificationToneInfo, ^{
			[RYGFollowRequestsViewController presentAtScope:scope];
		});
	});
}

@end
