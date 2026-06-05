// Injects a native-style shortcut IGBadgeButton into IGHomeFeedHeaderView.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../UI/SCIIcon.h"
#import "SCIHomeShortcutCatalog.h"
#import <objc/runtime.h>

static const void *kSCIHomeShortcutBtnKey = &kSCIHomeShortcutBtnKey;
static const void *kSCIHomeShortcutSigKey = &kSCIHomeShortcutSigKey;
static const void *kSCIHomeShortcutSingleActionKey = &kSCIHomeShortcutSingleActionKey;

static CGFloat const kSCIHomeShortcutPointSize = 20.0;

static UIView *sciIvarView(id obj, const char *name) {
	Ivar ivar = class_getInstanceVariable([obj class], name);
	id view = ivar ? object_getIvar(obj, ivar) : nil;
	return [view isKindOfClass:UIView.class] ? view : nil;
}

static NSString *sciResolvedSymbol(NSArray<NSString *> *actionIDs) {
	NSString *userIcon = [SCIUtils getStringPref:kSCIHomeShortcutIconPrefKey];

	if (userIcon.length && ![userIcon isEqualToString:@"auto"]) return userIcon;

	if (actionIDs.count == 1) {
		SCIHomeShortcutAction *action = [SCIHomeShortcutCatalog actionForID:actionIDs.firstObject];
		return action.symbol.length ? action.symbol : @"ellipsis.circle.fill";
	}

	return @"ellipsis.circle.fill";
}

static NSString *sciShortcutSignature(NSArray<NSString *> *actionIDs, NSString *symbol) {
	return [NSString stringWithFormat:@"%@|%@", symbol ?: @"", [actionIDs componentsJoinedByString:@","]];
}

static void sciRemoveShortcut(UIView *header) {
	UIButton *button = objc_getAssociatedObject(header, kSCIHomeShortcutBtnKey);

	[button removeFromSuperview];

	objc_setAssociatedObject(header, kSCIHomeShortcutSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(button, kSCIHomeShortcutSingleActionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void sciConfigureShortcut(UIButton *button, UIView *owner, NSArray<NSString *> *actionIDs, NSString *symbol) {
	NSString *signature = sciShortcutSignature(actionIDs, symbol);
	NSString *oldSignature = objc_getAssociatedObject(owner, kSCIHomeShortcutSigKey);

	if ([oldSignature isEqualToString:signature]) return;

	[button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

	button.menu = nil;
	button.showsMenuAsPrimaryAction = NO;
	button.adjustsImageWhenHighlighted = YES;
	button.accessibilityLabel = @"RyukGram";
	button.tintColor = UIColor.labelColor;

	[button setImage:[SCIIcon imageNamed:symbol pointSize:kSCIHomeShortcutPointSize weight:UIImageSymbolWeightRegular] forState:UIControlStateNormal];

	objc_setAssociatedObject(button, kSCIHomeShortcutSingleActionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	if (actionIDs.count == 1) {
		objc_setAssociatedObject(button, kSCIHomeShortcutSingleActionKey, actionIDs.firstObject, OBJC_ASSOCIATION_COPY_NONATOMIC);
		[button addTarget:owner action:@selector(sciHomeShortcutFireSingle:) forControlEvents:UIControlEventTouchUpInside];
	} else {
		NSMutableArray<UIAction *> *items = [NSMutableArray arrayWithCapacity:actionIDs.count];

		for (NSString *actionID in actionIDs) {
			SCIHomeShortcutAction *entry = [SCIHomeShortcutCatalog actionForID:actionID];
			if (!entry) continue;

			UIImage *icon = entry.symbol.length ? [SCIIcon imageNamed:entry.symbol pointSize:18.0 weight:UIImageSymbolWeightRegular] : nil;

			[items addObject:[UIAction actionWithTitle:(entry.title ?: actionID)
												 image:icon
											identifier:nil
											   handler:^(__unused UIAction *action) {
				[SCIHomeShortcutCatalog fireActionID:actionID contextView:button];
			}]];
		}

		button.menu = [UIMenu menuWithTitle:@"" children:items];
		button.showsMenuAsPrimaryAction = YES;
	}

	objc_setAssociatedObject(owner, kSCIHomeShortcutSigKey, signature.copy, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

static UIButton *sciShortcutButton(UIView *header, UIView *anchor) {
	NSArray<NSString *> *actionIDs = [SCIHomeShortcutCatalog enabledActionIDs];

	if (!actionIDs.count || !anchor.superview) {
		sciRemoveShortcut(header);
		return nil;
	}

	UIButton *button = objc_getAssociatedObject(header, kSCIHomeShortcutBtnKey);

	if (!button) {
		button = [[%c(IGBadgeButton) alloc] init];

		if (![button isKindOfClass:UIButton.class]) return nil;

		objc_setAssociatedObject(header, kSCIHomeShortcutBtnKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	if (button.superview != anchor.superview) {
		[button removeFromSuperview];
		[anchor.superview addSubview:button];
	}

	button.hidden = NO;
	button.alpha = 1.0;

	sciConfigureShortcut(button, header, actionIDs, sciResolvedSymbol(actionIDs));
	return button;
}

static NSArray *sciButtonsByAddingShortcut(UIView *header, NSArray *buttons) {
	if (!buttons.count) {
		sciRemoveShortcut(header);
		return buttons;
	}

	UIView *createButton = sciIvarView(header, "_createButton");
	NSUInteger createIndex = createButton ? [buttons indexOfObject:createButton] : NSNotFound;
	UIView *anchor = createIndex != NSNotFound ? createButton : buttons.firstObject;
	UIButton *button = sciShortcutButton(header, anchor);

	if (!button || [buttons containsObject:button]) return buttons;

	NSMutableArray *items = buttons.mutableCopy;
	NSUInteger insertIndex = createIndex != NSNotFound ? createIndex + 1 : 0;

	[items insertObject:button atIndex:insertIndex];

	return items;
}

%group SCIHomeShortcutButton

%hook IGHomeFeedHeaderView

- (NSArray *)_visibleRightButtons {
	return sciButtonsByAddingShortcut((UIView *)self, %orig);
}

%new - (void)sciHomeShortcutFireSingle:(UIButton *)sender {
	NSString *actionID = objc_getAssociatedObject(sender, kSCIHomeShortcutSingleActionKey);

	if (actionID.length) {
		[SCIHomeShortcutCatalog fireActionID:actionID contextView:sender];
	}
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:kSCIHomeShortcutEnabledPrefKey]) {
		%init(SCIHomeShortcutButton);
	}
}