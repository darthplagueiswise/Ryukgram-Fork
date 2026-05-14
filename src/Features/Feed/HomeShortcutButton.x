// Home feed top-bar shortcut button.
// Injects a shortcut button beside IGHomeFeedHeaderView's _createButton.
// Only hooks IGHomeFeedHeaderView for lighter and more stable layout.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../SCIChrome.h"
#import "SCIHomeShortcutCatalog.h"
#import <objc/runtime.h>
#import <objc/message.h>

static const void *kSCIHomeShortcutBtnKey = &kSCIHomeShortcutBtnKey;
static const void *kSCIHomeShortcutSigKey = &kSCIHomeShortcutSigKey;
static const void *kSCIHomeShortcutSingleActionKey = &kSCIHomeShortcutSingleActionKey;
static const void *kSCIHomeShortcutPlusKey = &kSCIHomeShortcutPlusKey;

static CGFloat const kSCIHomeShortcutGap = 4.0;
static CGFloat const kSCIHomeShortcutMinSide = 28.0;
static CGFloat const kSCIHomeShortcutPointSize = 17.0;

#pragma mark - Hosts

static NSHashTable<UIView *> *sciHomeShortcutHosts(void) {
	static NSHashTable *hosts;
	static dispatch_once_t once;

	dispatch_once(&once, ^{
		hosts = NSHashTable.weakObjectsHashTable;
	});

	return hosts;
}

#pragma mark - Helpers

static UIView *sciHomeHeaderCreateButton(id header) {
	Ivar ivar = class_getInstanceVariable([header class], "_createButton");
	id button = ivar ? object_getIvar(header, ivar) : nil;
	return [button isKindOfClass:UIView.class] ? button : nil;
}

static BOOL sciValidBadgeFrame(UIView *badge) {
	if (!badge || !badge.superview || !badge.window) return NO;
	if (badge.frame.size.width <= 1.0 || badge.frame.size.height <= 1.0) return NO;
	if (CGRectIsEmpty(badge.frame) || CGRectIsNull(badge.frame)) return NO;

	return YES;
}

static void sciClearInjectedButton(UIView *parent) {
	if (!parent) return;

	SCIChromeButton *button = objc_getAssociatedObject(parent, kSCIHomeShortcutBtnKey);

	[sciHomeShortcutHosts() removeObject:parent];

	if (button) {
		[button removeFromSuperview];
	}

	objc_setAssociatedObject(parent, kSCIHomeShortcutBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(parent, kSCIHomeShortcutSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(parent, kSCIHomeShortcutPlusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	[parent setNeedsLayout];
}

static NSString *sciResolvedSymbol(NSArray<NSString *> *actionIDs) {
	NSString *userIcon = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];

	if (userIcon.length && ![userIcon isEqualToString:@"auto"]) {
		return userIcon;
	}

	if (actionIDs.count == 1) {
		SCIHomeShortcutAction *action = [SCIHomeShortcutCatalog actionForID:actionIDs.firstObject];
		return action.symbol.length ? action.symbol : @"ellipsis.circle.fill";
	}

	return @"ellipsis.circle.fill";
}

static NSString *sciShortcutSignature(NSArray<NSString *> *actionIDs, NSString *symbol) {
	return [NSString stringWithFormat:@"%@|%@", symbol ?: @"", [actionIDs componentsJoinedByString:@","]];
}

static void sciShiftRightSiblings(UIView *parent, UIView *plus, UIView *button, CGRect plusFrame, CGRect buttonFrame) {
	Class badgeClass = %c(IGBadgeButton);
	CGFloat clearX = CGRectGetMaxX(buttonFrame) + kSCIHomeShortcutGap;

	for (UIView *view in parent.subviews) {
		if (view == plus || view == button) continue;
		if (![view isKindOfClass:badgeClass]) continue;
		if (view.frame.origin.x <= plusFrame.origin.x) continue;
		if (view.frame.origin.x >= clearX) continue;

		CGRect frame = view.frame;
		frame.origin.x = clearX;
		view.frame = frame;
	}
}

static void sciConfigureShortcutButton(SCIChromeButton *button, UIView *sigOwner, NSArray<NSString *> *actionIDs, NSString *symbol, id target, SEL actionSelector) {
	NSString *signature = sciShortcutSignature(actionIDs, symbol);
	NSString *oldSignature = objc_getAssociatedObject(sigOwner, kSCIHomeShortcutSigKey);

	if ([oldSignature isEqualToString:signature]) return;

	[button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	button.menu = nil;
	button.showsMenuAsPrimaryAction = NO;
	button.symbolName = symbol;
	button.symbolPointSize = kSCIHomeShortcutPointSize;

	objc_setAssociatedObject(button, kSCIHomeShortcutSingleActionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (actionIDs.count == 1) {
		objc_setAssociatedObject(button, kSCIHomeShortcutSingleActionKey, actionIDs.firstObject, OBJC_ASSOCIATION_COPY_NONATOMIC);
		[button addTarget:target action:actionSelector forControlEvents:UIControlEventTouchUpInside];
	} else {
		UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIImageSymbolWeightRegular];
		NSMutableArray<UIAction *> *items = [NSMutableArray arrayWithCapacity:actionIDs.count];

		for (NSString *actionID in actionIDs) {
			SCIHomeShortcutAction *entry = [SCIHomeShortcutCatalog actionForID:actionID];
			if (!entry) continue;

			UIImage *icon = entry.symbol.length ? [UIImage systemImageNamed:entry.symbol withConfiguration:config] : nil;

			[items addObject:[UIAction actionWithTitle:(entry.title ?: actionID)
												 image:icon
											identifier:nil
											   handler:^(UIAction *action) {
				(void)action;
				[SCIHomeShortcutCatalog fireActionID:actionID contextView:button];
			}]];
		}

		button.menu = [UIMenu menuWithTitle:@"" children:items];
		button.showsMenuAsPrimaryAction = YES;
	}

	objc_setAssociatedObject(sigOwner, kSCIHomeShortcutSigKey, signature.copy, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static SCIChromeButton *sciPlaceButtonAfterPlus(UIView *plus, id target, SEL singleActionSelector) {
	if (!sciValidBadgeFrame(plus)) return nil;

	UIView *parent = plus.superview;
	NSArray<NSString *> *actionIDs = [SCIHomeShortcutCatalog enabledActionIDs];
	SCIChromeButton *button = objc_getAssociatedObject(parent, kSCIHomeShortcutBtnKey);

	if (!actionIDs.count) {
		sciClearInjectedButton(parent);
		return nil;
	}

	NSString *symbol = sciResolvedSymbol(actionIDs);
	CGFloat side = MAX(kSCIHomeShortcutMinSide, plus.frame.size.height);

	if (!button) {
		button = [[SCIChromeButton alloc] initWithSymbol:symbol pointSize:kSCIHomeShortcutPointSize diameter:side];
		button.translatesAutoresizingMaskIntoConstraints = YES;
		button.iconTint = UIColor.labelColor;
		button.bubbleColor = UIColor.clearColor;
		button.adjustsImageWhenHighlighted = NO;

		[parent addSubview:button];

		objc_setAssociatedObject(parent, kSCIHomeShortcutBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[sciHomeShortcutHosts() addObject:parent];
	}

	objc_setAssociatedObject(parent, kSCIHomeShortcutPlusKey, plus, OBJC_ASSOCIATION_ASSIGN);
	sciConfigureShortcutButton(button, parent, actionIDs, symbol, target, singleActionSelector);

	CGRect plusFrame = plus.frame;
	CGRect targetFrame = CGRectMake(CGRectGetMaxX(plusFrame) + kSCIHomeShortcutGap,
									plusFrame.origin.y,
									side,
									side);

	if (!CGRectEqualToRect(button.frame, targetFrame)) {
		button.frame = targetFrame;
	}

	button.alpha = plus.alpha;
	button.hidden = plus.hidden || plus.alpha <= 0.01;

	[parent bringSubviewToFront:button];
	sciShiftRightSiblings(parent, plus, button, plusFrame, targetFrame);

	return button;
}

#pragma mark - Tiny refresh

static void sciRefreshTrackedHomeShortcutHosts(void) {
	NSArray<UIView *> *hosts = nil;

	@synchronized (sciHomeShortcutHosts()) {
		hosts = sciHomeShortcutHosts().allObjects;
	}

	for (UIView *parent in hosts) {
		if (!parent || !parent.superview) {
			sciClearInjectedButton(parent);
			continue;
		}

		UIView *plus = objc_getAssociatedObject(parent, kSCIHomeShortcutPlusKey);

		if (!sciValidBadgeFrame(plus)) {
			sciClearInjectedButton(parent);
			continue;
		}

		objc_setAssociatedObject(parent, kSCIHomeShortcutSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		sciPlaceButtonAfterPlus(plus, plus, @selector(sciHomeShortcutFireSingle:));
	}
}

#pragma mark - Hook

%group SCIHomeShortcutButton

%hook IGHomeFeedHeaderView

- (void)layoutSubviews {
	%orig;

	UIView *plus = sciHomeHeaderCreateButton(self);
	if (!sciValidBadgeFrame(plus)) return;

	sciPlaceButtonAfterPlus(plus, self, @selector(sciHomeShortcutFireSingle:));
}

%new - (void)sciHomeShortcutFireSingle:(UIButton *)sender {
	NSString *actionID = objc_getAssociatedObject(sender, kSCIHomeShortcutSingleActionKey);

	if (actionID.length) {
		[SCIHomeShortcutCatalog fireActionID:actionID contextView:sender];
	}
}

%end

%end

#pragma mark - Init

%ctor {
	if ([SCIUtils getBoolPref:kSCIHomeShortcutEnabledPrefKey]) {
		%init(SCIHomeShortcutButton);

		[NSNotificationCenter.defaultCenter addObserverForName:SCIHomeShortcutConfigDidChangeNotification
														object:nil
														 queue:NSOperationQueue.mainQueue
													usingBlock:^(NSNotification *note) {
			(void)note;
			sciRefreshTrackedHomeShortcutHosts();
		}];
	}
}