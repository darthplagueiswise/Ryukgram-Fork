#import "SCIFollowRequestTracker.h"
#import "../../InstagramHeaders.h"
#import <UIKit/UIKit.h>
#import "SCIFollowRequestStorage.h"
#import "SCIFollowRequestModels.h"
#import "SCIFollowRequestsViewController.h"
#import "../../Utils.h"
#import "../../Networking/SCIInstagramAPI.h"
#import "../../Localization/SCILocalization.h"
#import "../../UI/Notification/SCINotificationCenter.h"
#import "../../UI/Notification/SCINotificationActions.h"
#import "../../Background/SCIBackgroundActivity.h"
#import <objc/runtime.h>

// IG throttles /friendships/ — small batches with a cushion between them.
static const NSInteger kBatchCap = 50;
static const NSTimeInterval kBatchDelay = 1.5;
static const NSTimeInterval kMinCheckThrottle = 45;
static const NSTimeInterval kConfirmDelay = 2.0;
// IG can briefly report no outgoing request right after sending — don't mark a
// fresh request Rejected within this window (Accepted via following=YES is exact).
static const NSTimeInterval kRejectGrace = 60;

static id sciFieldCacheValue(id obj, NSString *key) {
	if (!obj || !key) return nil;
	Ivar fc = NULL;
	for (Class c = [obj class]; c && !fc; c = class_getSuperclass(c)) fc = class_getInstanceVariable(c, "_fieldCache");
	if (!fc) return nil;
	NSDictionary *dict = object_getIvar(obj, fc);
	if (![dict isKindOfClass:NSDictionary.class]) return nil;
	id v = dict[key];
	return (!v || [v isKindOfClass:NSNull.class]) ? nil : v;
}

static NSString *sciStr(id v) {
	if ([v isKindOfClass:NSString.class]) return v;
	if ([v respondsToSelector:@selector(stringValue)]) return [v stringValue];
	return nil;
}

static BOOL sciBoxedBool(id v) {
	if (!v || v == (id)NSNull.null) return NO;
	return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

// friendship_status is an IGAPIRelationshipInfoDict with a -following getter.
static BOOL sciAlreadyFollowing(id igUser) {
	id fs = sciFieldCacheValue(igUser, @"friendship_status");
	if (fs && [fs respondsToSelector:@selector(following)]) return sciBoxedBool([fs following]);
	return NO;
}

@interface SCIFollowRequestTracker ()
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL isChecking;
@property (nonatomic, strong) NSDate *lastCheckDate;
@end

@implementation SCIFollowRequestTracker

+ (instancetype)shared {
	static SCIFollowRequestTracker *s; static dispatch_once_t once;
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

- (BOOL)enabled { return [SCIUtils getBoolPref:@"follow_requests_enabled"]; }
- (BOOL)trackOutgoing { return [SCIUtils getBoolPref:@"follow_requests_track_outgoing"]; }
- (BOOL)trackIncoming { return [SCIUtils getBoolPref:@"follow_requests_track_incoming"]; }

- (NSTimeInterval)checkInterval {
	NSString *v = [SCIUtils getStringPref:@"follow_requests_check_interval"];
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
	NSString *pk = sciStr(sciFieldCacheValue(igUser, @"strong_id__")) ?: sciStr(sciFieldCacheValue(igUser, @"pk"));
	if (!pk.length) return;
	NSString *username = sciStr(sciFieldCacheValue(igUser, @"username"));
	NSString *fullName = sciStr(sciFieldCacheValue(igUser, @"full_name"));
	NSString *picURL = sciStr(sciFieldCacheValue(igUser, @"profile_pic_url"));
	NSString *picID = sciStr(sciFieldCacheValue(igUser, @"profile_pic_id"));
	id privVal = sciFieldCacheValue(igUser, @"is_private");
	NSString *owner = [SCIUtils currentUserPK] ?: @"anon";

	// Tapping "Following" on an account you already follow fires this same hook — not a new request.
	if (sciAlreadyFollowing(igUser)) return;

	// Private → pending request; public follows instantly and isn't a request.
	// Privacy unknown → confirm via one API call.
	if (privVal != nil) {
		if ([privVal boolValue]) [self recordSentPK:pk username:username fullName:fullName picURL:picURL picID:picID isPrivate:YES owner:owner];
	} else {
		[self confirmAndRecordPK:pk username:username fullName:fullName picURL:picURL picID:picID owner:owner];
	}
}

- (void)recordSentPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID isPrivate:(BOOL)isPrivate owner:(NSString *)owner {
	if ([SCIFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner]) return;
	SCIFollowRequest *r = [SCIFollowRequest new];
	r.userPK = pk; r.username = username; r.fullName = fullName;
	r.profilePicURL = picURL; r.profilePicID = picID; r.isPrivate = isPrivate;
	r.type = SCIFollowRequestTypeSent;
	[SCIFollowRequestStorage recordRequest:r forOwnerPK:owner];
}

- (void)recordManualFollowForPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID {
	if (![self enabled] || ![self trackOutgoing] || !pk.length) return;
	[self confirmAndRecordPK:pk username:username fullName:fullName picURL:picURL picID:picID owner:([SCIUtils currentUserPK] ?: @"anon")];
}

// Confirm a tapped follow actually became a pending request before recording it.
- (void)confirmAndRecordPK:(NSString *)pk username:(NSString *)username fullName:(NSString *)fullName picURL:(NSString *)picURL picID:(NSString *)picID owner:(NSString *)owner {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kConfirmDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[SCIInstagramAPI fetchFriendshipStatusesForPKs:@[pk] completion:^(NSDictionary *statuses, NSError *error) {
			NSDictionary *st = statuses[pk];
			if (![st[@"outgoing_request"] boolValue] || [st[@"following"] boolValue]) return;
			[self recordSentPK:pk username:username fullName:fullName picURL:picURL picID:picID isPrivate:[st[@"is_private"] boolValue] owner:owner];
		}];
	});
}

- (void)captureCancelForUser:(id)igUser {
	if (![self enabled] || ![self trackOutgoing] || !igUser) return;
	NSString *pk = sciStr(sciFieldCacheValue(igUser, @"strong_id__")) ?: sciStr(sciFieldCacheValue(igUser, @"pk"));
	if (!pk.length) return;
	NSString *owner = [SCIUtils currentUserPK] ?: @"anon";
	// Only a pending request can be cancelled; unfollowing an accepted account isn't one.
	if ([SCIFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner])
		[SCIFollowRequestStorage resolveTargetPK:pk fromType:SCIFollowRequestTypeSent toType:SCIFollowRequestTypeCancelled ownerPK:owner];
}

#pragma mark - Capture: incoming (them → you)

- (void)captureIgnoreIncomingPK:(NSString *)pk {
	if (![self enabled] || ![self trackIncoming] || !pk.length) return;
	NSString *owner = [SCIUtils currentUserPK] ?: @"anon";
	[SCIFollowRequestStorage markIgnoredPK:pk ownerPK:owner];
	[SCIFollowRequestStorage resolveTargetPK:pk fromType:SCIFollowRequestTypeReceived toType:SCIFollowRequestTypeIgnored ownerPK:owner];
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
	NSString *owner = [SCIUtils currentUserPK];
	if (!owner.length) { if (completion) completion(0); return; }

	self.lastCheckDate = [NSDate date];
	self.isChecking = YES;
	// Keep the poll alive if the app is backgrounded mid-check (batches are spaced apart).
	[SCIBackgroundActivity setSource:@"follow_requests" active:YES];
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
		[SCIBackgroundActivity setSource:@"follow_requests" active:NO];
		if (completion) completion(total);
	});
}

#pragma mark - Outgoing engine

- (void)runOutgoingForOwner:(NSString *)owner completion:(void (^)(NSInteger))completion {
	NSArray<NSString *> *pending = [SCIFollowRequestStorage pendingTargetPKsForOwnerPK:owner];
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
	[SCIInstagramAPI fetchFriendshipStatusesForPKs:batches[idx] completion:^(NSDictionary *statuses, NSError *error) {
		for (NSString *pk in batches[idx]) {
			NSDictionary *st = statuses[pk];
			if (![st isKindOfClass:NSDictionary.class]) continue;
			if ([st[@"following"] boolValue]) { if ([self resolveOutgoingPK:pk type:SCIFollowRequestTypeAccepted owner:owner]) (*cp)++; }
			else if (![st[@"outgoing_request"] boolValue]) { if ([self resolveOutgoingPK:pk type:SCIFollowRequestTypeRejected owner:owner]) (*cp)++; }
		}
		NSUInteger next = idx + 1;
		if (next < batches.count)
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBatchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self runOutgoingBatches:batches index:next owner:owner changed:cp completion:completion];
			});
		else completion(*cp);
	}];
}

- (BOOL)resolveOutgoingPK:(NSString *)pk type:(SCIFollowRequestType)type owner:(NSString *)owner {
	if (type == SCIFollowRequestTypeRejected) {
		SCIFollowRequest *p = [SCIFollowRequestStorage latestPendingForTargetPK:pk ownerPK:owner];
		if (p && [NSDate date].timeIntervalSince1970 - p.sentAt < kRejectGrace) return NO;
	}
	SCIFollowRequest *r = [SCIFollowRequestStorage resolveTargetPK:pk fromType:SCIFollowRequestTypeSent toType:type ownerPK:owner];
	if (!r) return NO;
	BOOL accepted = (type == SCIFollowRequestTypeAccepted);
	BOOL notify = accepted ? [SCIUtils getBoolPref:@"follow_requests_notify_accepted"] : [SCIUtils getBoolPref:@"follow_requests_notify_rejected"];
	if (notify) {
		NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
		[self notify:accepted ? SCI_NOTIF_FOLLOW_REQ_ACCEPTED : SCI_NOTIF_FOLLOW_REQ_REJECTED
			   title:accepted ? SCILocalized(@"Follow request accepted") : SCILocalized(@"Follow request declined")
			subtitle:accepted ? [NSString stringWithFormat:SCILocalized(@"%@ accepted your request"), handle]
							   : [NSString stringWithFormat:SCILocalized(@"%@ is no longer pending"), handle]
			   scope:SCIFollowRequestDirectionOutgoing success:accepted];
	}
	return YES;
}

#pragma mark - Incoming engine

- (void)runIncomingForOwner:(NSString *)owner completion:(void (^)(NSInteger))completion {
	[SCIInstagramAPI fetchPendingFollowRequestsWithCompletion:^(NSArray<NSDictionary *> *users, NSError *error) {
		if (error) { completion(0); return; }
		BOOL seeded = [SCIFollowRequestStorage incomingSeededForOwnerPK:owner];
		NSDictionary<NSString *, NSNumber *> *old = [SCIFollowRequestStorage incomingSnapshotForOwnerPK:owner];
		NSMutableDictionary<NSString *, NSNumber *> *snap = [NSMutableDictionary dictionary];
		NSMutableSet *currentPKs = [NSMutableSet set];
		NSTimeInterval now = [NSDate date].timeIntervalSince1970;
		NSInteger changed = 0;

		for (NSDictionary *u in users) {
			NSString *pk = sciStr(u[@"pk"]) ?: sciStr(u[@"pk_id"]) ?: sciStr(u[@"id"]);
			if (!pk.length) continue;
			[currentPKs addObject:pk];
			snap[pk] = old[pk] ?: @(now);
			if (old[pk] != nil) continue;

			SCIFollowRequest *r = [SCIFollowRequest new];
			r.userPK = pk;
			r.username = sciStr(u[@"username"]);
			r.fullName = sciStr(u[@"full_name"]);
			r.profilePicURL = sciStr(u[@"profile_pic_url"]);
			r.profilePicID = sciStr(u[@"profile_pic_id"]);
			r.isPrivate = [u[@"is_private"] boolValue];
			r.type = SCIFollowRequestTypeReceived;
			[SCIFollowRequestStorage recordRequest:r forOwnerPK:owner];
			changed++;
			// Seeding pass records existing requests silently; only later arrivals notify.
			if (seeded && [SCIUtils getBoolPref:@"follow_requests_notify_received"]) {
				NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
				[self notify:SCI_NOTIF_FOLLOW_REQ_RECEIVED title:SCILocalized(@"New follow request")
					subtitle:[NSString stringWithFormat:SCILocalized(@"%@ asked to follow you"), handle]
					   scope:SCIFollowRequestDirectionIncoming success:NO];
			}
		}

		NSMutableArray *vanished = [NSMutableArray array];
		for (NSString *pk in old) if (![currentPKs containsObject:pk]) [vanished addObject:pk];

		[SCIFollowRequestStorage setIncomingSnapshot:snap forOwnerPK:owner];
		if (!seeded) [SCIFollowRequestStorage setIncomingSeededForOwnerPK:owner];

		if (!vanished.count) { completion(changed); return; }
		[self resolveVanishedIncoming:vanished owner:owner baseChanged:changed completion:completion];
	}];
}

// A vanished incoming request was approved or withdrawn. Only single
// /friendships/show/ carries `followed_by` to tell them apart (show_many drops it).
- (void)resolveVanishedIncoming:(NSArray<NSString *> *)vanished owner:(NSString *)owner baseChanged:(NSInteger)base completion:(void (^)(NSInteger))completion {
	NSArray *batch = vanished.count > kBatchCap ? [vanished subarrayWithRange:NSMakeRange(0, kBatchCap)] : vanished;
	__block NSInteger changed = base;
	[self resolveVanishedIncomingBatch:batch index:0 owner:owner changed:&changed completion:completion];
}

- (void)resolveVanishedIncomingBatch:(NSArray<NSString *> *)batch index:(NSUInteger)idx owner:(NSString *)owner changed:(NSInteger *)changedPtr completion:(void (^)(NSInteger))completion {
	if (idx >= batch.count) { completion(*changedPtr); return; }
	NSString *pk = batch[idx];
	NSInteger *cp = changedPtr;
	void (^next)(void) = ^{
		NSUInteger n = idx + 1;
		if (n < batch.count)
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBatchDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self resolveVanishedIncomingBatch:batch index:n owner:owner changed:cp completion:completion];
			});
		else completion(*cp);
	};
	[SCIInstagramAPI fetchFriendshipForPK:pk completion:^(NSDictionary *st, NSError *error) {
		// Couldn't read the status — don't classify, retry next poll.
		if (![st isKindOfClass:NSDictionary.class]) { next(); return; }

		SCIFollowRequestType type;
		if ([st[@"followed_by"] boolValue]) { type = SCIFollowRequestTypeApproved; [SCIFollowRequestStorage consumeIgnoredPK:pk ownerPK:owner]; }
		else if ([SCIFollowRequestStorage consumeIgnoredPK:pk ownerPK:owner]) type = SCIFollowRequestTypeIgnored;
		else type = SCIFollowRequestTypeWithdrawn;

		SCIFollowRequest *r = [SCIFollowRequestStorage resolveTargetPK:pk fromType:SCIFollowRequestTypeReceived toType:type ownerPK:owner];
		if (r) {
			(*cp)++;
			if (type == SCIFollowRequestTypeWithdrawn && [SCIUtils getBoolPref:@"follow_requests_notify_withdrawn"]) {
				NSString *handle = r.username.length ? [@"@" stringByAppendingString:r.username] : r.displayName;
				[self notify:SCI_NOTIF_FOLLOW_REQ_WITHDRAWN title:SCILocalized(@"Follow request withdrawn")
					subtitle:[NSString stringWithFormat:SCILocalized(@"%@ withdrew their request"), handle]
					   scope:SCIFollowRequestDirectionIncoming success:NO];
			}
		}
		next();
	}];
}

#pragma mark - Notify

// Pill when foregrounded, single mirrored local notification when not; tap opens the list.
- (void)notify:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)sub scope:(SCIFollowRequestDirection)scope success:(BOOL)success {
	dispatch_async(dispatch_get_main_queue(), ^{
		SCINotifyTap(actionID, title, sub, nil, success ? SCINotificationToneSuccess : SCINotificationToneInfo, ^{
			[SCIFollowRequestsViewController presentAtScope:scope];
		});
	});
}

@end
