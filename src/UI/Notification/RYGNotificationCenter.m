#import "RYGNotificationCenter.h"
#import "RYGNotificationMirror.h"
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <QuartzCore/QuartzCore.h>

// ───── Pref keys (mirrored in RYGDefaultsDictionary in RYGDefaults.m) ─────
static NSString *const kPrefStyle		   = @"notif_style";
static NSString *const kPrefPosition		= @"notif_position";
static NSString *const kPrefDefaultSurface  = @"notif_default_surface";
static NSString *const kPrefMaxVisible	  = @"notif_max_visible";
static NSString *const kPrefHaptics		 = @"notif_haptics";
static NSString *const kPrefDuration		= @"notif_duration";
static NSString *const kPrefMaster		  = @"notif_master_enabled";
static NSString *const kPerActionPrefix	 = @"notif_action_";

static const NSTimeInterval kDefaultToastDuration = 1.8;
static const NSTimeInterval kErrorToastDuration   = 2.6;
static const NSTimeInterval kTerminalLinger	   = 1.2;
static const CGFloat		kStackSpacing		 = 8.0;
static const NSUInteger	 kHardMaxVisible	   = 3;

// Coalescing: bursty actions buffer for a sliding window, then flush as one
// summary pill. Cap from first enqueue so a slow drip still flushes.
static const NSTimeInterval kCoalesceWindow  = 0.7;
static const NSTimeInterval kCoalesceMaxHold = 2.0;

static NSString *rygCoalesceSummaryFormat(NSString *actionID) {
	if ([actionID isEqualToString:RYG_NOTIF_UNSENT_MESSAGE])   return RYGLocalized(@"%lu messages unsent");
	if ([actionID isEqualToString:RYG_NOTIF_REACTION_REMOVED]) return RYGLocalized(@"%lu reactions removed");
	if ([actionID isEqualToString:RYG_NOTIF_SEEN_DM])          return RYGLocalized(@"%lu chats marked seen");
	if ([actionID isEqualToString:RYG_NOTIF_SEEN_STORY])       return RYGLocalized(@"%lu stories marked seen");
	if ([actionID isEqualToString:RYG_NOTIF_READ_RECEIPT])     return RYGLocalized(@"%lu of your messages read");
	return RYGLocalized(@"%lu notifications");
}

// Spring + slide tuning for entrance / dismiss / restack.
static const NSTimeInterval kInsertDuration   = 0.55;
static const CGFloat		kInsertDamping	= 0.78;
static const CGFloat		kInsertVelocity   = 0.7;
static const CGFloat		kEntranceSlide	= 80.0;
static const CGFloat		kEntranceScale	= 0.9;
static const NSTimeInterval kDismissDuration  = 0.28;
static const CGFloat		kDismissSlide	 = 60.0;
static const CGFloat		kDismissScale	 = 0.92;
static const NSTimeInterval kRelayoutDuration = 0.32;
static const CGFloat		kRelayoutDamping  = 0.82;
static const CGFloat		kRelayoutVelocity = 0.5;

typedef void (^RYGNotifTapBlock)(void);
typedef RYGNotifTapBlock (^RYGNotifTapProvider)(void);

// ───── Surface routing ─────
typedef NS_ENUM(NSUInteger, RYGNotifSurface) {
	RYGNotifSurfacePill,
	RYGNotifSurfaceIGNative,
	RYGNotifSurfaceOff,
};

static RYGNotifSurface RYGNotifSurfaceFromString(NSString *s, RYGNotifSurface fallback) {
	if ([s isEqualToString:@"pill"]) return RYGNotifSurfacePill;
	if ([s isEqualToString:@"ig_native"]) return RYGNotifSurfaceIGNative;
	if ([s isEqualToString:@"off"]) return RYGNotifSurfaceOff;
	return fallback;
}

static RYGNotificationStyle RYGNotifStyleFromString(NSString *s) {
	if ([s isEqualToString:@"colorful"]) return RYGNotificationStyleColorful;
	if ([s isEqualToString:@"glow"]) return RYGNotificationStyleGlow;
	if ([s isEqualToString:@"island"]) return RYGNotificationStyleIsland;
	return RYGNotificationStyleMinimal;
}

// "x,y" normalized of the safe area. Legacy strings map to sensible points.
static CGPoint RYGNotifPointFromString(NSString *s) {
	if ([s containsString:@","]) {
		NSArray<NSString *> *p = [s componentsSeparatedByString:@","];
		if (p.count == 2) return CGPointMake(MIN(MAX(p[0].doubleValue, 0.0), 1.0), MIN(MAX(p[1].doubleValue, 0.0), 1.0));
	}
	CGFloat y = [s hasPrefix:@"bottom"] ? 0.94 : 0.06;
	CGFloat x = [s hasSuffix:@"_left"] ? 0.26 : ([s hasSuffix:@"_right"] ? 0.74 : 0.50);
	return CGPointMake(x, y);
}

static RYGNotificationPosition RYGNotifPositionFromString(NSString *s) {
	return RYGNotifPointFromString(s).y >= 0.5 ? RYGNotificationPositionBottom : RYGNotificationPositionTop;
}

// 0 = leading, 1 = centered, 2 = trailing.
static NSInteger RYGNotifHAlignFromString(NSString *s) {
	CGFloat x = RYGNotifPointFromString(s).x;
	return x < 0.4 ? 0 : (x > 0.6 ? 2 : 1);
}

static inline CGFloat rygPillHeight(RYGNotificationPillView *pill) {
	CGFloat h = [pill pillTargetHeight];
	return h > 1.0 ? h : 50.0;
}

// ───── Owner-VC presentation walker ─────
static BOOL ryg_vcChainContainsClass(UIViewController *vc, Class cls) {
	if (!vc || !cls) return NO;
	if ([vc isKindOfClass:cls]) return YES;
	if (vc.presentedViewController && ryg_vcChainContainsClass(vc.presentedViewController, cls)) return YES;

	if ([vc isKindOfClass:UINavigationController.class]) {
		for (UIViewController *child in ((UINavigationController *)vc).viewControllers)
			if (ryg_vcChainContainsClass(child, cls)) return YES;
	} else if ([vc isKindOfClass:UITabBarController.class]) {
		for (UIViewController *child in ((UITabBarController *)vc).viewControllers)
			if (ryg_vcChainContainsClass(child, cls)) return YES;
	}

	return NO;
}

static BOOL ryg_isVCClassInPresentationChain(Class cls) {
	if (!cls) return NO;

	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows)
			if (ryg_vcChainContainsClass(w.rootViewController, cls)) return YES;
	}

	return ryg_vcChainContainsClass(UIApplication.sharedApplication.keyWindow.rootViewController, cls);
}

@interface RYGNotifSlot : NSObject
@property (nonatomic, strong) RYGNotificationPillView *pill;
@property (nonatomic, strong) NSLayoutConstraint *anchorConstraint;
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, assign) BOOL terminal;
@property (nonatomic, assign) BOOL isProgress;
@property (nonatomic, strong) NSTimer *autoDismissTimer;
@property (nonatomic, weak) RYGNotificationHandle *handle;
@property (nonatomic, copy) RYGNotifTapBlock tapBlock;
@end

@implementation RYGNotifSlot @end

@interface RYGNotifQueueItem : NSObject
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, assign) RYGNotificationTone tone;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) RYGNotifTapBlock onTap;
@end

@implementation RYGNotifQueueItem @end

@interface RYGNotificationHandle ()
@property (nonatomic, copy, readwrite) NSString *actionID;
@property (nonatomic, assign, readwrite) BOOL isFinished;
@property (nonatomic, weak) RYGNotifSlot *slot;
@property (nonatomic, weak) RYGNotificationCenter *center;
@end

@interface RYGNotificationCenter () {
	NSMutableArray<RYGNotifSlot *> *_visible;
	NSMutableArray<RYGNotifQueueItem *> *_queue;
	NSMutableDictionary<NSString *, id> *_tapProviders;
	NSMutableDictionary<NSString *, Class> *_tapProviderOwners;
	NSMutableDictionary<NSString *, NSMutableArray<RYGNotifQueueItem *> *> *_coalesceBuckets;
	NSMutableDictionary<NSString *, NSTimer *> *_coalesceTimers;
	NSMutableDictionary<NSString *, NSNumber *> *_coalesceFirstFire;
	UINotificationFeedbackGenerator *_notifGen;
	UIImpactFeedbackGenerator *_impactGen;
}

- (void)rygDispatchToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable NSString *)iconSymbol tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(nullable RYGNotifTapBlock)onTap;
- (BOOL)rygActionCoalesces:(NSString *)actionID;
- (void)rygEnqueueCoalesceForAction:(NSString *)actionID title:(NSString *)title subtitle:(nullable NSString *)subtitle icon:(nullable NSString *)icon tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(nullable RYGNotifTapBlock)onTap;
- (void)rygArmCoalesceTimerForAction:(NSString *)key;
- (void)rygFlushCoalesceForAction:(NSString *)key;
- (void)rygHandleSetProgress:(float)progress slot:(RYGNotifSlot *)slot;
- (void)rygHandleSetIndeterminate:(BOOL)indeterminate slot:(RYGNotifSlot *)slot;
- (void)rygHandleSetTitle:(NSString *)title subtitle:(NSString *)subtitle slot:(RYGNotifSlot *)slot;
- (void)rygHandleTerminate:(RYGNotifSlot *)slot tone:(RYGNotificationTone)tone title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon;
- (void)rygHandleDismiss:(RYGNotifSlot *)slot;
- (BOOL)rygInsertSlot:(RYGNotifSlot *)slot animated:(BOOL)animated;
@end

@implementation RYGNotificationCenter

+ (instancetype)shared {
	static RYGNotificationCenter *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [RYGNotificationCenter new]; });
	return s;
}

- (instancetype)init {
	self = [super init];
	if (!self) return nil;

	_visible = [NSMutableArray new];
	_queue = [NSMutableArray new];
	_tapProviders = [NSMutableDictionary new];
	_tapProviderOwners = [NSMutableDictionary new];
	_coalesceBuckets = [NSMutableDictionary new];
	_coalesceTimers = [NSMutableDictionary new];
	_coalesceFirstFire = [NSMutableDictionary new];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rygAppBackgrounded) name:UIApplicationDidEnterBackgroundNotification object:nil];
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Settings (read fresh per call — no caching)

- (RYGNotificationStyle)rygCurrentStyle {
	return RYGNotifStyleFromString([RYGUtils getStringPref:kPrefStyle]);
}

- (RYGNotificationPosition)rygCurrentPosition {
	return RYGNotifPositionFromString([RYGUtils getStringPref:kPrefPosition]);
}

- (NSInteger)rygCurrentHAlign {
	return RYGNotifHAlignFromString([RYGUtils getStringPref:kPrefPosition]);
}

- (CGFloat)rygCurrentYFraction {
	return RYGNotifPointFromString([RYGUtils getStringPref:kPrefPosition]).y;
}

- (BOOL)rygMasterEnabled {
	return [RYGUtils getBoolPref:kPrefMaster];
}

- (BOOL)rygHapticsEnabled {
	return [RYGUtils getBoolPref:kPrefHaptics];
}

- (double)rygDurationMultiplier {
	double d = [RYGUtils getDoublePref:kPrefDuration];
	return d > 0.01 ? d : 1.0;
}

- (NSUInteger)rygMaxVisible {
	double d = [RYGUtils getDoublePref:kPrefMaxVisible];
	NSUInteger n = d > 0.5 ? (NSUInteger)d : 2;
	return MAX(1, MIN(n, kHardMaxVisible));
}

- (RYGNotifSurface)rygDefaultSurface {
	return RYGNotifSurfaceFromString([RYGUtils getStringPref:kPrefDefaultSurface], RYGNotifSurfacePill);
}

- (RYGNotifSurface)rygSurfaceForAction:(NSString *)actionID isProgress:(BOOL)isProgress {
	if (![self rygMasterEnabled]) return RYGNotifSurfaceOff;

	NSString *key = [kPerActionPrefix stringByAppendingString:actionID ?: @""];
	RYGNotifSurface surface = RYGNotifSurfaceFromString([RYGUtils getStringPref:key], [self rygDefaultSurface]);

	// IG-native has no progress affordance; fall back to pill.
	if (surface == RYGNotifSurfaceIGNative && isProgress) return RYGNotifSurfacePill;

	RYGNotificationActionInfo *info = RYGNotificationActionInfoForID(actionID);
	if (surface == RYGNotifSurfaceIGNative && info && !(info.caps & RYGNotificationActionCapsAllowIG)) return RYGNotifSurfacePill;

	return surface;
}

#pragma mark - Public toast

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(RYGNotificationTone)tone {
	NSTimeInterval base = tone == RYGNotificationToneError ? kErrorToastDuration : kDefaultToastDuration;
	[self notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:base];
}

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration {
	[self notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:nil];
}

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(void (^)(void))onTap {
	// Foreground bursts of a coalescing action merge into one summary pill.
	// Background mirroring stays 1:1 (the OS groups local notifications itself).
	if ([self rygActionCoalesces:actionID]) {
		RYGNotifTapBlock tapCopy = onTap ? [onTap copy] : nil;
		[self rygOnMain:^{
			if ([RYGNotificationMirror appIsBackgrounded])
				[self rygDispatchToastForAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:tapCopy];
			else
				[self rygEnqueueCoalesceForAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:tapCopy];
		}];
		return;
	}

	[self rygDispatchToastForAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:onTap];
}

- (void)rygDispatchToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(void (^)(void))onTap {
	RYGNotifSurface surface = [self rygSurfaceForAction:actionID isProgress:NO];
	if (surface == RYGNotifSurfaceOff) return;

	RYGNotifTapBlock tap = nil;
	if (onTap) tap = [onTap copy];
	else tap = [self rygResolveDefaultTapForAction:actionID];

	if (surface == RYGNotifSurfaceIGNative) {
		NSTimeInterval effective = MAX(0.6, duration * [self rygDurationMultiplier]);
		[self rygOnMain:^{
			if ([self rygMirrorIfBackgrounded:actionID title:title subtitle:subtitle onTap:tap]) return;
			[RYGUtils showIGNativeToastForDuration:effective title:title subtitle:subtitle onTap:tap];
		}];
		return;
	}

	[self rygOnMain:^{
		if ([self rygMirrorIfBackgrounded:actionID title:title subtitle:subtitle onTap:tap]) return;
		[self rygPresentToastForAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:tap];
	}];
}

// Mirrors to the notification centre. Backgrounded: replaces the pill (YES).
// Foreground "show while open": rides alongside it (NO keeps the pill). Main thread.
- (BOOL)rygMirrorIfBackgrounded:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle onTap:(RYGNotifTapBlock)onTap {
	BOOL backgrounded = [RYGNotificationMirror appIsBackgrounded];
	if (!backgrounded && ![RYGNotificationMirror mirrorsWhileForeground]) return NO;
	if (![RYGNotificationMirror shouldMirrorAction:actionID]) return NO;

	[RYGNotificationMirror mirrorActionID:actionID title:title subtitle:subtitle onTap:onTap];
	return backgrounded;
}

- (void)notifyError:(NSString *)actionID title:(NSString *)title message:(NSString *)message {
	[self notifyAction:actionID title:title subtitle:message icon:@"exclamationmark.triangle.fill" tone:RYGNotificationToneError];
}

#pragma mark - Coalescing (main thread)

- (BOOL)rygActionCoalesces:(NSString *)actionID {
	RYGNotificationActionInfo *info = RYGNotificationActionInfoForID(actionID);
	return info && (info.caps & RYGNotificationActionCapsCoalesce);
}

- (void)rygEnqueueCoalesceForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(RYGNotifTapBlock)onTap {
	NSString *key = actionID ?: @"";

	// Leading edge: first event shows instantly so a single action never lags;
	// only the overflow that lands during the window is summarised.
	if (!_coalesceBuckets[key]) {
		_coalesceBuckets[key] = [NSMutableArray new];
		_coalesceFirstFire[key] = @(CACurrentMediaTime());
		[self rygDispatchToastForAction:key title:title subtitle:subtitle icon:icon tone:tone duration:duration onTap:onTap];
		[self rygArmCoalesceTimerForAction:key];
		return;
	}

	RYGNotifQueueItem *item = [RYGNotifQueueItem new];
	item.actionID = key;
	item.title = title ?: @"";
	item.subtitle = subtitle ?: @"";
	item.icon = icon ?: @"";
	item.tone = tone;
	item.duration = duration;
	item.onTap = onTap;
	[_coalesceBuckets[key] addObject:item];

	[self rygArmCoalesceTimerForAction:key];
}

- (void)rygArmCoalesceTimerForAction:(NSString *)key {
	[_coalesceTimers[key] invalidate];

	NSTimeInterval elapsed = CACurrentMediaTime() - _coalesceFirstFire[key].doubleValue;
	NSTimeInterval delay = MIN(kCoalesceWindow, MAX(0.0, kCoalesceMaxHold - elapsed));
	if (delay <= 0.001) {
		[self rygFlushCoalesceForAction:key];
		return;
	}

	__weak typeof(self) weakSelf = self;
	_coalesceTimers[key] = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:^(__unused NSTimer *t) {
		[weakSelf rygFlushCoalesceForAction:key];
	}];
}

- (void)rygFlushCoalesceForAction:(NSString *)key {
	NSArray<RYGNotifQueueItem *> *items = _coalesceBuckets[key];
	[_coalesceTimers[key] invalidate];
	[_coalesceTimers removeObjectForKey:key];
	[_coalesceBuckets removeObjectForKey:key];
	[_coalesceFirstFire removeObjectForKey:key];
	if (!items.count) return;

	if (items.count == 1) {
		RYGNotifQueueItem *it = items.firstObject;
		[self rygDispatchToastForAction:it.actionID title:it.title subtitle:it.subtitle.length ? it.subtitle : nil icon:it.icon.length ? it.icon : nil tone:it.tone duration:it.duration onTap:it.onTap];
		return;
	}

	// onTap:nil → dispatch resolves the action's registered default tap (e.g. the deleted-messages log).
	RYGNotifQueueItem *first = items.firstObject;
	NSString *title = [NSString stringWithFormat:rygCoalesceSummaryFormat(key), (unsigned long)items.count];
	[self rygDispatchToastForAction:key title:title subtitle:nil icon:first.icon.length ? first.icon : nil tone:first.tone duration:first.duration onTap:nil];
}

#pragma mark - Public progress

- (RYGNotificationHandle *)beginProgressForAction:(NSString *)actionID title:(NSString *)title onCancel:(void (^)(void))onCancel {
	return [self rygBeginProgressForAction:actionID title:title indeterminate:NO icon:@"arrow.down.to.line" onCancel:onCancel];
}

- (RYGNotificationHandle *)beginLoadingForAction:(NSString *)actionID title:(NSString *)title onCancel:(void (^)(void))onCancel {
	return [self rygBeginProgressForAction:actionID title:title indeterminate:YES icon:@"hourglass" onCancel:onCancel];
}

- (RYGNotificationHandle *)rygBeginProgressForAction:(NSString *)actionID title:(NSString *)title indeterminate:(BOOL)indeterminate icon:(NSString *)icon onCancel:(void (^)(void))onCancel {
	RYGNotifSurface surface = [self rygSurfaceForAction:actionID isProgress:YES];
	if (surface == RYGNotifSurfaceOff) return nil;

	RYGNotificationHandle *handle = [RYGNotificationHandle new];
	handle.actionID = actionID;
	handle.center = self;

	RYGNotifTapBlock cancelCopy = [onCancel copy];
	RYGNotifTapBlock tap = [self rygResolveDefaultTapForAction:actionID];

	[self rygOnMain:^{
		RYGNotifSlot *slot = [self rygCreateSlotForAction:actionID title:title subtitle:nil icon:icon tone:RYGNotificationToneInfo isProgress:YES onTap:tap];

		slot.handle = handle;
		slot.pill.showsProgress = YES;
		slot.pill.indeterminate = indeterminate;
		slot.pill.showsCancelButton = cancelCopy != nil;
		slot.pill.onCancel = ^(__unused RYGNotificationPillView *pill) {
			if (cancelCopy) cancelCopy();
		};

		handle.slot = slot;
		[slot.pill refreshSizeAnimated:NO];

		if (![self rygInsertSlot:slot animated:YES]) {
			handle.isFinished = YES;
			handle.slot = nil;
		}
	}];

	return handle;
}

#pragma mark - Stack mgmt

- (void)rygPresentToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration {
	[self rygPresentToastForAction:actionID title:title subtitle:subtitle icon:icon tone:tone duration:duration onTap:nil];
}

- (void)rygPresentToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(RYGNotificationTone)tone duration:(NSTimeInterval)duration onTap:(void (^)(void))onTap {
	NSTimeInterval effective = MAX(0.6, duration * [self rygDurationMultiplier]);

	if (_visible.count >= [self rygMaxVisible]) {
		RYGNotifQueueItem *item = [RYGNotifQueueItem new];
		item.actionID = actionID ?: @"";
		item.title = title ?: @"";
		item.subtitle = subtitle ?: @"";
		item.icon = icon ?: @"";
		item.tone = tone;
		item.duration = duration;
		item.onTap = [onTap copy];
		[_queue addObject:item];
		return;
	}

	RYGNotifSlot *slot = [self rygCreateSlotForAction:actionID title:title subtitle:subtitle icon:icon tone:tone isProgress:NO onTap:onTap];
	[slot.pill refreshSizeAnimated:NO];

	if (![self rygInsertSlot:slot animated:YES]) return;

	__weak typeof(self) weakSelf = self;
	__weak RYGNotifSlot *weakSlot = slot;
	slot.autoDismissTimer = [NSTimer scheduledTimerWithTimeInterval:effective repeats:NO block:^(__unused NSTimer *timer) {
		RYGNotificationCenter *self = weakSelf;
		RYGNotifSlot *slot = weakSlot;
		if (self && slot) [self rygDismissSlot:slot animated:YES];
	}];
}

- (RYGNotifSlot *)rygCreateSlotForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(RYGNotificationTone)tone isProgress:(BOOL)isProgress {
	return [self rygCreateSlotForAction:actionID title:title subtitle:subtitle icon:icon tone:tone isProgress:isProgress onTap:nil];
}

- (RYGNotifSlot *)rygCreateSlotForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(RYGNotificationTone)tone isProgress:(BOOL)isProgress onTap:(void (^)(void))onTap {
	RYGNotificationPillView *pill = [[RYGNotificationPillView alloc] initWithStyle:[self rygCurrentStyle] position:[self rygCurrentPosition]];
	pill.titleText = title ?: @"";
	pill.subtitleText = subtitle;
	pill.iconSymbolName = icon;
	[pill applyTone:tone animated:NO];

	RYGNotifSlot *slot = [RYGNotifSlot new];
	slot.pill = pill;
	slot.actionID = actionID;
	slot.isProgress = isProgress;
	slot.tapBlock = onTap;

	RYGNotifTapBlock tapCopy = [onTap copy];
	__weak typeof(self) weakSelf = self;
	__weak RYGNotifSlot *weakSlot = slot;

	pill.onTap = ^(__unused RYGNotificationPillView *pill) {
		RYGNotificationCenter *self = weakSelf;
		RYGNotifSlot *slot = weakSlot;
		if (!self || !slot) return;
		if (tapCopy) tapCopy();
		if (!slot.isProgress) [self rygDismissSlot:slot animated:YES];
	};

	pill.onSwipeDismiss = ^(__unused RYGNotificationPillView *pill) {
		RYGNotificationCenter *self = weakSelf;
		RYGNotifSlot *slot = weakSlot;
		if (self && slot) [self rygDismissSlot:slot animated:YES];
	};

	return slot;
}

- (UIView *)rygHostView {
	UIWindow *keyWin = nil;

	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				keyWin = w;
				break;
			}
		}

		if (keyWin) break;
	}

	if (!keyWin) keyWin = UIApplication.sharedApplication.keyWindow;
	return keyWin ?: topMostController().view;
}

- (BOOL)rygInsertSlot:(RYGNotifSlot *)slot animated:(BOOL)animated {
	UIView *host = [self rygHostView];
	if (!host || !slot.pill) return NO;

	RYGNotificationPillView *pill = slot.pill;
	[host addSubview:pill];
	[pill refreshSizeAnimated:NO];

	BOOL bottom = [self rygCurrentPosition] == RYGNotificationPositionBottom;

	UILayoutGuide *safe = host.safeAreaLayoutGuide;
	NSLayoutConstraint *anchor = bottom
		? [pill.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:0.0]
		: [pill.topAnchor constraintEqualToAnchor:safe.topAnchor constant:0.0];
	anchor.active = YES;

	switch ([self rygCurrentHAlign]) {
		case 0: [pill.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10.0].active = YES; break;
		case 2: [pill.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-10.0].active = YES; break;
		default: [pill.centerXAnchor constraintEqualToAnchor:host.centerXAnchor].active = YES; break;
	}

	slot.anchorConstraint = anchor;

	[_visible addObject:slot];
	[self rygHapticForTone:pill.tone];

	// Settle all pills at their real positions before the entrance slide.
	[self rygRelayoutVisibleAnimated:NO host:host];
	[host layoutIfNeeded];

	CGFloat slideY = bottom ? kEntranceSlide : -kEntranceSlide;
	pill.alpha = 0.0;
	pill.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(kEntranceScale, kEntranceScale), CGAffineTransformMakeTranslation(0, slideY));

	if (!animated) {
		pill.alpha = 1.0;
		pill.transform = CGAffineTransformIdentity;
		return YES;
	}

	[UIView animateWithDuration:kInsertDuration delay:0 usingSpringWithDamping:kInsertDamping initialSpringVelocity:kInsertVelocity options:UIViewAnimationOptionCurveEaseOut animations:^{
		pill.alpha = 1.0;
		pill.transform = CGAffineTransformIdentity;
		[host layoutIfNeeded];
	} completion:nil];

	return YES;
}

- (void)rygRelayoutVisibleAnimated:(BOOL)animated host:(UIView *)host {
	if (!host) return;

	BOOL bottom = [self rygCurrentPosition] == RYGNotificationPositionBottom;
	NSUInteger count = _visible.count;
	if (!count) return;

	// yFrac is normalized over the full screen (matching the editor); convert to a
	// distance from the safe-area anchor so the top inset isn't double-counted.
	CGFloat fullH = host.bounds.size.height;
	UIEdgeInsets ins = host.safeAreaInsets;
	CGFloat yFrac = [self rygCurrentYFraction];
	CGFloat centerFull = yFrac * fullH;
	CGFloat firstH = rygPillHeight(_visible[bottom ? count - 1 : 0].pill);
	CGFloat fromEdge = bottom ? ((fullH - ins.bottom) - centerFull) : (centerFull - ins.top);
	CGFloat acc = MAX(2.0, fromEdge - firstH / 2.0);

	for (NSUInteger i = 0; i < count; i++) {
		NSUInteger index = bottom ? count - 1 - i : i;
		RYGNotifSlot *slot = _visible[index];
		slot.anchorConstraint.constant = bottom ? -acc : acc;
		acc += rygPillHeight(slot.pill) + kStackSpacing;
	}

	if (!animated) return;

	[UIView animateWithDuration:kRelayoutDuration delay:0 usingSpringWithDamping:kRelayoutDamping initialSpringVelocity:kRelayoutVelocity options:UIViewAnimationOptionCurveEaseOut animations:^{
		[host layoutIfNeeded];
	} completion:nil];
}

- (void)rygDismissSlot:(RYGNotifSlot *)slot animated:(BOOL)animated {
	if (!slot || ![_visible containsObject:slot]) return;

	[slot.autoDismissTimer invalidate];
	slot.autoDismissTimer = nil;

	RYGNotificationPillView *pill = slot.pill;
	UIView *host = pill.superview ?: [self rygHostView];
	BOOL bottom = [self rygCurrentPosition] == RYGNotificationPositionBottom;

	void (^cleanup)(void) = ^{
		[pill removeFromSuperview];
		[self->_visible removeObject:slot];
		[self rygRelayoutVisibleAnimated:YES host:host];
		[self rygDrainQueueIfPossible];
	};

	if (!animated) {
		cleanup();
		return;
	}

	[UIView animateWithDuration:kDismissDuration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
		pill.alpha = 0.0;
		pill.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(kDismissScale, kDismissScale), CGAffineTransformMakeTranslation(0, bottom ? kDismissSlide : -kDismissSlide));
	} completion:^(__unused BOOL done) {
		cleanup();
	}];
}

- (void)rygDrainQueueIfPossible {
	while (_visible.count < [self rygMaxVisible] && _queue.count) {
		RYGNotifQueueItem *item = _queue.firstObject;
		[_queue removeObjectAtIndex:0];
		[self rygPresentToastForAction:item.actionID title:item.title subtitle:item.subtitle.length ? item.subtitle : nil icon:item.icon.length ? item.icon : nil tone:item.tone duration:item.duration onTap:item.onTap];
	}
}

- (void)dismissAll {
	[self rygOnMain:^{
		for (RYGNotifSlot *slot in self->_visible.copy)
			[self rygDismissSlot:slot animated:NO];

		[self->_queue removeAllObjects];

		for (NSTimer *t in self->_coalesceTimers.allValues) [t invalidate];
		[self->_coalesceTimers removeAllObjects];
		[self->_coalesceBuckets removeAllObjects];
		[self->_coalesceFirstFire removeAllObjects];
	}];
}

#pragma mark - Default tap providers

- (void)setDefaultTapProvider:(void (^ (^)(void))(void))provider forAction:(NSString *)actionID {
	[self setDefaultTapProvider:provider ownerVCClass:nil forAction:actionID];
}

- (void)setDefaultTapProvider:(void (^ (^)(void))(void))provider ownerVCClass:(Class)ownerClass forAction:(NSString *)actionID {
	if (!actionID.length) return;

	@synchronized (_tapProviders) {
		if (provider) {
			_tapProviders[actionID] = [provider copy];
			if (ownerClass) _tapProviderOwners[actionID] = ownerClass;
			else [_tapProviderOwners removeObjectForKey:actionID];
		} else {
			[_tapProviders removeObjectForKey:actionID];
			[_tapProviderOwners removeObjectForKey:actionID];
		}
	}
}

// Owner check is deferred to tap time; no-owner paths skip the wrap.
- (RYGNotifTapBlock)rygResolveDefaultTapForAction:(NSString *)actionID {
	if (!actionID.length) return nil;

	RYGNotifTapProvider provider = nil;
	Class owner = Nil;

	@synchronized (_tapProviders) {
		provider = _tapProviders[actionID];
		owner = _tapProviderOwners[actionID];
	}

	if (!provider) return nil;

	RYGNotifTapBlock resolved = provider();
	if (!resolved) return nil;

	RYGNotifTapBlock resolvedCopy = [resolved copy];
	if (!owner) return resolvedCopy;

	Class ownerCopy = owner;
	return [^{
		if (ryg_isVCClassInPresentationChain(ownerCopy)) return;
		resolvedCopy();
	} copy];
}

- (void)rygAppBackgrounded {
	// Work keeps running in the background, so keep its progress pill — drop only toasts.
	[self rygOnMain:^{
		// Flush any pending coalesce buckets now — dispatch mirrors them since we're backgrounded.
		for (NSString *key in self->_coalesceBuckets.allKeys.copy)
			[self rygFlushCoalesceForAction:key];

		for (RYGNotifSlot *slot in self->_visible.copy) {
			if (slot.isProgress && !slot.terminal) continue;
			[self rygDismissSlot:slot animated:NO];
		}

		// Queued toasts were never shown — mirror instead of dropping silently.
		for (RYGNotifQueueItem *item in self->_queue)
			[self rygMirrorIfBackgrounded:item.actionID title:item.title subtitle:item.subtitle.length ? item.subtitle : nil onTap:item.onTap];

		[self->_queue removeAllObjects];
	}];
}

#pragma mark - Defaults registration

+ (NSDictionary<NSString *, NSString *> *)defaultPerActionPrefs {
	NSMutableDictionary *m = [NSMutableDictionary new];

	for (RYGNotificationActionInfo *info in RYGNotificationActionsAll()) {
		if (info.identifier.length)
			m[[kPerActionPrefix stringByAppendingString:info.identifier]] = @"default";
	}

	return m.copy;
}

#pragma mark - Preview

- (void)presentPreviewDownloadEndingWithError:(BOOL)endWithError {
	[self rygOnMain:^{
		RYGNotificationHandle *h = [self beginProgressForAction:RYG_NOTIF_DOWNLOAD title:RYGLocalized(@"Preview download…") onCancel:nil];
		if (!h) return;

		NSArray<NSNumber *> *steps = @[@0.25, @0.55, @0.80, @1.00];

		for (NSUInteger i = 0; i < steps.count; i++) {
			float p = steps[i].floatValue;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.5 + i * 0.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[h setProgress:p];
			});
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (endWithError) [h error:RYGLocalized(@"Download failed") subtitle:RYGLocalized(@"Tap to retry")];
			else [h success:RYGLocalized(@"Saved") subtitle:RYGLocalized(@"Saved to Photos")];
		});
	}];
}

- (void)presentPreviewLoadingEndingWithError:(BOOL)endWithError {
	[self rygOnMain:^{
		RYGNotificationHandle *h = [self beginLoadingForAction:RYG_NOTIF_GENERIC title:[RYGLocalized(@"Loading") stringByAppendingString:@"…"] onCancel:nil];
		if (!h) return;

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (endWithError) [h error:RYGLocalized(@"Failed") subtitle:nil];
			else [h success:RYGLocalized(@"Done") subtitle:nil];
		});
	}];
}

- (void)presentPreviewWithTone:(RYGNotificationTone)tone {
	NSString *title = nil, *subtitle = nil, *icon = nil;

	switch (tone) {
		case RYGNotificationToneSuccess:
			title = RYGLocalized(@"Success preview");
			subtitle = RYGLocalized(@"Looks great");
			icon = @"checkmark.circle.fill";
			break;
		case RYGNotificationToneError:
			title = RYGLocalized(@"Error preview");
			subtitle = RYGLocalized(@"Something broke");
			icon = @"exclamationmark.triangle.fill";
			break;
		case RYGNotificationToneWarning:
			title = RYGLocalized(@"Warning preview");
			subtitle = RYGLocalized(@"Heads up");
			icon = @"exclamationmark.circle.fill";
			break;
		case RYGNotificationToneInfo:
		default:
			title = RYGLocalized(@"Info preview");
			subtitle = RYGLocalized(@"Just so you know");
			icon = @"info.circle.fill";
			break;
	}

	// Bypass routing — preview must always show our pill.
	[self rygOnMain:^{ [self rygPresentToastForAction:RYG_NOTIF_GENERIC title:title subtitle:subtitle icon:icon tone:tone duration:2.0]; }];
}

#pragma mark - Haptics

- (void)rygHapticForTone:(RYGNotificationTone)tone {
	if (![self rygHapticsEnabled]) return;

	if (tone == RYGNotificationToneSuccess || tone == RYGNotificationToneError) {
		if (!_notifGen) _notifGen = [UINotificationFeedbackGenerator new];
		[_notifGen notificationOccurred:tone == RYGNotificationToneSuccess ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
		return;
	}

	if (!_impactGen) _impactGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[_impactGen impactOccurred];
}

#pragma mark - Threading

- (void)rygOnMain:(dispatch_block_t)block {
	if (!block) return;
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - Handle bridging

- (void)rygHandleSetProgress:(float)progress slot:(RYGNotifSlot *)slot {
	[self rygOnMain:^{
		if (!slot || slot.terminal) return;
		[slot.pill setProgress:progress animated:YES];
	}];
}

- (void)rygHandleSetIndeterminate:(BOOL)indeterminate slot:(RYGNotifSlot *)slot {
	[self rygOnMain:^{
		if (!slot || slot.terminal) return;
		slot.pill.indeterminate = indeterminate;
	}];
}

- (void)rygHandleSetTitle:(NSString *)title subtitle:(NSString *)subtitle slot:(RYGNotifSlot *)slot {
	[self rygOnMain:^{
		if (!slot || slot.terminal) return;

		if (title) slot.pill.titleText = title;
		slot.pill.subtitleText = subtitle;
		[slot.pill refreshSizeAnimated:YES];

		UIView *host = slot.pill.superview;
		if (host) [self rygRelayoutVisibleAnimated:YES host:host];
	}];
}

- (void)rygHandleTerminate:(RYGNotifSlot *)slot tone:(RYGNotificationTone)tone title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon {
	[self rygOnMain:^{
		if (!slot || slot.terminal) return;

		// The bare outcome ("Done") has no context in notification centre — the
		// task's running title becomes the notification title, the outcome the body.
		if ([RYGNotificationMirror appIsBackgrounded]) {
			NSString *taskTitle = slot.pill.titleText;
			NSString *outcome = title ?: @"";
			NSString *body = subtitle.length ? [NSString stringWithFormat:@"%@ — %@", outcome, subtitle] : outcome;
			if (!taskTitle.length || [taskTitle isEqualToString:outcome]) { taskTitle = outcome; body = subtitle; }
			[self rygMirrorIfBackgrounded:slot.actionID title:taskTitle subtitle:body onTap:slot.tapBlock];
		}

		slot.terminal = YES;
		[slot.autoDismissTimer invalidate];
		slot.autoDismissTimer = nil;

		slot.pill.showsProgress = NO;
		slot.pill.showsCancelButton = NO;
		slot.pill.onCancel = nil;
		slot.pill.iconSymbolName = icon;

		if (title) slot.pill.titleText = title;
		slot.pill.subtitleText = subtitle;

		[slot.pill applyTone:tone animated:YES];
		[slot.pill refreshSizeAnimated:YES];
		[slot.pill pulseIcon];
		[self rygHapticForTone:tone];

		UIView *host = slot.pill.superview;
		if (host) [self rygRelayoutVisibleAnimated:YES host:host];

		__weak typeof(self) weakSelf = self;
		__weak RYGNotifSlot *weakSlot = slot;
		slot.autoDismissTimer = [NSTimer scheduledTimerWithTimeInterval:kTerminalLinger repeats:NO block:^(__unused NSTimer *timer) {
			RYGNotificationCenter *self = weakSelf;
			RYGNotifSlot *slot = weakSlot;
			if (self && slot) [self rygDismissSlot:slot animated:YES];
		}];
	}];
}

- (void)rygHandleDismiss:(RYGNotifSlot *)slot {
	[self rygOnMain:^{ [self rygDismissSlot:slot animated:YES]; }];
}

@end

// ───── Handle implementation ─────
@implementation RYGNotificationHandle

- (void)setProgress:(float)progress {
	if (self.isFinished) return;
	[self.center rygHandleSetProgress:progress slot:self.slot];
}

- (void)setIndeterminate:(BOOL)indeterminate {
	if (self.isFinished) return;
	[self.center rygHandleSetIndeterminate:indeterminate slot:self.slot];
}

- (void)setTitle:(NSString *)title {
	if (self.isFinished) return;
	[self.center rygHandleSetTitle:title subtitle:self.slot.pill.subtitleText slot:self.slot];
}

- (void)setSubtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	[self.center rygHandleSetTitle:self.slot.pill.titleText subtitle:subtitle slot:self.slot];
}

- (void)success:(NSString *)title {
	[self success:title subtitle:nil];
}

- (void)success:(NSString *)title subtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center rygHandleTerminate:self.slot tone:RYGNotificationToneSuccess title:title ?: RYGLocalized(@"Done") subtitle:subtitle icon:@"checkmark.circle.fill"];
}

- (void)error:(NSString *)title {
	[self error:title subtitle:nil];
}

- (void)error:(NSString *)title subtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center rygHandleTerminate:self.slot tone:RYGNotificationToneError title:title ?: RYGLocalized(@"Failed") subtitle:subtitle icon:@"exclamationmark.triangle.fill"];
}

- (void)cancelled:(NSString *)title {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center rygHandleTerminate:self.slot tone:RYGNotificationToneWarning title:title ?: RYGLocalized(@"Cancelled") subtitle:nil icon:@"xmark.circle.fill"];
}

- (void)dismiss {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center rygHandleDismiss:self.slot];
}

@end

// ───── C convenience ─────
void RYGNotify(NSString *actionID, NSString *title, NSString *subtitle, NSString *iconSymbol, RYGNotificationTone tone) {
	[[RYGNotificationCenter shared] notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone];
}

void RYGNotifySuccess(NSString *actionID, NSString *title, NSString *subtitle) {
	RYGNotify(actionID, title, subtitle, @"checkmark.circle.fill", RYGNotificationToneSuccess);
}

void RYGNotifyInfo(NSString *actionID, NSString *title, NSString *subtitle) {
	RYGNotify(actionID, title, subtitle, @"info.circle.fill", RYGNotificationToneInfo);
}

void RYGNotifyError(NSString *actionID, NSString *title, NSString *message) {
	[[RYGNotificationCenter shared] notifyError:actionID title:title message:message];
}

void RYGNotifyTap(NSString *actionID, NSString *title, NSString *subtitle, NSString *iconSymbol, RYGNotificationTone tone, void (^onTap)(void)) {
	NSTimeInterval base = tone == RYGNotificationToneError ? kErrorToastDuration : kDefaultToastDuration;
	[[RYGNotificationCenter shared] notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:base onTap:onTap];
}

void RYGNotifyWarning(NSString *actionID, NSString *title, NSString *message) {
	RYGNotify(actionID, title, message, @"exclamationmark.circle.fill", RYGNotificationToneWarning);
}

RYGNotificationHandle *RYGNotifyProgress(NSString *actionID, NSString *title, void (^onCancel)(void)) {
	return [[RYGNotificationCenter shared] beginProgressForAction:actionID title:title onCancel:onCancel];
}

RYGNotificationHandle *RYGNotifyLoading(NSString *actionID, NSString *title, void (^onCancel)(void)) {
	return [[RYGNotificationCenter shared] beginLoadingForAction:actionID title:title onCancel:onCancel];
}