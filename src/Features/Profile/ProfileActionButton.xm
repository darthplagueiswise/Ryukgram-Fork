// Profile action button — SCIChromeButton positioned next to the native nav cluster.
// Own profile  -> RIGHT of plus.
// Other profile -> LEFT of right-side cluster.
// Icon follows SCIActionIcon profile/global override.

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

static NSString * const kSCIProfileButtonID = @"sci-profile-action-button";

static CGFloat const kSize = 32.0;
static CGFloat const kIcon = 18.0;
static CGFloat const kGap = 8.0;

static const void *kBtnKey = &kBtnKey;
static const void *kHitKey = &kHitKey;
static const void *kWireKey = &kWireKey;
static const void *kIconKey = &kIconKey;
static const void *kOwnKey = &kOwnKey;

static NSInteger sciVersion = 0;

typedef NS_ENUM(NSInteger, SCISide) {
	SCISideLeft,
	SCISideRight
};

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

	objc_setAssociatedObject(header, kHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return hit;
}

static void sciWire(UIView *header, UIButton *hit) {
	SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceProfile];
	NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
	NSString *key = [NSString stringWithFormat:@"%@|%ld", tap, (long)sciVersion];

	if ([objc_getAssociatedObject(hit, kWireKey) isEqualToString:key]) return;

	[hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
	hit.menu = nil;
	hit.showsMenuAsPrimaryAction = NO;

	if ([tap isEqualToString:@"menu"]) {
		hit.menu = sciDeferredMenu(header);
		hit.showsMenuAsPrimaryAction = YES;
	} else {
		[hit addTarget:header action:@selector(sciProfileActionTapped:) forControlEvents:UIControlEventTouchUpInside];
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

static void sciScanAnchors(UIView *header, UIView *root, SCISide side, UIView **best, CGFloat *bestX) {
	for (UIView *sub in root.subviews) {
		if (sciIsNativeNavButton(sub)) sciConsiderAnchor(header, sub, side, best, bestX);
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

#pragma mark - Layout

static void sciRemove(UIView *header) {
	[(UIView *)objc_getAssociatedObject(header, kBtnKey) removeFromSuperview];
	[(UIView *)objc_getAssociatedObject(header, kHitKey) removeFromSuperview];
	objc_setAssociatedObject(header, kBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(header, kHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void sciLayout(UIView *header) {
	if (![header isKindOfClass:UIView.class]) return;

	if (![SCIUtils getBoolPref:@"action_button_profile_enabled"]) {
		sciRemove(header);
		return;
	}

	UIView *button = sciButton(header);
	UIButton *hit = sciHit(header);
	if (!button || !hit) return;

	if (button.superview != header) {
		[button removeFromSuperview];
		[header addSubview:button];
	}
	if (hit.superview != header) {
		[hit removeFromSuperview];
		[header addSubview:hit];
	}

	sciApplyIcon(button);
	sciWire(header, hit);

	CGFloat width = CGRectGetWidth(header.bounds);
	CGFloat height = CGRectGetHeight(header.bounds);

	if (width < 60.0 || height < 20.0) return;

	SCISide side = sciIsOwnProfile(header) ? SCISideLeft : SCISideRight;
	UIView *anchor = sciAnchor(header, side);

	if (!anchor) return;

	CGRect frame = [anchor.superview convertRect:anchor.frame toView:header];

	CGFloat y = floor(CGRectGetMidY(frame) - kSize * 0.5);
	CGFloat x = side == SCISideLeft ? CGRectGetMaxX(frame) + kGap : CGRectGetMinX(frame) - kGap - kSize;

	x = MAX(4.0, MIN(x, width - kSize - 4.0));
	y = MAX(0.0, MIN(y, height - kSize));

	CGRect target = CGRectMake(x, y, kSize, kSize);

	button.hidden = NO;
	button.alpha = 1.0;
	button.frame = target;

	hit.hidden = NO;
	hit.frame = target;

	[header bringSubviewToFront:button];
	[header bringSubviewToFront:hit];
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

	dispatch_async(dispatch_get_main_queue(), ^{
		sciLayout(header);
	});
}

- (void)layoutSubviews {
	%orig;
	sciLayout((UIView *)self);
}

%new
- (void)sciProfileActionTapped:(id)sender {
	UIView *view = [sender isKindOfClass:UIView.class] ? sender : (UIView *)self;
	sciRunTap(sciUserForView(view), [SCIActionMenuConfig configForSource:SCIActionSourceProfile]);
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
