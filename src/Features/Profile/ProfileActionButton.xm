// Profile action button — SCIChromeButton positioned next to the native nav cluster.
// Own profile  -> RIGHT of plus.
// Other profile -> LEFT of right-side cluster.
// Icon follows SCIActionIcon profile/global override.

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIIcon.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../ActionButton/SCIActionCatalog.h"
#import "../../ActionButton/SCIActionIcon.h"
#import "SCIProfileHelpers.h"

// Route to the debug console if its module is built in, else the device console.
// Resolved at runtime so there's no link dependency when it's disabled.
static void sciPBLog(NSString *body) {
	static void (*dbg)(NSString *, NSString *, ...) = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ dbg = (void (*)(NSString *, NSString *, ...))dlsym(RTLD_DEFAULT, "SCIDebugLog"); });

	if (dbg) dbg(@"ProfileBtn", @"%@", body);
}
#define SCIPBLog(fmt, ...) sciPBLog([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static NSString * const kSCIProfileButtonID = @"sci-profile-action-button";

static CGFloat const kSize = 32.0;
static CGFloat const kIcon = 18.0;
static CGFloat const kGap = 8.0;

static const void *kBtnKey = &kBtnKey;
static const void *kHitKey = &kHitKey;
static const void *kWireKey = &kWireKey;
static const void *kIconKey = &kIconKey;
static const void *kOwnKey = &kOwnKey;
static const void *kSideKey = &kSideKey;       // cached SCISide
static const void *kTargetKey = &kTargetKey;   // last applied frame
static const void *kSideWarnKey = &kSideWarnKey; // dedup the side-fallback log
static const void *kSkipKey = &kSkipKey;       // dedup repeated skip-reason logs
static const void *kPKKey = &kPKKey;           // last user PK seen on a container (variant-B reuse)
static const void *kChainKey = &kChainKey;     // dedup the variant-B superview-chain log
static const void *kNavDiagKey = &kNavDiagKey; // dedup the nav-bar "no user" diagnostic

static NSInteger sciVersion = 0;

typedef NS_ENUM(NSInteger, SCISide) {
	SCISideLeft,
	SCISideRight
};

static Class sciHeaderViewClass(void);
static UIView *sciFindDescendantOfClass(UIView *root, Class cls);
static BOOL sciHostHasNativeButton(UIView *host);

#pragma mark - Runtime

static id sciCall(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

static id sciValue(id obj, NSString *key) {
	if (!obj || !key.length) return nil;

	@try {
		return [obj valueForKey:key];
	} @catch (__unused NSException *e) {
		return nil;
	}
}

static Class sciNativeClass(void) {
	return objc_getClass("_TtC19IGProfileNavigation24IGBadgedNavigationButton") ?:
		objc_getClass("IGProfileNavigation.IGBadgedNavigationButton");
}

static BOOL sciIsNativeNavButton(UIView *view) {
	if (!view) return NO;

	Class badged = sciNativeClass();
	Class nav = objc_getClass("_TtC14IGProfileUtils25IGNavigationBarButtonView");

	return (badged && [view isKindOfClass:badged]) || (nav && [view isKindOfClass:nav]);
}

static BOOL sciUsableView(UIView *view) {
	return view &&
		view.superview &&
		!view.hidden &&
		view.alpha > 0.01 &&
		!CGRectIsEmpty(view.bounds) &&
		![view.accessibilityIdentifier isEqualToString:kSCIProfileButtonID];
}

static UIView *sciWrapperView(id obj) {
	if ([obj isKindOfClass:UIView.class]) return obj;

	UIView *view = sciCall(obj, @selector(view));
	if (![view isKindOfClass:UIView.class]) view = sciValue(obj, @"view");

	return [view isKindOfClass:UIView.class] ? view : nil;
}

#pragma mark - Headers

static NSHashTable<UIView *> *sciHeaders(void) {
	static NSHashTable<UIView *> *headers;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		headers = [NSHashTable weakObjectsHashTable];
	});

	return headers;
}

#pragma mark - User

static id sciUserForView(UIView *view) {
	id user = [SCIProfileHelpers userForView:view];
	if (user) return user;

	UIViewController *vc = [SCIUtils nearestViewControllerForView:view];

	user = sciCall(vc, @selector(user));
	if (user) return user;

	id context = sciCall(vc, @selector(context));
	id config = sciCall(context, @selector(configuration));
	id ref = sciCall(config, @selector(userReference));

	return ref ?: sciCall(sciCall(context, @selector(dataManager)), @selector(userReference));
}

static NSString *sciLogID(UIView *header) {
	id user = sciUserForView(header);
	NSString *uname = user ? [SCIProfileHelpers usernameForUser:user] : nil;
	NSString *pk = user ? [SCIProfileHelpers pkForUser:user] : nil;
	return [NSString stringWithFormat:@"user=%@ pk=%@ hdr=%p", uname.length ? uname : @"<nil>", pk.length ? pk : @"<nil>", header];
}

static BOOL sciIsOwnProfile(UIView *header) {
	id user = sciUserForView(header);
	NSString *pk = user ? [SCIProfileHelpers pkForUser:user] : nil;
	NSString *me = [SCIUtils currentUserPK];

	if (pk.length && me.length) return [pk isEqualToString:me];

	return [objc_getAssociatedObject(header, kOwnKey) boolValue];
}

#pragma mark - Copy

static BOOL sciIsCopyAction(NSString *aid) {
	return [aid isEqualToString:SCIAID_CopyID] ||
		[aid isEqualToString:SCIAID_CopyUsername] ||
		[aid isEqualToString:SCIAID_CopyName] ||
		[aid isEqualToString:SCIAID_CopyBio] ||
		[aid isEqualToString:SCIAID_CopyLink] ||
		[aid isEqualToString:SCIAID_CopyAll];
}

static void sciCopy(NSString *value, NSString *kind) {
	if (!value.length) {
		SCINotifyWarning(SCI_NOTIF_VALIDATION_ERROR, SCILocalized(@"Nothing to copy"), nil);
		return;
	}

	UIPasteboard.generalPasteboard.string = value;
	SCINotifySuccess(SCI_NOTIF_COPY_PROFILE, [NSString stringWithFormat:SCILocalized(@"Copied %@"), kind], nil);
}

static NSString *sciAllInfo(id user) {
	NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:5];

	NSString *username = [SCIProfileHelpers usernameForUser:user];
	NSString *name = [SCIProfileHelpers fullNameForUser:user];
	NSString *bio = [SCIProfileHelpers biographyForUser:user];
	NSString *link = [SCIProfileHelpers profileLinkForUser:user].absoluteString;
	NSString *pk = [SCIProfileHelpers pkForUser:user];

	if (username.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", SCILocalized(@"Username"), username]];
	if (name.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", SCILocalized(@"Name"), name]];
	if (bio.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", SCILocalized(@"Bio"), bio]];
	if (link.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", SCILocalized(@"Profile link"), link]];
	if (pk.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", SCILocalized(@"ID"), pk]];

	return [lines componentsJoinedByString:@"\n"];
}

static void sciRunCopy(id user, NSString *aid) {
	if ([aid isEqualToString:SCIAID_CopyID]) {
		sciCopy([SCIProfileHelpers pkForUser:user], SCILocalized(@"ID"));
	} else if ([aid isEqualToString:SCIAID_CopyUsername]) {
		sciCopy([SCIProfileHelpers usernameForUser:user], SCILocalized(@"Username"));
	} else if ([aid isEqualToString:SCIAID_CopyName]) {
		sciCopy([SCIProfileHelpers fullNameForUser:user], SCILocalized(@"Name"));
	} else if ([aid isEqualToString:SCIAID_CopyBio]) {
		sciCopy([SCIProfileHelpers biographyForUser:user], SCILocalized(@"Bio"));
	} else if ([aid isEqualToString:SCIAID_CopyLink]) {
		sciCopy([SCIProfileHelpers profileLinkForUser:user].absoluteString, SCILocalized(@"Profile link"));
	} else if ([aid isEqualToString:SCIAID_CopyAll]) {
		sciCopy(sciAllInfo(user), SCILocalized(@"Profile info"));
	}
}

#pragma mark - Settings

static void sciOpenSettings(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (!window.isKeyWindow) continue;

			[SCIUtils showSettingsVC:window atTopLevelEntry:SCILocalized(@"Profile")];
			return;
		}
	}
}

#pragma mark - Menu

static NSString *sciDecimal(NSNumber *number) {
	if (!number) return nil;

	static NSNumberFormatter *formatter;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		formatter = [NSNumberFormatter new];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
	});

	return [formatter stringFromNumber:number];
}

static SCIAction *sciActionForUser(id user, NSString *aid) {
	if (sciIsCopyAction(aid)) {
		SCIActionDescriptor *d = [SCIActionCatalog descriptorForActionID:aid source:SCIActionSourceProfile];
		return d ? [SCIAction actionWithTitle:d.title icon:d.iconSF handler:^{ sciRunCopy(user, aid); }] : nil;
	}

	if ([aid isEqualToString:SCIAID_ViewPicture]) {
		return [SCIAction actionWithTitle:SCILocalized(@"View picture") icon:@"photo" handler:^{ [SCIProfileHelpers viewPictureForUser:user]; }];
	}

	if ([aid isEqualToString:SCIAID_SharePicture]) {
		return [SCIAction actionWithTitle:SCILocalized(@"Share picture") icon:@"square.and.arrow.up" handler:^{ [SCIProfileHelpers sharePictureForUser:user]; }];
	}

	if ([aid isEqualToString:SCIAID_SavePicturePhotos]) {
		return [SCIAction actionWithTitle:SCILocalized(@"Save to Photos") icon:@"square.and.arrow.down" handler:^{ [SCIProfileHelpers savePictureForUser:user]; }];
	}

	if ([aid isEqualToString:SCIAID_SavePictureGallery]) {
		if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;

		return [SCIAction actionWithTitle:SCILocalized(@"Save picture to Gallery") icon:@"photo.on.rectangle.angled" handler:^{
			[SCIProfileHelpers savePictureToGalleryForUser:user];
		}];
	}

	if ([aid isEqualToString:SCIAID_ProfileSettings]) {
		return [SCIAction actionWithTitle:SCILocalized(@"Profile settings") icon:@"gearshape" handler:^{
			sciOpenSettings();
		}];
	}

	if ([aid isEqualToString:SCIAID_ProfileInfoPrivacy]) {
		NSNumber *status = [SCIProfileHelpers privacyStatusForUser:user];
		if (!status) return nil;

		BOOL priv = status.integerValue == 2;
		return [SCIAction infoRowWithTitle:(priv ? SCILocalized(@"Private profile") : SCILocalized(@"Public profile")) icon:(priv ? @"lock" : @"lock.open")];
	}

	if ([aid isEqualToString:SCIAID_ProfileInfoFollowers]) {
		NSString *count = sciDecimal([SCIProfileHelpers followerCountForUser:user]);
		return count.length ? [SCIAction infoRowWithTitle:[NSString stringWithFormat:SCILocalized(@"Followers: %@"), count] icon:@"person.2"] : nil;
	}

	if ([aid isEqualToString:SCIAID_ProfileInfoFollowing]) {
		NSString *count = sciDecimal([SCIProfileHelpers followingCountForUser:user]);
		return count.length ? [SCIAction infoRowWithTitle:[NSString stringWithFormat:SCILocalized(@"Following: %@"), count] icon:@"person.crop.circle.badge.plus"] : nil;
	}

	return nil;
}

static UIMenu *sciMenuForUser(id user) {
	if (!user) {
		SCIAction *action = [SCIAction actionWithTitle:SCILocalized(@"Profile unavailable") icon:nil handler:^{}];
		return [SCIActionMenu buildMenuWithActions:@[action]];
	}

	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];

	SCIAction *(^resolver)(NSString *) = ^SCIAction *(NSString *aid) {
		return sciActionForUser(user, aid);
	};

	return [SCIActionMenu buildMenuWithActions:[SCIActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolver]];
}

static UIMenu *sciDeferredMenu(UIView *view) {
	__weak UIView *weakView = view;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithProvider:^(void (^done)(NSArray<UIMenuElement *> *)) {
		done(sciMenuForUser(sciUserForView(weakView)).children ?: @[]);
	}];

	return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

static void sciRunTap(id user, SCIActionMenuConfig *cfg) {
	if (!user) return;

	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	if ([tap isEqualToString:@"menu"]) return;

	if ([tap isEqualToString:SCIAID_ViewPicture]) {
		[SCIProfileHelpers viewPictureForUser:user];
	} else if ([tap isEqualToString:SCIAID_SharePicture]) {
		[SCIProfileHelpers sharePictureForUser:user];
	} else if ([tap isEqualToString:SCIAID_SavePicturePhotos]) {
		[SCIProfileHelpers savePictureForUser:user];
	} else if ([tap isEqualToString:SCIAID_SavePictureGallery]) {
		if ([SCIUtils getBoolPref:@"sci_gallery_enabled"]) [SCIProfileHelpers savePictureToGalleryForUser:user];
	} else if ([tap isEqualToString:SCIAID_ProfileSettings]) {
		sciOpenSettings();
	} else if (sciIsCopyAction(tap)) {
		sciRunCopy(user, tap);
	}
}

// Shared tap target — the host may be a nav bar with no tap selector, so resolve
// the user from the sender rather than targeting the host.
@interface SCIProfileTapTarget : NSObject
@end

@implementation SCIProfileTapTarget
+ (instancetype)shared {
	static SCIProfileTapTarget *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [SCIProfileTapTarget new]; });
	return shared;
}
- (void)tapped:(id)sender {
	UIView *view = [sender isKindOfClass:UIView.class] ? sender : nil;
	sciRunTap(sciUserForView(view), [SCIActionMenuConfig configForSource:SCIActionSourceProfile]);
}
@end

#pragma mark - Icon

static NSString *sciSymbol(void) {
	NSString *symbol = [SCIActionIcon effectiveSymbolNameForSource:SCIActionSourceProfile];
	return symbol.length ? symbol : SCIActionIconDefaultName;
}

static void sciApplyIcon(UIView *native) {
	NSString *symbol = sciSymbol();
	if ([objc_getAssociatedObject(native, kIconKey) isEqualToString:symbol]) return;

	if ([native isKindOfClass:SCIChromeButton.class]) {
		SCIChromeButton *chrome = (SCIChromeButton *)native;
		chrome.symbolName = symbol;
		chrome.iconTint = UIColor.labelColor;
	}

	objc_setAssociatedObject(native, kIconKey, symbol, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Button

static UIView *sciButton(UIView *header) {
	UIView *button = objc_getAssociatedObject(header, kBtnKey);
	if (button) return button;

	SCIChromeButton *chrome = [[SCIChromeButton alloc] initWithSymbol:sciSymbol() pointSize:kIcon diameter:kSize];
	chrome.translatesAutoresizingMaskIntoConstraints = YES;
	chrome.bubbleColor = UIColor.clearColor;
	chrome.iconTint = UIColor.labelColor;
	chrome.userInteractionEnabled = NO;
	chrome.hidden = YES;
	chrome.accessibilityIdentifier = kSCIProfileButtonID;
	chrome.accessibilityLabel = SCILocalized(@"RyukGram profile actions");

	button = chrome;
	objc_setAssociatedObject(header, kBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return button;
}

static UIButton *sciHit(UIView *header) {
	UIButton *hit = objc_getAssociatedObject(header, kHitKey);
	if (hit) return hit;

	hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.backgroundColor = UIColor.clearColor;
	hit.translatesAutoresizingMaskIntoConstraints = YES;
	hit.adjustsImageWhenHighlighted = NO;
	hit.hidden = YES;
	hit.accessibilityLabel = SCILocalized(@"RyukGram profile actions");
	hit.accessibilityIdentifier = kSCIProfileButtonID;   // excluded from the anchor scan

	objc_setAssociatedObject(header, kHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return hit;
}

static void sciWire(UIView *header, UIButton *hit) {
	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	NSString *key = [NSString stringWithFormat:@"%@|%ld", tap, (long)sciVersion];

	if ([objc_getAssociatedObject(hit, kWireKey) isEqualToString:key]) return;

	[hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	// Always attach the menu (long-press); a direct tap just drops primary-action.
	hit.menu = sciDeferredMenu(header);

	if ([tap isEqualToString:@"menu"]) {
		hit.showsMenuAsPrimaryAction = YES;
	} else {
		hit.showsMenuAsPrimaryAction = NO;
		[hit addTarget:[SCIProfileTapTarget shared] action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
	}

	objc_setAssociatedObject(hit, kWireKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Anchor

static void sciConsiderAnchor(UIView *header, UIView *view, SCISide side, UIView **best, CGFloat *bestX) {
	if (!sciUsableView(view)) return;

	CGFloat width = CGRectGetWidth(header.bounds);
	CGRect frame = [view.superview convertRect:view.frame toView:header];

	if (side == SCISideLeft) {
		if (width > 0.0 && CGRectGetMinX(frame) > width * 0.6) return;

		CGFloat x = CGRectGetMaxX(frame);
		if (x > *bestX) {
			*bestX = x;
			*best = view;
		}
	} else {
		if (width > 0.0 && CGRectGetMaxX(frame) < width * 0.4) return;

		CGFloat x = CGRectGetMinX(frame);
		if (x < *bestX) {
			*bestX = x;
			*best = view;
		}
	}
}

// Right cluster can hold non-native controls (e.g. the "Follow" pill) we must
// clear, so count any control there as an anchor — not just the native nav classes.
static BOOL sciIsAnchorCandidate(UIView *view, SCISide side) {
	if ([view.accessibilityIdentifier isEqualToString:kSCIProfileButtonID]) return NO;
	if (sciIsNativeNavButton(view)) return YES;
	return side == SCISideRight && [view isKindOfClass:UIControl.class];
}

static void sciScanAnchors(UIView *header, UIView *root, SCISide side, UIView **best, CGFloat *bestX) {
	for (UIView *sub in root.subviews) {
		if (sciIsAnchorCandidate(sub, side)) sciConsiderAnchor(header, sub, side, best, bestX);
		sciScanAnchors(header, sub, side, best, bestX);
	}
}

static UIView *sciAnchor(UIView *header, SCISide side) {
	UIView *best = nil;
	CGFloat bestX = (side == SCISideLeft) ? -CGFLOAT_MAX : CGFLOAT_MAX;

	NSArray *buttons = sciValue(header, side == SCISideLeft ? @"leftButtons" : @"rightButtons");
	if ([buttons isKindOfClass:NSArray.class]) {
		for (id wrapper in buttons) {
			sciConsiderAnchor(header, sciWrapperView(wrapper), side, &best, &bestX);
		}
	}

	if (!best) sciScanAnchors(header, header, side, &best, &bestX);

	return best;
}

static SCISide sciSideFor(UIView *header) {
	NSNumber *cached = objc_getAssociatedObject(header, kSideKey);
	if (cached) return (SCISide)cached.integerValue;

	id user = sciUserForView(header);
	NSString *pk = user ? [SCIProfileHelpers pkForUser:user] : nil;
	NSString *me = [SCIUtils currentUserPK];

	// Cache only once the PK is known; the titleIsCentered fallback can be wrong early.
	if (pk.length && me.length) {
		SCISide side = [pk isEqualToString:me] ? SCISideLeft : SCISideRight;
		objc_setAssociatedObject(header, kSideKey, @(side), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return side;
	}

	BOOL centered = [objc_getAssociatedObject(header, kOwnKey) boolValue];
	if (![objc_getAssociatedObject(header, kSideWarnKey) boolValue]) {
		objc_setAssociatedObject(header, kSideWarnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		SCIPBLog(@"side FALLBACK: pk/me unresolved (pk=%@ me=%@) using titleIsCentered=%d — hdr=%p", pk.length ? pk : @"<nil>", me.length ? me : @"<nil>", centered, header);
	}
	return centered ? SCISideLeft : SCISideRight;
}

static void sciInvalidate(UIView *header) {
	objc_setAssociatedObject(header, kSideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kSideWarnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kSkipKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Layout

static void sciRemove(UIView *header) {
	[(UIView *)objc_getAssociatedObject(header, kBtnKey) removeFromSuperview];
	[(UIView *)objc_getAssociatedObject(header, kHitKey) removeFromSuperview];
	objc_setAssociatedObject(header, kBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	sciInvalidate(header);
}

// Re-scan each pass — the leftmost right-cluster element can change as pills appear.
static UIView *sciResolveAnchor(UIView *header, SCISide side) {
	return sciAnchor(header, side);
}

// Dedup skip reasons — layoutSubviews fires constantly.
static void sciLogSkip(UIView *header, NSString *reason) {
	if ([objc_getAssociatedObject(header, kSkipKey) isEqualToString:reason]) return;
	objc_setAssociatedObject(header, kSkipKey, reason, OBJC_ASSOCIATION_COPY_NONATOMIC);
	SCIPBLog(@"layout SKIP: %@ — %@", reason, sciLogID(header));
}

static void sciLayout(UIView *header) {
	if (![header isKindOfClass:UIView.class]) return;

	BOOL enabled = [SCIUtils getBoolPref:@"action_button_profile_enabled"];
	if (!enabled) {
		sciLogSkip(header, @"pref action_button_profile_enabled=OFF");
		if (objc_getAssociatedObject(header, kBtnKey)) sciRemove(header);
		return;
	}

	Class headerCls = sciHeaderViewClass();

	UIView *button = sciButton(header);
	UIButton *hit = sciHit(header);
	if (!button || !hit) {
		sciLogSkip(header, [NSString stringWithFormat:@"button=%p hit=%p nil", button, hit]);
		return;
	}

	BOOL reparented = NO;
	if (button.superview != header) { [button removeFromSuperview]; [header addSubview:button]; reparented = YES; }
	if (hit.superview != header) { [hit removeFromSuperview]; [header addSubview:hit]; reparented = YES; }

	// Fresh attach may be a recycled header on a different profile — re-resolve side.
	if (reparented) {
		objc_setAssociatedObject(header, kSideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(header, kTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	sciApplyIcon(button);
	sciWire(header, hit);

	CGFloat width = CGRectGetWidth(header.bounds);
	CGFloat height = CGRectGetHeight(header.bounds);

	if (width < 60.0 || height < 20.0) {
		sciLogSkip(header, [NSString stringWithFormat:@"header too small w=%.1f h=%.1f", width, height]);
		return;
	}

	// Header view can place early off titleIsCentered; other hosts need a resolved
	// user, else we'd paint a stray button on whatever nav bar is on screen.
	BOOL isHeaderHost = headerCls && [header isKindOfClass:headerCls];
	if (!isHeaderHost && !sciUserForView(header)) {
		sciLogSkip(header, @"non-header host without a resolved user");
		return;
	}

	SCISide side = sciSideFor(header);
	UIView *anchor = sciResolveAnchor(header, side);

	CGFloat x, y;

	if (anchor) {
		CGRect frame = [anchor.superview convertRect:anchor.frame toView:header];
		y = floor(CGRectGetMidY(frame) - kSize * 0.5);
		x = side == SCISideLeft ? CGRectGetMaxX(frame) + kGap : CGRectGetMinX(frame) - kGap - kSize;
	} else {
		NSValue *placed = objc_getAssociatedObject(header, kTargetKey);
		if (placed && !button.hidden && !reparented) return;   // hold position; don't bounce to the band on a transient anchor miss

		// First placement with no anchor — pin to the nav-bar band.
		CGFloat band = header.safeAreaInsets.top + (44.0 - kSize) * 0.5;
		y = floor(band);
		x = side == SCISideLeft ? kGap + 4.0 : width - kSize - 8.0;
	}

	x = MAX(4.0, MIN(x, width - kSize - 4.0));
	y = MAX(0.0, MIN(y, height - kSize));

	CGRect target = CGRectMake(x, y, kSize, kSize);

	NSValue *last = objc_getAssociatedObject(header, kTargetKey);
	if (!reparented && !button.hidden && last && CGRectEqualToRect(last.CGRectValue, target)) return;

	SCIPBLog(@"layout SHOW: side=%@ anchor=%@ target=%@ clipped=%d icon=%@ hdr=%.0fx%.0f safeTop=%.1f reparented=%d — %@",
		side == SCISideLeft ? @"L" : @"R",
		anchor ? NSStringFromClass(anchor.class) : @"<none/band>",
		NSStringFromCGRect(target),
		(x <= 4.0 || x >= width - kSize - 4.0 || y <= 0.0 || y >= height - kSize),
		sciSymbol(), width, height, header.safeAreaInsets.top, reparented, sciLogID(header));

	objc_setAssociatedObject(header, kSkipKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);

	button.hidden = NO;
	button.alpha = 1.0;
	button.frame = target;

	hit.hidden = NO;
	hit.frame = target;

	[header bringSubviewToFront:button];
	[header bringSubviewToFront:hit];

	objc_setAssociatedObject(header, kTargetKey, [NSValue valueWithCGRect:target], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void sciRefresh(void) {
	sciVersion++;

	for (UIView *header in sciHeaders().allObjects) {
		if (!header.superview) continue;

		objc_setAssociatedObject(objc_getAssociatedObject(header, kHitKey), kWireKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(objc_getAssociatedObject(header, kBtnKey), kIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		sciLayout(header);
	}
}

#pragma mark - Hook

%hook _TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView

- (void)configureWithTitleView:(id)titleView leftButtons:(id)leftButtons rightButtons:(id)rightButtons titleIsCentered:(BOOL)titleIsCentered {
	%orig;

	UIView *header = (UIView *)self;
	if (![header isKindOfClass:UIView.class]) return;

	objc_setAssociatedObject(header, kOwnKey, @(titleIsCentered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[sciHeaders() addObject:header];
	sciInvalidate(header);

	dispatch_async(dispatch_get_main_queue(), ^{
		sciLayout(header);
	});
}

- (void)layoutSubviews {
	%orig;

	UIView *header = (UIView *)self;
	if (![header isKindOfClass:UIView.class]) return;

	// configure: is bypassed by IG's Swift dispatch, so register for refresh here.
	[sciHeaders() addObject:header];
	sciLayout(header);
}

%end

#pragma mark - Variant B (classic nav surface)

// A/B variant: some accounts show other-user profiles in a plain UINavigationBar
// instead of the header view, so the hook above never fires. Anchor off the one
// class common to both: the native badged nav button.

static Class sciHeaderViewClass(void) {
	return objc_getClass("_TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView");
}

// Walk up from a native nav button to the host to inject into. *variantA marks
// the header-view case (handled above) so we don't double-inject.
static UIView *sciHostForNavButton(UIView *button, BOOL *variantA) {
	*variantA = NO;
	Class headerCls = sciHeaderViewClass();

	UIView *navBar = nil;
	UIView *widest = nil;
	CGFloat widestW = 0.0;

	UIView *v = button.superview;
	for (int depth = 0; v && depth < 14; v = v.superview, depth++) {
		if (headerCls && [v isKindOfClass:headerCls]) { *variantA = YES; return v; }
		if ([v isKindOfClass:UINavigationBar.class] && !navBar) navBar = v;

		CGFloat w = CGRectGetWidth(v.bounds);
		if (w > widestW && CGRectGetHeight(v.bounds) <= 120.0) { widestW = w; widest = v; }
	}

	// Prefer the nav bar; else the widest shallow ancestor (the nav band).
	return navBar ?: widest ?: button.superview;
}

static void sciLogChainOnce(UIView *button, UIView *host) {
	if (objc_getAssociatedObject(button, kChainKey)) return;
	objc_setAssociatedObject(button, kChainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	NSMutableString *chain = [NSMutableString string];
	UIView *v = button;
	for (int depth = 0; v && depth < 14; v = v.superview, depth++) {
		[chain appendFormat:@"\n  [%d] %@ frame=%@%@", depth, NSStringFromClass(v.class), NSStringFromCGRect(v.frame), v == host ? @"  <== HOST" : @""];
	}
	UIViewController *vc = [SCIUtils nearestViewControllerForView:button];
	SCIPBLog(@"variantB chain (vc=%@):%@", vc ? NSStringFromClass(vc.class) : @"<nil>", chain);
}

// Other-profile nav bars get recycled across users; re-resolve when the PK changes.
static void sciSyncContainerUser(UIView *container) {
	id user = sciUserForView(container);
	NSString *pk = user ? [SCIProfileHelpers pkForUser:user] : nil;
	NSString *last = objc_getAssociatedObject(container, kPKKey);

	if (pk.length && ![pk isEqualToString:last ?: @""]) {
		objc_setAssociatedObject(container, kPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		if (last.length) sciInvalidate(container);   // genuine user switch on a reused bar
	}
}

static void sciInjectIntoHost(UIView *host, UIView *button) {
	if (!host) return;

	// Gate on a resolvable user so we never inject on a non-profile nav bar.
	if (!sciUserForView(host)) {
		id marker = button ?: host;
		if (!objc_getAssociatedObject(marker, kChainKey)) {
			objc_setAssociatedObject(marker, kChainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			SCIPBLog(@"variantB SKIP: no user for host=%@ marker=%p", NSStringFromClass(host.class), marker);
		}
		return;
	}

	// Real profile bars hold the native buttons; variant A's separate decorative
	// bar is empty. Requiring one keeps a stray button off it regardless of timing.
	if (!sciHostHasNativeButton(host)) {
		sciLogSkip(host, [NSString stringWithFormat:@"host %@ has no native nav button", NSStringFromClass(host.class)]);
		return;
	}

	if (button) sciLogChainOnce(button, host);
	[sciHeaders() addObject:host];
	sciSyncContainerUser(host);
	sciLayout(host);
}

static void sciHandleNavButton(UIView *button) {
	if (![SCIUtils getBoolPref:@"action_button_profile_enabled"]) return;
	if (!button.window) return;

	BOOL variantA = NO;
	UIView *host = sciHostForNavButton(button, &variantA);
	if (variantA) return;   // header-view hook owns variant A
	sciInjectIntoHost(host, button);
}

static UIView *sciFindDescendantOfClass(UIView *root, Class cls) {
	if (!root || !cls) return nil;
	for (UIView *sub in root.subviews) {
		if ([sub isKindOfClass:cls]) return sub;
		UIView *found = sciFindDescendantOfClass(sub, cls);
		if (found) return found;
	}
	return nil;
}

static BOOL sciHostHasNativeButton(UIView *host) {
	if (sciFindDescendantOfClass(host, sciNativeClass())) return YES;
	Class navBtn = objc_getClass("_TtC14IGProfileUtils25IGNavigationBarButtonView");
	return navBtn && sciFindDescendantOfClass(host, navBtn) != nil;
}

// Drive off the VC lifecycle, not the button's relayout — that timing was flaky
// (button only appeared from some entry points).
static void sciDriveProfileVC(UIViewController *vc) {
	if (![SCIUtils getBoolPref:@"action_button_profile_enabled"]) return;

	UINavigationBar *bar = vc.navigationController.navigationBar;
	if (![bar isKindOfClass:UIView.class]) return;

	// Prefer routing through a real native button (full host classification).
	UIView *button = sciFindDescendantOfClass(bar, sciNativeClass());
	if (button) { sciHandleNavButton(button); return; }

	// No native button in the bar — variant A (header view) owns it.
	Class headerCls = sciHeaderViewClass();
	if (headerCls && sciFindDescendantOfClass(bar, headerCls)) return;

	sciInjectIntoHost(bar, nil);
}

%hook _TtC19IGProfileNavigation24IGBadgedNavigationButton

- (void)layoutSubviews {
	%orig;
	UIView *button = (UIView *)self;
	if ([button isKindOfClass:UIView.class]) sciHandleNavButton(button);
}

- (void)didMoveToWindow {
	%orig;
	UIView *button = (UIView *)self;
	if ([button isKindOfClass:UIView.class]) sciHandleNavButton(button);
}

%end

%hook IGProfileViewController

- (void)viewDidLayoutSubviews {
	%orig;
	sciDriveProfileVC((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	sciDriveProfileVC((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	sciDriveProfileVC((UIViewController *)self);
}

%end

// The nav bar is present for every variant regardless of VC/button class — drive
// off it directly to catch accounts the other hooks miss.
static BOOL sciNonProfileVCName(NSString *cls) {
	return [cls containsString:@"Edit"] || [cls containsString:@"Creation"] ||
		[cls containsString:@"Settings"] || [cls containsString:@"Business"];
}

static void sciDriveNavBar(UIView *bar) {
	if (![SCIUtils getBoolPref:@"action_button_profile_enabled"]) return;

	UINavigationController *nav = nil;
	for (UIResponder *r = bar.nextResponder; r; r = r.nextResponder) {
		if ([r isKindOfClass:UINavigationController.class]) { nav = (UINavigationController *)r; break; }
	}

	UIViewController *top = nav.topViewController ?: nav.visibleViewController;
	if (!top) return;

	NSString *cls = NSStringFromClass(top.class);
	if (![cls containsString:@"Profile"] || sciNonProfileVCName(cls)) return;   // user-profile screens only

	Class headerCls = sciHeaderViewClass();
	if (headerCls && (sciFindDescendantOfClass(bar, headerCls) ||
			sciFindDescendantOfClass(top.viewIfLoaded, headerCls))) return;     // header-view hook owns variant A

	if (![SCIProfileHelpers userForViewController:top] && !sciUserForView(bar)) {
		NSString *key = [@"nb:" stringByAppendingString:cls];
		if (![objc_getAssociatedObject(bar, kNavDiagKey) isEqualToString:key]) {
			objc_setAssociatedObject(bar, kNavDiagKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
			SCIPBLog(@"navbar profile but NO USER yet — vc=%@ bar=%p nav=%@ subviews=%lu", cls, bar, nav ? NSStringFromClass(nav.class) : @"<nil>", (unsigned long)bar.subviews.count);
		}
		return;
	}

	sciInjectIntoHost(bar, nil);   // native-button gate inside keeps the empty variant-A bar clean
}

%hook IGNavigationBar

- (void)layoutSubviews {
	%orig;
	UIView *bar = (UIView *)self;
	if ([bar isKindOfClass:UIView.class]) sciDriveNavBar(bar);
}

%end

#pragma mark - Constructor

%ctor {
	%init;

	void (^refresh)(__unused NSNotification *) = ^(__unused NSNotification *note) {
		sciRefresh();
	};

	[NSNotificationCenter.defaultCenter addObserverForName:SCIActionMenuConfigDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
	[NSNotificationCenter.defaultCenter addObserverForName:SCIActionIconDidChangeNote object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
}