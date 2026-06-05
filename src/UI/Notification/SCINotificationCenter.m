#import "SCINotificationCenter.h"
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// ───── Pref keys (mirrored in SCIDefaultsDictionary in SCIDefaults.m) ─────
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

typedef void (^SCINotifTapBlock)(void);
typedef SCINotifTapBlock (^SCINotifTapProvider)(void);

// ───── Surface routing ─────
typedef NS_ENUM(NSUInteger, SCINotifSurface) {
	SCINotifSurfacePill,
	SCINotifSurfaceIGNative,
	SCINotifSurfaceOff,
};

static SCINotifSurface SCINotifSurfaceFromString(NSString *s, SCINotifSurface fallback) {
	if ([s isEqualToString:@"pill"]) return SCINotifSurfacePill;
	if ([s isEqualToString:@"ig_native"]) return SCINotifSurfaceIGNative;
	if ([s isEqualToString:@"off"]) return SCINotifSurfaceOff;
	return fallback;
}

static SCINotificationStyle SCINotifStyleFromString(NSString *s) {
	if ([s isEqualToString:@"colorful"]) return SCINotificationStyleColorful;
	if ([s isEqualToString:@"glow"]) return SCINotificationStyleGlow;
	if ([s isEqualToString:@"island"]) return SCINotificationStyleIsland;
	return SCINotificationStyleMinimal;
}

static SCINotificationPosition SCINotifPositionFromString(NSString *s) {
	return [s isEqualToString:@"bottom"] ? SCINotificationPositionBottom : SCINotificationPositionTop;
}

static inline CGFloat sciPillHeight(SCINotificationPillView *pill) {
	CGFloat h = pill.bounds.size.height;
	return h > 1.0 ? h : 50.0;
}

// ───── Owner-VC presentation walker ─────
static BOOL sci_vcChainContainsClass(UIViewController *vc, Class cls) {
	if (!vc || !cls) return NO;
	if ([vc isKindOfClass:cls]) return YES;
	if (vc.presentedViewController && sci_vcChainContainsClass(vc.presentedViewController, cls)) return YES;

	if ([vc isKindOfClass:UINavigationController.class]) {
		for (UIViewController *child in ((UINavigationController *)vc).viewControllers)
			if (sci_vcChainContainsClass(child, cls)) return YES;
	} else if ([vc isKindOfClass:UITabBarController.class]) {
		for (UIViewController *child in ((UITabBarController *)vc).viewControllers)
			if (sci_vcChainContainsClass(child, cls)) return YES;
	}

	return NO;
}

static BOOL sci_isVCClassInPresentationChain(Class cls) {
	if (!cls) return NO;

	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)scene).windows)
			if (sci_vcChainContainsClass(w.rootViewController, cls)) return YES;
	}

	return sci_vcChainContainsClass(UIApplication.sharedApplication.keyWindow.rootViewController, cls);
}

@interface SCINotifSlot : NSObject
@property (nonatomic, strong) SCINotificationPillView *pill;
@property (nonatomic, strong) NSLayoutConstraint *anchorConstraint;
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, assign) BOOL terminal;
@property (nonatomic, assign) BOOL isProgress;
@property (nonatomic, strong) NSTimer *autoDismissTimer;
@property (nonatomic, weak) SCINotificationHandle *handle;
@end

@implementation SCINotifSlot @end

@interface SCINotifQueueItem : NSObject
@property (nonatomic, copy) NSString *actionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *icon;
@property (nonatomic, assign) SCINotificationTone tone;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, copy) SCINotifTapBlock onTap;
@end

@implementation SCINotifQueueItem @end

@interface SCINotificationHandle ()
@property (nonatomic, copy, readwrite) NSString *actionID;
@property (nonatomic, assign, readwrite) BOOL isFinished;
@property (nonatomic, weak) SCINotifSlot *slot;
@property (nonatomic, weak) SCINotificationCenter *center;
@end

@interface SCINotificationCenter () {
	NSMutableArray<SCINotifSlot *> *_visible;
	NSMutableArray<SCINotifQueueItem *> *_queue;
	NSMutableDictionary<NSString *, id> *_tapProviders;
	NSMutableDictionary<NSString *, Class> *_tapProviderOwners;
	UINotificationFeedbackGenerator *_notifGen;
	UIImpactFeedbackGenerator *_impactGen;
}

- (void)sciHandleSetProgress:(float)progress slot:(SCINotifSlot *)slot;
- (void)sciHandleSetIndeterminate:(BOOL)indeterminate slot:(SCINotifSlot *)slot;
- (void)sciHandleSetTitle:(NSString *)title subtitle:(NSString *)subtitle slot:(SCINotifSlot *)slot;
- (void)sciHandleTerminate:(SCINotifSlot *)slot tone:(SCINotificationTone)tone title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon;
- (void)sciHandleDismiss:(SCINotifSlot *)slot;
- (BOOL)sciInsertSlot:(SCINotifSlot *)slot animated:(BOOL)animated;
@end

@implementation SCINotificationCenter

+ (instancetype)shared {
	static SCINotificationCenter *s;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [SCINotificationCenter new]; });
	return s;
}

- (instancetype)init {
	self = [super init];
	if (!self) return nil;

	_visible = [NSMutableArray new];
	_queue = [NSMutableArray new];
	_tapProviders = [NSMutableDictionary new];
	_tapProviderOwners = [NSMutableDictionary new];

	[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sciAppBackgrounded) name:UIApplicationDidEnterBackgroundNotification object:nil];
	return self;
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - Settings (read fresh per call — no caching)

- (SCINotificationStyle)sciCurrentStyle {
	return SCINotifStyleFromString([SCIUtils getStringPref:kPrefStyle]);
}

- (SCINotificationPosition)sciCurrentPosition {
	return SCINotifPositionFromString([SCIUtils getStringPref:kPrefPosition]);
}

- (BOOL)sciMasterEnabled {
	return [SCIUtils getBoolPref:kPrefMaster];
}

- (BOOL)sciHapticsEnabled {
	return [SCIUtils getBoolPref:kPrefHaptics];
}

- (double)sciDurationMultiplier {
	double d = [SCIUtils getDoublePref:kPrefDuration];
	return d > 0.01 ? d : 1.0;
}

- (NSUInteger)sciMaxVisible {
	double d = [SCIUtils getDoublePref:kPrefMaxVisible];
	NSUInteger n = d > 0.5 ? (NSUInteger)d : 2;
	return MAX(1, MIN(n, kHardMaxVisible));
}

- (SCINotifSurface)sciDefaultSurface {
	return SCINotifSurfaceFromString([SCIUtils getStringPref:kPrefDefaultSurface], SCINotifSurfacePill);
}

- (SCINotifSurface)sciSurfaceForAction:(NSString *)actionID isProgress:(BOOL)isProgress {
	if (![self sciMasterEnabled]) return SCINotifSurfaceOff;

	NSString *key = [kPerActionPrefix stringByAppendingString:actionID ?: @""];
	SCINotifSurface surface = SCINotifSurfaceFromString([SCIUtils getStringPref:key], [self sciDefaultSurface]);

	// IG-native has no progress affordance; fall back to pill.
	if (surface == SCINotifSurfaceIGNative && isProgress) return SCINotifSurfacePill;

	SCINotificationActionInfo *info = SCINotificationActionInfoForID(actionID);
	if (surface == SCINotifSurfaceIGNative && info && !(info.caps & SCINotificationActionCapsAllowIG)) return SCINotifSurfacePill;

	return surface;
}

#pragma mark - Public toast

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(SCINotificationTone)tone {
	NSTimeInterval base = tone == SCINotificationToneError ? kErrorToastDuration : kDefaultToastDuration;
	[self notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:base];
}

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(SCINotificationTone)tone duration:(NSTimeInterval)duration {
	[self notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:nil];
}

- (void)notifyAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)iconSymbol tone:(SCINotificationTone)tone duration:(NSTimeInterval)duration onTap:(void (^)(void))onTap {
	SCINotifSurface surface = [self sciSurfaceForAction:actionID isProgress:NO];
	if (surface == SCINotifSurfaceOff) return;

	SCINotifTapBlock tap = nil;
	if (onTap) tap = [onTap copy];
	else tap = [self sciResolveDefaultTapForAction:actionID];

	if (surface == SCINotifSurfaceIGNative) {
		NSTimeInterval effective = MAX(0.6, duration * [self sciDurationMultiplier]);
		[self sciOnMain:^{ [SCIUtils showIGNativeToastForDuration:effective title:title subtitle:subtitle onTap:tap]; }];
		return;
	}

	[self sciOnMain:^{ [self sciPresentToastForAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:duration onTap:tap]; }];
}

- (void)notifyError:(NSString *)actionID title:(NSString *)title message:(NSString *)message {
	[self notifyAction:actionID title:title subtitle:message icon:@"exclamationmark.triangle.fill" tone:SCINotificationToneError];
}

#pragma mark - Public progress

- (SCINotificationHandle *)beginProgressForAction:(NSString *)actionID title:(NSString *)title onCancel:(void (^)(void))onCancel {
	return [self sciBeginProgressForAction:actionID title:title indeterminate:NO icon:@"arrow.down.to.line" onCancel:onCancel];
}

- (SCINotificationHandle *)beginLoadingForAction:(NSString *)actionID title:(NSString *)title onCancel:(void (^)(void))onCancel {
	return [self sciBeginProgressForAction:actionID title:title indeterminate:YES icon:@"hourglass" onCancel:onCancel];
}

- (SCINotificationHandle *)sciBeginProgressForAction:(NSString *)actionID title:(NSString *)title indeterminate:(BOOL)indeterminate icon:(NSString *)icon onCancel:(void (^)(void))onCancel {
	SCINotifSurface surface = [self sciSurfaceForAction:actionID isProgress:YES];
	if (surface == SCINotifSurfaceOff) return nil;

	SCINotificationHandle *handle = [SCINotificationHandle new];
	handle.actionID = actionID;
	handle.center = self;

	SCINotifTapBlock cancelCopy = [onCancel copy];
	SCINotifTapBlock tap = [self sciResolveDefaultTapForAction:actionID];

	[self sciOnMain:^{
		SCINotifSlot *slot = [self sciCreateSlotForAction:actionID title:title subtitle:nil icon:icon tone:SCINotificationToneInfo isProgress:YES onTap:tap];

		slot.handle = handle;
		slot.pill.showsProgress = YES;
		slot.pill.indeterminate = indeterminate;
		slot.pill.showsCancelButton = cancelCopy != nil;
		slot.pill.onCancel = ^(__unused SCINotificationPillView *pill) {
			if (cancelCopy) cancelCopy();
		};

		handle.slot = slot;
		[slot.pill refreshSizeAnimated:NO];

		if (![self sciInsertSlot:slot animated:YES]) {
			handle.isFinished = YES;
			handle.slot = nil;
		}
	}];

	return handle;
}

#pragma mark - Stack mgmt

- (void)sciPresentToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(SCINotificationTone)tone duration:(NSTimeInterval)duration {
	[self sciPresentToastForAction:actionID title:title subtitle:subtitle icon:icon tone:tone duration:duration onTap:nil];
}

- (void)sciPresentToastForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(SCINotificationTone)tone duration:(NSTimeInterval)duration onTap:(void (^)(void))onTap {
	NSTimeInterval effective = MAX(0.6, duration * [self sciDurationMultiplier]);

	if (_visible.count >= [self sciMaxVisible]) {
		SCINotifQueueItem *item = [SCINotifQueueItem new];
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

	SCINotifSlot *slot = [self sciCreateSlotForAction:actionID title:title subtitle:subtitle icon:icon tone:tone isProgress:NO onTap:onTap];
	[slot.pill refreshSizeAnimated:NO];

	if (![self sciInsertSlot:slot animated:YES]) return;

	__weak typeof(self) weakSelf = self;
	__weak SCINotifSlot *weakSlot = slot;
	slot.autoDismissTimer = [NSTimer scheduledTimerWithTimeInterval:effective repeats:NO block:^(__unused NSTimer *timer) {
		SCINotificationCenter *self = weakSelf;
		SCINotifSlot *slot = weakSlot;
		if (self && slot) [self sciDismissSlot:slot animated:YES];
	}];
}

- (SCINotifSlot *)sciCreateSlotForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(SCINotificationTone)tone isProgress:(BOOL)isProgress {
	return [self sciCreateSlotForAction:actionID title:title subtitle:subtitle icon:icon tone:tone isProgress:isProgress onTap:nil];
}

- (SCINotifSlot *)sciCreateSlotForAction:(NSString *)actionID title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon tone:(SCINotificationTone)tone isProgress:(BOOL)isProgress onTap:(void (^)(void))onTap {
	SCINotificationPillView *pill = [[SCINotificationPillView alloc] initWithStyle:[self sciCurrentStyle] position:[self sciCurrentPosition]];
	pill.titleText = title ?: @"";
	pill.subtitleText = subtitle;
	pill.iconSymbolName = icon;
	[pill applyTone:tone animated:NO];

	SCINotifSlot *slot = [SCINotifSlot new];
	slot.pill = pill;
	slot.actionID = actionID;
	slot.isProgress = isProgress;

	SCINotifTapBlock tapCopy = [onTap copy];
	__weak typeof(self) weakSelf = self;
	__weak SCINotifSlot *weakSlot = slot;

	pill.onTap = ^(__unused SCINotificationPillView *pill) {
		SCINotificationCenter *self = weakSelf;
		SCINotifSlot *slot = weakSlot;
		if (!self || !slot) return;
		if (tapCopy) tapCopy();
		if (!slot.isProgress) [self sciDismissSlot:slot animated:YES];
	};

	pill.onSwipeDismiss = ^(__unused SCINotificationPillView *pill) {
		SCINotificationCenter *self = weakSelf;
		SCINotifSlot *slot = weakSlot;
		if (self && slot) [self sciDismissSlot:slot animated:YES];
	};

	return slot;
}

- (UIView *)sciHostView {
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

- (BOOL)sciInsertSlot:(SCINotifSlot *)slot animated:(BOOL)animated {
	UIView *host = [self sciHostView];
	if (!host || !slot.pill) return NO;

	SCINotificationPillView *pill = slot.pill;
	[host addSubview:pill];
	[pill refreshSizeAnimated:NO];

	BOOL bottom = [self sciCurrentPosition] == SCINotificationPositionBottom;
	CGFloat offset = [self sciOffsetForPosition:bottom slotIndex:_visible.count];

	NSLayoutConstraint *anchor = bottom
		? [pill.bottomAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.bottomAnchor constant:-offset]
		: [pill.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:offset];

	anchor.active = YES;
	[pill.centerXAnchor constraintEqualToAnchor:host.centerXAnchor].active = YES;
	slot.anchorConstraint = anchor;

	[_visible addObject:slot];
	[self sciHapticForTone:pill.tone];
	[host layoutIfNeeded];

	CGFloat slideY = bottom ? kEntranceSlide : -kEntranceSlide;
	pill.alpha = 0.0;
	pill.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(kEntranceScale, kEntranceScale), CGAffineTransformMakeTranslation(0, slideY));

	if (!animated) {
		pill.alpha = 1.0;
		pill.transform = CGAffineTransformIdentity;
		[self sciRelayoutVisibleAnimated:NO host:host];
		return YES;
	}

	[UIView animateWithDuration:kInsertDuration delay:0 usingSpringWithDamping:kInsertDamping initialSpringVelocity:kInsertVelocity options:UIViewAnimationOptionCurveEaseOut animations:^{
		pill.alpha = 1.0;
		pill.transform = CGAffineTransformIdentity;
		[self sciRelayoutVisibleAnimated:NO host:host];
	} completion:nil];

	return YES;
}

- (CGFloat)sciOffsetForPosition:(BOOL)bottom slotIndex:(NSUInteger)idx {
	CGFloat acc = 8.0;
	NSUInteger count = _visible.count;
	NSUInteger n = MIN(idx, count);

	for (NSUInteger i = 0; i < n; i++) {
		NSUInteger index = bottom ? count - 1 - i : i;
		acc += sciPillHeight(_visible[index].pill) + kStackSpacing;
	}

	return acc;
}

- (void)sciRelayoutVisibleAnimated:(BOOL)animated host:(UIView *)host {
	if (!host) return;

	BOOL bottom = [self sciCurrentPosition] == SCINotificationPositionBottom;
	CGFloat acc = 8.0;
	NSUInteger count = _visible.count;

	for (NSUInteger i = 0; i < count; i++) {
		NSUInteger index = bottom ? count - 1 - i : i;
		SCINotifSlot *slot = _visible[index];
		slot.anchorConstraint.constant = bottom ? -acc : acc;
		acc += sciPillHeight(slot.pill) + kStackSpacing;
	}

	if (!animated) return;

	[UIView animateWithDuration:kRelayoutDuration delay:0 usingSpringWithDamping:kRelayoutDamping initialSpringVelocity:kRelayoutVelocity options:UIViewAnimationOptionCurveEaseOut animations:^{
		[host layoutIfNeeded];
	} completion:nil];
}

- (void)sciDismissSlot:(SCINotifSlot *)slot animated:(BOOL)animated {
	if (!slot || ![_visible containsObject:slot]) return;

	[slot.autoDismissTimer invalidate];
	slot.autoDismissTimer = nil;

	SCINotificationPillView *pill = slot.pill;
	UIView *host = pill.superview ?: [self sciHostView];
	BOOL bottom = [self sciCurrentPosition] == SCINotificationPositionBottom;

	void (^cleanup)(void) = ^{
		[pill removeFromSuperview];
		[self->_visible removeObject:slot];
		[self sciRelayoutVisibleAnimated:YES host:host];
		[self sciDrainQueueIfPossible];
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

- (void)sciDrainQueueIfPossible {
	while (_visible.count < [self sciMaxVisible] && _queue.count) {
		SCINotifQueueItem *item = _queue.firstObject;
		[_queue removeObjectAtIndex:0];
		[self sciPresentToastForAction:item.actionID title:item.title subtitle:item.subtitle.length ? item.subtitle : nil icon:item.icon.length ? item.icon : nil tone:item.tone duration:item.duration onTap:item.onTap];
	}
}

- (void)dismissAll {
	[self sciOnMain:^{
		for (SCINotifSlot *slot in self->_visible.copy)
			[self sciDismissSlot:slot animated:NO];

		[self->_queue removeAllObjects];
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
- (SCINotifTapBlock)sciResolveDefaultTapForAction:(NSString *)actionID {
	if (!actionID.length) return nil;

	SCINotifTapProvider provider = nil;
	Class owner = Nil;

	@synchronized (_tapProviders) {
		provider = _tapProviders[actionID];
		owner = _tapProviderOwners[actionID];
	}

	if (!provider) return nil;

	SCINotifTapBlock resolved = provider();
	if (!resolved) return nil;

	SCINotifTapBlock resolvedCopy = [resolved copy];
	if (!owner) return resolvedCopy;

	Class ownerCopy = owner;
	return [^{
		if (sci_isVCClassInPresentationChain(ownerCopy)) return;
		resolvedCopy();
	} copy];
}

- (void)sciAppBackgrounded {
	// Work keeps running in the background, so keep its progress pill — drop only toasts.
	[self sciOnMain:^{
		for (SCINotifSlot *slot in self->_visible.copy) {
			if (slot.isProgress && !slot.terminal) continue;
			[self sciDismissSlot:slot animated:NO];
		}

		[self->_queue removeAllObjects];
	}];
}

#pragma mark - Defaults registration

+ (NSDictionary<NSString *, NSString *> *)defaultPerActionPrefs {
	NSMutableDictionary *m = [NSMutableDictionary new];

	for (SCINotificationActionInfo *info in SCINotificationActionsAll()) {
		if (info.identifier.length)
			m[[kPerActionPrefix stringByAppendingString:info.identifier]] = @"default";
	}

	return m.copy;
}

#pragma mark - Preview

- (void)presentPreviewDownloadEndingWithError:(BOOL)endWithError {
	[self sciOnMain:^{
		SCINotificationHandle *h = [self beginProgressForAction:SCI_NOTIF_DOWNLOAD title:SCILocalized(@"Preview download…") onCancel:nil];
		if (!h) return;

		NSArray<NSNumber *> *steps = @[@0.25, @0.55, @0.80, @1.00];

		for (NSUInteger i = 0; i < steps.count; i++) {
			float p = steps[i].floatValue;
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.5 + i * 0.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[h setProgress:p];
			});
		}

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (endWithError) [h error:SCILocalized(@"Download failed") subtitle:SCILocalized(@"Tap to retry")];
			else [h success:SCILocalized(@"Saved") subtitle:SCILocalized(@"Saved to Photos")];
		});
	}];
}

- (void)presentPreviewLoadingEndingWithError:(BOOL)endWithError {
	[self sciOnMain:^{
		SCINotificationHandle *h = [self beginLoadingForAction:SCI_NOTIF_GENERIC title:[SCILocalized(@"Loading") stringByAppendingString:@"…"] onCancel:nil];
		if (!h) return;

		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (endWithError) [h error:SCILocalized(@"Failed") subtitle:nil];
			else [h success:SCILocalized(@"Done") subtitle:nil];
		});
	}];
}

- (void)presentPreviewWithTone:(SCINotificationTone)tone {
	NSString *title = nil, *subtitle = nil, *icon = nil;

	switch (tone) {
		case SCINotificationToneSuccess:
			title = SCILocalized(@"Success preview");
			subtitle = SCILocalized(@"Looks great");
			icon = @"checkmark.circle.fill";
			break;
		case SCINotificationToneError:
			title = SCILocalized(@"Error preview");
			subtitle = SCILocalized(@"Something broke");
			icon = @"exclamationmark.triangle.fill";
			break;
		case SCINotificationToneWarning:
			title = SCILocalized(@"Warning preview");
			subtitle = SCILocalized(@"Heads up");
			icon = @"exclamationmark.circle.fill";
			break;
		case SCINotificationToneInfo:
		default:
			title = SCILocalized(@"Info preview");
			subtitle = SCILocalized(@"Just so you know");
			icon = @"info.circle.fill";
			break;
	}

	// Bypass routing — preview must always show our pill.
	[self sciOnMain:^{ [self sciPresentToastForAction:SCI_NOTIF_GENERIC title:title subtitle:subtitle icon:icon tone:tone duration:2.0]; }];
}

#pragma mark - Haptics

- (void)sciHapticForTone:(SCINotificationTone)tone {
	if (![self sciHapticsEnabled]) return;

	if (tone == SCINotificationToneSuccess || tone == SCINotificationToneError) {
		if (!_notifGen) _notifGen = [UINotificationFeedbackGenerator new];
		[_notifGen notificationOccurred:tone == SCINotificationToneSuccess ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
		return;
	}

	if (!_impactGen) _impactGen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
	[_impactGen impactOccurred];
}

#pragma mark - Threading

- (void)sciOnMain:(dispatch_block_t)block {
	if (!block) return;
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - Handle bridging

- (void)sciHandleSetProgress:(float)progress slot:(SCINotifSlot *)slot {
	[self sciOnMain:^{
		if (!slot || slot.terminal) return;
		[slot.pill setProgress:progress animated:YES];
	}];
}

- (void)sciHandleSetIndeterminate:(BOOL)indeterminate slot:(SCINotifSlot *)slot {
	[self sciOnMain:^{
		if (!slot || slot.terminal) return;
		slot.pill.indeterminate = indeterminate;
	}];
}

- (void)sciHandleSetTitle:(NSString *)title subtitle:(NSString *)subtitle slot:(SCINotifSlot *)slot {
	[self sciOnMain:^{
		if (!slot || slot.terminal) return;

		if (title) slot.pill.titleText = title;
		slot.pill.subtitleText = subtitle;
		[slot.pill refreshSizeAnimated:YES];

		UIView *host = slot.pill.superview;
		if (host) [self sciRelayoutVisibleAnimated:YES host:host];
	}];
}

- (void)sciHandleTerminate:(SCINotifSlot *)slot tone:(SCINotificationTone)tone title:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon {
	[self sciOnMain:^{
		if (!slot || slot.terminal) return;

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
		[self sciHapticForTone:tone];

		UIView *host = slot.pill.superview;
		if (host) [self sciRelayoutVisibleAnimated:YES host:host];

		__weak typeof(self) weakSelf = self;
		__weak SCINotifSlot *weakSlot = slot;
		slot.autoDismissTimer = [NSTimer scheduledTimerWithTimeInterval:kTerminalLinger repeats:NO block:^(__unused NSTimer *timer) {
			SCINotificationCenter *self = weakSelf;
			SCINotifSlot *slot = weakSlot;
			if (self && slot) [self sciDismissSlot:slot animated:YES];
		}];
	}];
}

- (void)sciHandleDismiss:(SCINotifSlot *)slot {
	[self sciOnMain:^{ [self sciDismissSlot:slot animated:YES]; }];
}

@end

// ───── Handle implementation ─────
@implementation SCINotificationHandle

- (void)setProgress:(float)progress {
	if (self.isFinished) return;
	[self.center sciHandleSetProgress:progress slot:self.slot];
}

- (void)setIndeterminate:(BOOL)indeterminate {
	if (self.isFinished) return;
	[self.center sciHandleSetIndeterminate:indeterminate slot:self.slot];
}

- (void)setTitle:(NSString *)title {
	if (self.isFinished) return;
	[self.center sciHandleSetTitle:title subtitle:self.slot.pill.subtitleText slot:self.slot];
}

- (void)setSubtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	[self.center sciHandleSetTitle:self.slot.pill.titleText subtitle:subtitle slot:self.slot];
}

- (void)success:(NSString *)title {
	[self success:title subtitle:nil];
}

- (void)success:(NSString *)title subtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center sciHandleTerminate:self.slot tone:SCINotificationToneSuccess title:title ?: SCILocalized(@"Done") subtitle:subtitle icon:@"checkmark.circle.fill"];
}

- (void)error:(NSString *)title {
	[self error:title subtitle:nil];
}

- (void)error:(NSString *)title subtitle:(NSString *)subtitle {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center sciHandleTerminate:self.slot tone:SCINotificationToneError title:title ?: SCILocalized(@"Failed") subtitle:subtitle icon:@"exclamationmark.triangle.fill"];
}

- (void)cancelled:(NSString *)title {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center sciHandleTerminate:self.slot tone:SCINotificationToneWarning title:title ?: SCILocalized(@"Cancelled") subtitle:nil icon:@"xmark.circle.fill"];
}

- (void)dismiss {
	if (self.isFinished) return;
	self.isFinished = YES;
	[self.center sciHandleDismiss:self.slot];
}

@end

// ───── C convenience ─────
void SCINotify(NSString *actionID, NSString *title, NSString *subtitle, NSString *iconSymbol, SCINotificationTone tone) {
	[[SCINotificationCenter shared] notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone];
}

void SCINotifySuccess(NSString *actionID, NSString *title, NSString *subtitle) {
	SCINotify(actionID, title, subtitle, @"checkmark.circle.fill", SCINotificationToneSuccess);
}

void SCINotifyInfo(NSString *actionID, NSString *title, NSString *subtitle) {
	SCINotify(actionID, title, subtitle, @"info.circle.fill", SCINotificationToneInfo);
}

void SCINotifyError(NSString *actionID, NSString *title, NSString *message) {
	[[SCINotificationCenter shared] notifyError:actionID title:title message:message];
}

void SCINotifyTap(NSString *actionID, NSString *title, NSString *subtitle, NSString *iconSymbol, SCINotificationTone tone, void (^onTap)(void)) {
	NSTimeInterval base = tone == SCINotificationToneError ? kErrorToastDuration : kDefaultToastDuration;
	[[SCINotificationCenter shared] notifyAction:actionID title:title subtitle:subtitle icon:iconSymbol tone:tone duration:base onTap:onTap];
}

void SCINotifyWarning(NSString *actionID, NSString *title, NSString *message) {
	SCINotify(actionID, title, message, @"exclamationmark.circle.fill", SCINotificationToneWarning);
}

SCINotificationHandle *SCINotifyProgress(NSString *actionID, NSString *title, void (^onCancel)(void)) {
	return [[SCINotificationCenter shared] beginProgressForAction:actionID title:title onCancel:onCancel];
}

SCINotificationHandle *SCINotifyLoading(NSString *actionID, NSString *title, void (^onCancel)(void)) {
	return [[SCINotificationCenter shared] beginLoadingForAction:actionID title:title onCancel:onCancel];
}