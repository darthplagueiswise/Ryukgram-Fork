// Profile action button — RYGChromeButton positioned next to the native nav cluster.
// Own profile  -> RIGHT of plus.
// Other profile -> LEFT of right-side cluster.
// Icon follows RYGActionIcon profile/global override.

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../ActionButton/RYGActionMenu.h"
#import "../../ActionButton/RYGActionMenuConfig.h"
#import "../../ActionButton/RYGActionCatalog.h"
#import "../../ActionButton/RYGActionIcon.h"
#import "RYGProfileHelpers.h"

// Route to the debug console if its module is built in, else the device console.
// Resolved at runtime so there's no link dependency when it's disabled.
static void rygPBLog(NSString *body) {
	static void (*dbg)(NSString *, NSString *, ...) = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ dbg = (void (*)(NSString *, NSString *, ...))dlsym(RTLD_DEFAULT, "RYGDebugLog"); });

	if (dbg) dbg(@"ProfileBtn", @"%@", body);
}
#define RYGPBLog(fmt, ...) rygPBLog([NSString stringWithFormat:fmt, ##__VA_ARGS__])

static NSString * const kRYGProfileButtonID = @"ryg-profile-action-button";

static CGFloat const kSize = 32.0;
static CGFloat const kIcon = 18.0;
static CGFloat const kGap = 8.0;

static const void *kBtnKey = &kBtnKey;
static const void *kHitKey = &kHitKey;
static const void *kWireKey = &kWireKey;
static const void *kIconKey = &kIconKey;
static const void *kOwnKey = &kOwnKey;
static const void *kSideKey = &kSideKey;       // cached RYGSide
static const void *kTargetKey = &kTargetKey;   // last applied frame
static const void *kSideWarnKey = &kSideWarnKey; // dedup the side-fallback log
static const void *kSkipKey = &kSkipKey;       // dedup repeated skip-reason logs
static const void *kPKKey = &kPKKey;           // last user PK seen on a container (variant-B reuse)
static const void *kChainKey = &kChainKey;     // dedup the variant-B superview-chain log
static const void *kNavDiagKey = &kNavDiagKey; // dedup the nav-bar "no user" diagnostic

static NSInteger rygVersion = 0;

typedef NS_ENUM(NSInteger, RYGSide) {
	RYGSideLeft,
	RYGSideRight
};

static Class rygHeaderViewClass(void);
static UIView *rygFindDescendantOfClass(UIView *root, Class cls);
static BOOL rygHostHasNativeButton(UIView *host);

#pragma mark - Runtime

static id rygCall(id obj, SEL sel) {
	return (obj && [obj respondsToSelector:sel]) ? ((id (*)(id, SEL))objc_msgSend)(obj, sel) : nil;
}

// No KVC: valueForUndefinedKey: throws, and ObjC++/ARC unwinding aborts before @catch runs.
static id rygValue(id obj, NSString *key) {
	if (!obj || !key.length) return nil;

	SEL sel = NSSelectorFromString(key);
	if ([obj respondsToSelector:sel]) return ((id (*)(id, SEL))objc_msgSend)(obj, sel);

	Ivar iv = class_getInstanceVariable([obj class], [@"_" stringByAppendingString:key].UTF8String)
		?: class_getInstanceVariable([obj class], key.UTF8String);
	const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
	return (enc && enc[0] == '@') ? object_getIvar(obj, iv) : nil;
}

static Class rygNativeClass(void) {
	return objc_getClass("_TtC19IGProfileNavigation24IGBadgedNavigationButton") ?:
		objc_getClass("IGProfileNavigation.IGBadgedNavigationButton");
}

static BOOL rygIsNativeNavButton(UIView *view) {
	if (!view) return NO;

	Class badged = rygNativeClass();
	Class nav = objc_getClass("_TtC14IGProfileUtils25IGNavigationBarButtonView");

	return (badged && [view isKindOfClass:badged]) || (nav && [view isKindOfClass:nav]);
}

static BOOL rygUsableView(UIView *view) {
	return view &&
		view.superview &&
		!view.hidden &&
		view.alpha > 0.01 &&
		!CGRectIsEmpty(view.bounds) &&
		![view.accessibilityIdentifier isEqualToString:kRYGProfileButtonID];
}

static UIView *rygWrapperView(id obj) {
	if ([obj isKindOfClass:UIView.class]) return obj;

	UIView *view = rygCall(obj, @selector(view));
	if (![view isKindOfClass:UIView.class]) view = rygValue(obj, @"view");

	return [view isKindOfClass:UIView.class] ? view : nil;
}

#pragma mark - Headers

static NSHashTable<UIView *> *rygHeaders(void) {
	static NSHashTable<UIView *> *headers;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		headers = [NSHashTable weakObjectsHashTable];
	});

	return headers;
}

#pragma mark - User

static id rygUserForView(UIView *view) {
	id user = [RYGProfileHelpers userForView:view];
	if (user) return user;

	UIViewController *vc = [RYGUtils nearestViewControllerForView:view];

	user = rygCall(vc, @selector(user));
	if (user) return user;

	id context = rygCall(vc, @selector(context));
	id config = rygCall(context, @selector(configuration));
	id ref = rygCall(config, @selector(userReference));

	return ref ?: rygCall(rygCall(context, @selector(dataManager)), @selector(userReference));
}

static NSString *rygLogID(UIView *header) {
	id user = rygUserForView(header);
	NSString *uname = user ? [RYGProfileHelpers usernameForUser:user] : nil;
	NSString *pk = user ? [RYGProfileHelpers pkForUser:user] : nil;
	return [NSString stringWithFormat:@"user=%@ pk=%@ hdr=%p", uname.length ? uname : @"<nil>", pk.length ? pk : @"<nil>", header];
}

static BOOL rygIsOwnProfile(UIView *header) {
	id user = rygUserForView(header);
	NSString *pk = user ? [RYGProfileHelpers pkForUser:user] : nil;
	NSString *me = [RYGUtils currentUserPK];

	if (pk.length && me.length) return [pk isEqualToString:me];

	return [objc_getAssociatedObject(header, kOwnKey) boolValue];
}

#pragma mark - Copy

static BOOL rygIsCopyAction(NSString *aid) {
	return [aid isEqualToString:RYGAID_CopyID] ||
		[aid isEqualToString:RYGAID_CopyUsername] ||
		[aid isEqualToString:RYGAID_CopyName] ||
		[aid isEqualToString:RYGAID_CopyBio] ||
		[aid isEqualToString:RYGAID_CopyLink] ||
		[aid isEqualToString:RYGAID_CopyAll];
}

static void rygCopy(NSString *value, NSString *kind) {
	if (!value.length) {
		RYGNotifyWarning(RYG_NOTIF_VALIDATION_ERROR, RYGLocalized(@"Nothing to copy"), nil);
		return;
	}

	UIPasteboard.generalPasteboard.string = value;
	RYGNotifySuccess(RYG_NOTIF_COPY_PROFILE, [NSString stringWithFormat:RYGLocalized(@"Copied %@"), kind], nil);
}

static NSString *rygAllInfo(id user) {
	NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:5];

	NSString *username = [RYGProfileHelpers usernameForUser:user];
	NSString *name = [RYGProfileHelpers fullNameForUser:user];
	NSString *bio = [RYGProfileHelpers biographyForUser:user];
	NSString *link = [RYGProfileHelpers profileLinkForUser:user].absoluteString;
	NSString *pk = [RYGProfileHelpers pkForUser:user];

	if (username.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", RYGLocalized(@"Username"), username]];
	if (name.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", RYGLocalized(@"Name"), name]];
	if (bio.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", RYGLocalized(@"Bio"), bio]];
	if (link.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", RYGLocalized(@"Profile link"), link]];
	if (pk.length) [lines addObject:[NSString stringWithFormat:@"%@: %@", RYGLocalized(@"ID"), pk]];

	return [lines componentsJoinedByString:@"\n"];
}

static void rygRunCopy(id user, NSString *aid) {
	if ([aid isEqualToString:RYGAID_CopyID]) {
		rygCopy([RYGProfileHelpers pkForUser:user], RYGLocalized(@"ID"));
	} else if ([aid isEqualToString:RYGAID_CopyUsername]) {
		rygCopy([RYGProfileHelpers usernameForUser:user], RYGLocalized(@"Username"));
	} else if ([aid isEqualToString:RYGAID_CopyName]) {
		rygCopy([RYGProfileHelpers fullNameForUser:user], RYGLocalized(@"Name"));
	} else if ([aid isEqualToString:RYGAID_CopyBio]) {
		rygCopy([RYGProfileHelpers biographyForUser:user], RYGLocalized(@"Bio"));
	} else if ([aid isEqualToString:RYGAID_CopyLink]) {
		rygCopy([RYGProfileHelpers profileLinkForUser:user].absoluteString, RYGLocalized(@"Profile link"));
	} else if ([aid isEqualToString:RYGAID_CopyAll]) {
		rygCopy(rygAllInfo(user), RYGLocalized(@"Profile info"));
	}
}

#pragma mark - Settings

static void rygOpenSettings(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			if (!window.isKeyWindow) continue;

			[RYGUtils showSettingsVC:window atTopLevelEntry:RYGLocalized(@"Profile")];
			return;
		}
	}
}

#pragma mark - Menu

static NSString *rygDecimal(NSNumber *number) {
	if (!number) return nil;

	static NSNumberFormatter *formatter;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		formatter = [NSNumberFormatter new];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;
	});

	return [formatter stringFromNumber:number];
}

static RYGAction *rygActionForUser(id user, NSString *aid) {
	if (rygIsCopyAction(aid)) {
		RYGActionDescriptor *d = [RYGActionCatalog descriptorForActionID:aid source:RYGActionSourceProfile];
		return d ? [RYGAction actionWithTitle:d.title icon:d.iconSF handler:^{ rygRunCopy(user, aid); }] : nil;
	}

	if ([aid isEqualToString:RYGAID_ViewPicture]) {
		return [RYGAction actionWithTitle:RYGLocalized(@"View picture") icon:@"bcn_image_outline_24" handler:^{ [RYGProfileHelpers viewPictureForUser:user]; }];
	}

	if ([aid isEqualToString:RYGAID_SharePicture]) {
		return [RYGAction actionWithTitle:RYGLocalized(@"Share picture") icon:@"square.and.arrow.up" handler:^{ [RYGProfileHelpers sharePictureForUser:user]; }];
	}

	if ([aid isEqualToString:RYGAID_SavePicturePhotos]) {
		return [RYGAction actionWithTitle:RYGLocalized(@"Save to Photos") icon:@"square.and.arrow.down" handler:^{ [RYGProfileHelpers savePictureForUser:user]; }];
	}

	if ([aid isEqualToString:RYGAID_SavePictureGallery]) {
		if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;

		return [RYGAction actionWithTitle:RYGLocalized(@"Save picture to Gallery") icon:@"ig_icon_photo_gallery_prism_outline_24" handler:^{
			[RYGProfileHelpers savePictureToGalleryForUser:user];
		}];
	}

	if ([aid isEqualToString:RYGAID_ProfileSettings]) {
		return [RYGAction actionWithTitle:RYGLocalized(@"Profile settings") icon:@"bcn_user_outline_24" handler:^{
			rygOpenSettings();
		}];
	}

	if ([aid isEqualToString:RYGAID_ProfileInfoPrivacy]) {
		NSNumber *status = [RYGProfileHelpers privacyStatusForUser:user];
		if (!status) return nil;

		BOOL priv = status.integerValue == 2;
		return [RYGAction infoRowWithTitle:(priv ? RYGLocalized(@"Private profile") : RYGLocalized(@"Public profile")) icon:(priv ? @"lock" : @"ig_icon_unlock_prism_outline_24")];
	}

	if ([aid isEqualToString:RYGAID_ProfileInfoFollowers]) {
		NSString *count = rygDecimal([RYGProfileHelpers followerCountForUser:user]);
		return count.length ? [RYGAction infoRowWithTitle:[NSString stringWithFormat:RYGLocalized(@"Followers: %@"), count] icon:@"ig_icon_users_pano_outline_24"] : nil;
	}

	if ([aid isEqualToString:RYGAID_ProfileInfoFollowing]) {
		NSString *count = rygDecimal([RYGProfileHelpers followingCountForUser:user]);
		return count.length ? [RYGAction infoRowWithTitle:[NSString stringWithFormat:RYGLocalized(@"Following: %@"), count] icon:@"ig_icon_user_follow_outline_24"] : nil;
	}

	return nil;
}

static UIMenu *rygMenuForUser(id user) {
	if (!user) {
		RYGAction *action = [RYGAction actionWithTitle:RYGLocalized(@"Profile unavailable") icon:nil handler:^{}];
		return [RYGActionMenu buildMenuWithActions:@[action]];
	}

	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceProfile];

	RYGAction *(^resolver)(NSString *) = ^RYGAction *(NSString *aid) {
		return rygActionForUser(user, aid);
	};

	return [RYGActionMenu buildMenuWithActions:[RYGActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolver]];
}

static UIMenu *rygDeferredMenu(UIView *view) {
	__weak UIView *weakView = view;

	UIDeferredMenuElement *deferred = [UIDeferredMenuElement elementWithProvider:^(void (^done)(NSArray<UIMenuElement *> *)) {
		done(rygMenuForUser(rygUserForView(weakView)).children ?: @[]);
	}];

	return [UIMenu menuWithTitle:@"" children:@[deferred]];
}

static void rygRunTap(id user, RYGActionMenuConfig *cfg) {
	if (!user) return;

	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	if ([tap isEqualToString:@"menu"]) return;

	if ([tap isEqualToString:RYGAID_ViewPicture]) {
		[RYGProfileHelpers viewPictureForUser:user];
	} else if ([tap isEqualToString:RYGAID_SharePicture]) {
		[RYGProfileHelpers sharePictureForUser:user];
	} else if ([tap isEqualToString:RYGAID_SavePicturePhotos]) {
		[RYGProfileHelpers savePictureForUser:user];
	} else if ([tap isEqualToString:RYGAID_SavePictureGallery]) {
		if ([RYGUtils getBoolPref:@"ryg_gallery_enabled"]) [RYGProfileHelpers savePictureToGalleryForUser:user];
	} else if ([tap isEqualToString:RYGAID_ProfileSettings]) {
		rygOpenSettings();
	} else if (rygIsCopyAction(tap)) {
		rygRunCopy(user, tap);
	}
}

// Shared tap target — the host may be a nav bar with no tap selector, so resolve
// the user from the sender rather than targeting the host.
@interface RYGProfileTapTarget : NSObject
@end

@implementation RYGProfileTapTarget
+ (instancetype)shared {
	static RYGProfileTapTarget *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [RYGProfileTapTarget new]; });
	return shared;
}
- (void)tapped:(id)sender {
	UIView *view = [sender isKindOfClass:UIView.class] ? sender : nil;
	rygRunTap(rygUserForView(view), [RYGActionMenuConfig configForSource:RYGActionSourceProfile]);
}
@end

#pragma mark - Icon

static NSString *rygSymbol(void) {
	NSString *symbol = [RYGActionIcon effectiveSymbolNameForSource:RYGActionSourceProfile];
	return symbol.length ? symbol : RYGActionIconDefaultName;
}

static void rygApplyIcon(UIView *native) {
	NSString *symbol = rygSymbol();
	if ([objc_getAssociatedObject(native, kIconKey) isEqualToString:symbol]) return;

	if ([native isKindOfClass:RYGChromeButton.class]) {
		RYGChromeButton *chrome = (RYGChromeButton *)native;
		chrome.symbolName = symbol;
		chrome.iconTint = UIColor.labelColor;
	}

	objc_setAssociatedObject(native, kIconKey, symbol, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Button

static UIView *rygButton(UIView *header) {
	UIView *button = objc_getAssociatedObject(header, kBtnKey);
	if (button) return button;

	RYGChromeButton *chrome = [[RYGChromeButton alloc] initWithSymbol:rygSymbol() pointSize:kIcon diameter:kSize];
	chrome.translatesAutoresizingMaskIntoConstraints = YES;
	chrome.bubbleColor = UIColor.clearColor;
	chrome.iconTint = UIColor.labelColor;
	chrome.userInteractionEnabled = NO;
	chrome.hidden = YES;
	chrome.accessibilityIdentifier = kRYGProfileButtonID;
	chrome.accessibilityLabel = RYGLocalized(@"RyukGram profile actions");

	button = chrome;
	objc_setAssociatedObject(header, kBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return button;
}

static UIButton *rygHit(UIView *header) {
	UIButton *hit = objc_getAssociatedObject(header, kHitKey);
	if (hit) return hit;

	hit = [UIButton buttonWithType:UIButtonTypeCustom];
	hit.backgroundColor = UIColor.clearColor;
	hit.translatesAutoresizingMaskIntoConstraints = YES;
	hit.adjustsImageWhenHighlighted = NO;
	hit.hidden = YES;
	hit.accessibilityLabel = RYGLocalized(@"RyukGram profile actions");
	hit.accessibilityIdentifier = kRYGProfileButtonID;   // excluded from the anchor scan

	objc_setAssociatedObject(header, kHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return hit;
}

static void rygWire(UIView *header, UIButton *hit) {
	RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceProfile];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	NSString *key = [NSString stringWithFormat:@"%@|%ld", tap, (long)rygVersion];

	if ([objc_getAssociatedObject(hit, kWireKey) isEqualToString:key]) return;

	[hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	// Always attach the menu (long-press); a direct tap just drops primary-action.
	hit.menu = rygDeferredMenu(header);

	if ([tap isEqualToString:@"menu"]) {
		hit.showsMenuAsPrimaryAction = YES;
	} else {
		hit.showsMenuAsPrimaryAction = NO;
		[hit addTarget:[RYGProfileTapTarget shared] action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
	}

	objc_setAssociatedObject(hit, kWireKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Anchor

static void rygConsiderAnchor(UIView *header, UIView *view, RYGSide side, UIView **best, CGFloat *bestX) {
	if (!rygUsableView(view)) return;

	CGFloat width = CGRectGetWidth(header.bounds);
	CGRect frame = [view.superview convertRect:view.frame toView:header];

	if (side == RYGSideLeft) {
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
static BOOL rygIsAnchorCandidate(UIView *view, RYGSide side) {
	if ([view.accessibilityIdentifier isEqualToString:kRYGProfileButtonID]) return NO;
	if (rygIsNativeNavButton(view)) return YES;
	return side == RYGSideRight && [view isKindOfClass:UIControl.class];
}

static void rygScanAnchors(UIView *header, UIView *root, RYGSide side, UIView **best, CGFloat *bestX) {
	for (UIView *sub in root.subviews) {
		if (rygIsAnchorCandidate(sub, side)) rygConsiderAnchor(header, sub, side, best, bestX);
		rygScanAnchors(header, sub, side, best, bestX);
	}
}

static UIView *rygAnchor(UIView *header, RYGSide side) {
	UIView *best = nil;
	CGFloat bestX = (side == RYGSideLeft) ? -CGFLOAT_MAX : CGFLOAT_MAX;

	NSArray *buttons = rygValue(header, side == RYGSideLeft ? @"leftButtons" : @"rightButtons");
	if ([buttons isKindOfClass:NSArray.class]) {
		for (id wrapper in buttons) {
			rygConsiderAnchor(header, rygWrapperView(wrapper), side, &best, &bestX);
		}
	}

	if (!best) rygScanAnchors(header, header, side, &best, &bestX);

	return best;
}

static RYGSide rygSideFor(UIView *header) {
	NSNumber *cached = objc_getAssociatedObject(header, kSideKey);
	if (cached) return (RYGSide)cached.integerValue;

	id user = rygUserForView(header);
	NSString *pk = user ? [RYGProfileHelpers pkForUser:user] : nil;
	NSString *me = [RYGUtils currentUserPK];

	// Cache only once the PK is known; the titleIsCentered fallback can be wrong early.
	if (pk.length && me.length) {
		RYGSide side = [pk isEqualToString:me] ? RYGSideLeft : RYGSideRight;
		objc_setAssociatedObject(header, kSideKey, @(side), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		return side;
	}

	BOOL centered = [objc_getAssociatedObject(header, kOwnKey) boolValue];
	if (![objc_getAssociatedObject(header, kSideWarnKey) boolValue]) {
		objc_setAssociatedObject(header, kSideWarnKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		RYGPBLog(@"side FALLBACK: pk/me unresolved (pk=%@ me=%@) using titleIsCentered=%d — hdr=%p", pk.length ? pk : @"<nil>", me.length ? me : @"<nil>", centered, header);
	}
	return centered ? RYGSideLeft : RYGSideRight;
}

static void rygInvalidate(UIView *header) {
	objc_setAssociatedObject(header, kSideKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kTargetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kSideWarnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kSkipKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark - Layout

static void rygRemove(UIView *header) {
	[(UIView *)objc_getAssociatedObject(header, kBtnKey) removeFromSuperview];
	[(UIView *)objc_getAssociatedObject(header, kHitKey) removeFromSuperview];
	objc_setAssociatedObject(header, kBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	rygInvalidate(header);
}

// Re-scan each pass — the leftmost right-cluster element can change as pills appear.
static UIView *rygResolveAnchor(UIView *header, RYGSide side) {
	return rygAnchor(header, side);
}

// Dedup skip reasons — layoutSubviews fires constantly.
static void rygLogSkip(UIView *header, NSString *reason) {
	if ([objc_getAssociatedObject(header, kSkipKey) isEqualToString:reason]) return;
	objc_setAssociatedObject(header, kSkipKey, reason, OBJC_ASSOCIATION_COPY_NONATOMIC);
	RYGPBLog(@"layout SKIP: %@ — %@", reason, rygLogID(header));
}

static void rygLayout(UIView *header) {
	if (![header isKindOfClass:UIView.class]) return;

	BOOL enabled = [RYGUtils getBoolPref:@"action_button_profile_enabled"];
	if (!enabled) {
		rygLogSkip(header, @"pref action_button_profile_enabled=OFF");
		if (objc_getAssociatedObject(header, kBtnKey)) rygRemove(header);
		return;
	}

	Class headerCls = rygHeaderViewClass();

	UIView *button = rygButton(header);
	UIButton *hit = rygHit(header);
	if (!button || !hit) {
		rygLogSkip(header, [NSString stringWithFormat:@"button=%p hit=%p nil", button, hit]);
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

	rygApplyIcon(button);
	rygWire(header, hit);

	CGFloat width = CGRectGetWidth(header.bounds);
	CGFloat height = CGRectGetHeight(header.bounds);

	if (width < 60.0 || height < 20.0) {
		rygLogSkip(header, [NSString stringWithFormat:@"header too small w=%.1f h=%.1f", width, height]);
		return;
	}

	// Header view can place early off titleIsCentered; other hosts need a resolved
	// user, else we'd paint a stray button on whatever nav bar is on screen.
	BOOL isHeaderHost = headerCls && [header isKindOfClass:headerCls];
	if (!isHeaderHost && !rygUserForView(header)) {
		rygLogSkip(header, @"non-header host without a resolved user");
		return;
	}

	RYGSide side = rygSideFor(header);
	UIView *anchor = rygResolveAnchor(header, side);

	CGFloat x, y;

	if (anchor) {
		CGRect frame = [anchor.superview convertRect:anchor.frame toView:header];
		y = floor(CGRectGetMidY(frame) - kSize * 0.5);
		x = side == RYGSideLeft ? CGRectGetMaxX(frame) + kGap : CGRectGetMinX(frame) - kGap - kSize;
	} else {
		NSValue *placed = objc_getAssociatedObject(header, kTargetKey);
		if (placed && !button.hidden && !reparented) return;   // hold position; don't bounce to the band on a transient anchor miss

		// First placement with no anchor — pin to the nav-bar band.
		CGFloat band = header.safeAreaInsets.top + (44.0 - kSize) * 0.5;
		y = floor(band);
		x = side == RYGSideLeft ? kGap + 4.0 : width - kSize - 8.0;
	}

	x = MAX(4.0, MIN(x, width - kSize - 4.0));
	y = MAX(0.0, MIN(y, height - kSize));

	CGRect target = CGRectMake(x, y, kSize, kSize);

	NSValue *last = objc_getAssociatedObject(header, kTargetKey);
	if (!reparented && !button.hidden && last && CGRectEqualToRect(last.CGRectValue, target)) return;

	RYGPBLog(@"layout SHOW: side=%@ anchor=%@ target=%@ clipped=%d icon=%@ hdr=%.0fx%.0f safeTop=%.1f reparented=%d — %@",
		side == RYGSideLeft ? @"L" : @"R",
		anchor ? NSStringFromClass(anchor.class) : @"<none/band>",
		NSStringFromCGRect(target),
		(x <= 4.0 || x >= width - kSize - 4.0 || y <= 0.0 || y >= height - kSize),
		rygSymbol(), width, height, header.safeAreaInsets.top, reparented, rygLogID(header));

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

static void rygRefresh(void) {
	rygVersion++;

	for (UIView *header in rygHeaders().allObjects) {
		if (!header.superview) continue;

		objc_setAssociatedObject(objc_getAssociatedObject(header, kHitKey), kWireKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(objc_getAssociatedObject(header, kBtnKey), kIconKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		rygLayout(header);
	}
}

#pragma mark - Hook

%hook _TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView

- (void)configureWithTitleView:(id)titleView leftButtons:(id)leftButtons rightButtons:(id)rightButtons titleIsCentered:(BOOL)titleIsCentered {
	%orig;

	UIView *header = (UIView *)self;
	if (![header isKindOfClass:UIView.class]) return;

	objc_setAssociatedObject(header, kOwnKey, @(titleIsCentered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[rygHeaders() addObject:header];
	rygInvalidate(header);

	dispatch_async(dispatch_get_main_queue(), ^{
		rygLayout(header);
	});
}

- (void)layoutSubviews {
	%orig;

	UIView *header = (UIView *)self;
	if (![header isKindOfClass:UIView.class]) return;

	// configure: is bypassed by IG's Swift dispatch, so register for refresh here.
	[rygHeaders() addObject:header];
	rygLayout(header);
}

%end

#pragma mark - Variant B (classic nav surface)

// A/B variant: some accounts show other-user profiles in a plain UINavigationBar
// instead of the header view, so the hook above never fires. Anchor off the one
// class common to both: the native badged nav button.

static Class rygHeaderViewClass(void) {
	return objc_getClass("_TtC24IGProfileNavigationSwift29IGProfileNavigationHeaderView");
}

// Walk up from a native nav button to the host to inject into. *variantA marks
// the header-view case (handled above) so we don't double-inject.
static UIView *rygHostForNavButton(UIView *button, BOOL *variantA) {
	*variantA = NO;
	Class headerCls = rygHeaderViewClass();

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

static void rygLogChainOnce(UIView *button, UIView *host) {
	if (objc_getAssociatedObject(button, kChainKey)) return;
	objc_setAssociatedObject(button, kChainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	NSMutableString *chain = [NSMutableString string];
	UIView *v = button;
	for (int depth = 0; v && depth < 14; v = v.superview, depth++) {
		[chain appendFormat:@"\n  [%d] %@ frame=%@%@", depth, NSStringFromClass(v.class), NSStringFromCGRect(v.frame), v == host ? @"  <== HOST" : @""];
	}
	UIViewController *vc = [RYGUtils nearestViewControllerForView:button];
	RYGPBLog(@"variantB chain (vc=%@):%@", vc ? NSStringFromClass(vc.class) : @"<nil>", chain);
}

// Other-profile nav bars get recycled across users; re-resolve when the PK changes.
static void rygSyncContainerUser(UIView *container) {
	id user = rygUserForView(container);
	NSString *pk = user ? [RYGProfileHelpers pkForUser:user] : nil;
	NSString *last = objc_getAssociatedObject(container, kPKKey);

	if (pk.length && ![pk isEqualToString:last ?: @""]) {
		objc_setAssociatedObject(container, kPKKey, pk, OBJC_ASSOCIATION_COPY_NONATOMIC);
		if (last.length) rygInvalidate(container);   // genuine user switch on a reused bar
	}
}

static void rygInjectIntoHost(UIView *host, UIView *button) {
	if (!host) return;

	// Gate on a resolvable user so we never inject on a non-profile nav bar.
	if (!rygUserForView(host)) {
		id marker = button ?: host;
		if (!objc_getAssociatedObject(marker, kChainKey)) {
			objc_setAssociatedObject(marker, kChainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			RYGPBLog(@"variantB SKIP: no user for host=%@ marker=%p", NSStringFromClass(host.class), marker);
		}
		return;
	}

	// Real profile bars hold the native buttons; variant A's separate decorative
	// bar is empty. Requiring one keeps a stray button off it regardless of timing.
	if (!rygHostHasNativeButton(host)) {
		rygLogSkip(host, [NSString stringWithFormat:@"host %@ has no native nav button", NSStringFromClass(host.class)]);
		return;
	}

	if (button) rygLogChainOnce(button, host);
	[rygHeaders() addObject:host];
	rygSyncContainerUser(host);
	rygLayout(host);
}

static void rygHandleNavButton(UIView *button) {
	if (![RYGUtils getBoolPref:@"action_button_profile_enabled"]) return;
	if (!button.window) return;

	BOOL variantA = NO;
	UIView *host = rygHostForNavButton(button, &variantA);
	if (variantA) return;   // header-view hook owns variant A
	rygInjectIntoHost(host, button);
}

static UIView *rygFindDescendantOfClass(UIView *root, Class cls) {
	if (!root || !cls) return nil;
	for (UIView *sub in root.subviews) {
		if ([sub isKindOfClass:cls]) return sub;
		UIView *found = rygFindDescendantOfClass(sub, cls);
		if (found) return found;
	}
	return nil;
}

static BOOL rygHostHasNativeButton(UIView *host) {
	if (rygFindDescendantOfClass(host, rygNativeClass())) return YES;
	Class navBtn = objc_getClass("_TtC14IGProfileUtils25IGNavigationBarButtonView");
	return navBtn && rygFindDescendantOfClass(host, navBtn) != nil;
}

// Drive off the VC lifecycle, not the button's relayout — that timing was flaky
// (button only appeared from some entry points).
static void rygDriveProfileVC(UIViewController *vc) {
	if (![RYGUtils getBoolPref:@"action_button_profile_enabled"]) return;

	UINavigationBar *bar = vc.navigationController.navigationBar;
	if (![bar isKindOfClass:UIView.class]) return;

	// Prefer routing through a real native button (full host classification).
	UIView *button = rygFindDescendantOfClass(bar, rygNativeClass());
	if (button) { rygHandleNavButton(button); return; }

	// No native button in the bar — variant A (header view) owns it.
	Class headerCls = rygHeaderViewClass();
	if (headerCls && rygFindDescendantOfClass(bar, headerCls)) return;

	rygInjectIntoHost(bar, nil);
}

%hook _TtC19IGProfileNavigation24IGBadgedNavigationButton

- (void)layoutSubviews {
	%orig;
	UIView *button = (UIView *)self;
	if ([button isKindOfClass:UIView.class]) rygHandleNavButton(button);
}

- (void)didMoveToWindow {
	%orig;
	UIView *button = (UIView *)self;
	if ([button isKindOfClass:UIView.class]) rygHandleNavButton(button);
}

%end

%hook IGProfileViewController

- (void)viewDidLayoutSubviews {
	%orig;
	rygDriveProfileVC((UIViewController *)self);
}

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	rygDriveProfileVC((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygDriveProfileVC((UIViewController *)self);
}

%end

// The nav bar is present for every variant regardless of VC/button class — drive
// off it directly to catch accounts the other hooks miss.
static BOOL rygNonProfileVCName(NSString *cls) {
	return [cls containsString:@"Edit"] || [cls containsString:@"Creation"] ||
		[cls containsString:@"Settings"] || [cls containsString:@"Business"];
}

static void rygDriveNavBar(UIView *bar) {
	if (![RYGUtils getBoolPref:@"action_button_profile_enabled"]) return;

	UINavigationController *nav = nil;
	for (UIResponder *r = bar.nextResponder; r; r = r.nextResponder) {
		if ([r isKindOfClass:UINavigationController.class]) { nav = (UINavigationController *)r; break; }
	}

	UIViewController *top = nav.topViewController ?: nav.visibleViewController;
	if (!top) return;

	NSString *cls = NSStringFromClass(top.class);
	if (![cls containsString:@"Profile"] || rygNonProfileVCName(cls)) return;   // user-profile screens only

	Class headerCls = rygHeaderViewClass();
	if (headerCls && (rygFindDescendantOfClass(bar, headerCls) ||
			rygFindDescendantOfClass(top.viewIfLoaded, headerCls))) return;     // header-view hook owns variant A

	if (![RYGProfileHelpers userForViewController:top] && !rygUserForView(bar)) {
		NSString *key = [@"nb:" stringByAppendingString:cls];
		if (![objc_getAssociatedObject(bar, kNavDiagKey) isEqualToString:key]) {
			objc_setAssociatedObject(bar, kNavDiagKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
			RYGPBLog(@"navbar profile but NO USER yet — vc=%@ bar=%p nav=%@ subviews=%lu", cls, bar, nav ? NSStringFromClass(nav.class) : @"<nil>", (unsigned long)bar.subviews.count);
		}
		return;
	}

	rygInjectIntoHost(bar, nil);   // native-button gate inside keeps the empty variant-A bar clean
}

%hook IGNavigationBar

- (void)layoutSubviews {
	%orig;
	UIView *bar = (UIView *)self;
	if ([bar isKindOfClass:UIView.class]) rygDriveNavBar(bar);
}

%end

#pragma mark - Constructor

%ctor {
	%init;

	void (^refresh)(__unused NSNotification *) = ^(__unused NSNotification *note) {
		rygRefresh();
	};

	[NSNotificationCenter.defaultCenter addObserverForName:RYGActionMenuConfigDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
	[NSNotificationCenter.defaultCenter addObserverForName:RYGActionIconDidChangeNote object:nil queue:NSOperationQueue.mainQueue usingBlock:refresh];
}