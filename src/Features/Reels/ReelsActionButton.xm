// Reels action button — injects a RyukGram action button above the reel's
// vertical like/comment/share sidebar (IGSundialViewerVerticalUFI).

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGIcon.h"
#import "../../ActionButton/RYGActionButton.h"
#import "../../ActionButton/RYGActionIcon.h"
#import "../../ActionButton/RYGMediaActions.h"
#import <objc/runtime.h>

static const NSInteger kReelActionBtnTag = 1337;
static const NSInteger kReelActionHitTag = 1338;

static char kReelActionDefaultKey;
static char kReelContextInteractionKey;
static char kReelVisibleButtonKey;

@interface RYGReelHitButton : UIButton
@end

@implementation RYGReelHitButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
	return CGRectContainsPoint(CGRectInset(self.bounds, -24.0, -24.0), point);
}

- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:NO];
	self.backgroundColor = UIColor.clearColor;
	self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

- (void)setSelected:(BOOL)selected {
	[super setSelected:NO];
	self.backgroundColor = UIColor.clearColor;
	self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

@end

static inline BOOL RYGReelsActionEnabled(void) {
	return [RYGUtils getBoolPref:@"reels_action_button"];
}

static inline NSString *RYGReelDefaultAction(void) {
	return [RYGUtils getStringPref:@"reels_action_default"];
}

static inline NSString *RYGReelActionOrMenu(void) {
	NSString *action = RYGReelDefaultAction();
	return action.length ? action : @"menu";
}

static UIColor *rygNativeReelColor(IGSundialViewerVerticalUFI *ufi) {
	UIButton *like = (UIButton *)ufi.ufiLikeButton;
	UIColor *tint = like.imageView.tintColor;
	return tint ?: UIColor.whiteColor;
}

static void rygApplyReelIconColor(RYGChromeButton *button, UIColor *color) {
	if (!button) return;

	button.hidden = NO;
	button.alpha = 1.0;
	button.userInteractionEnabled = NO;
	button.bubbleColor = UIColor.clearColor;
	button.iconView.hidden = NO;
	button.iconView.alpha = 1.0;

	// Colour pet sprites carry their own colours — don't tint/templatize them.
	if ([RYGIcon isPetAssetName:button.symbolName]) return;

	if (!color) color = UIColor.whiteColor;
	button.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
	button.iconTint = color;
	button.iconView.tintColor = color;
	button.iconView.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
	button.iconView.highlighted = NO;

	if (button.iconView.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
		button.iconView.image = [button.iconView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	}
}

static UIView *rygFindSuperviewOfClass(UIView *view, NSString *className) {
	Class cls = NSClassFromString(className);
	if (!view || !cls) return nil;

	for (UIView *current = view.superview; current; current = current.superview) {
		if ([current isKindOfClass:cls]) return current;
	}

	return nil;
}

static id rygFindMediaIvar(UIView *view) {
	Class mediaClass = NSClassFromString(@"IGMedia");
	if (!view || !mediaClass) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList(view.class, &count);
	id found = nil;

	for (unsigned int i = 0; i < count && !found; i++) {
		const char *type = ivar_getTypeEncoding(ivars[i]);
		if (!type || type[0] != '@') continue;

		@try {
			id value = object_getIvar(view, ivars[i]);
			if ([value isKindOfClass:mediaClass]) found = value;
		} @catch (__unused id e) {}
	}

	if (ivars) free(ivars);
	return found;
}

static NSInteger rygCarouselIndex(UIView *cell) {
	NSInteger index = 0;

	Ivar ivar = class_getInstanceVariable(cell.class, "_currentIndex");
	if (ivar) index = *(NSInteger *)((char *)(__bridge void *)cell + ivar_getOffset(ivar));

	ivar = class_getInstanceVariable(cell.class, "_currentFractionalIndex");
	if (ivar) {
		NSInteger rounded = (NSInteger)round(*(double *)((char *)(__bridge void *)cell + ivar_getOffset(ivar)));
		if (rounded > index) index = rounded;
	}

	ivar = class_getInstanceVariable(cell.class, "_collectionView");
	if (ivar) {
		UICollectionView *collectionView = object_getIvar(cell, ivar);
		CGFloat width = collectionView.bounds.size.width;

		if (collectionView && width > 0.0) {
			NSInteger cvIndex = (NSInteger)round(collectionView.contentOffset.x / width);
			if (cvIndex > index) index = cvIndex;
		}
	}

	return index;
}

static id rygReelsMediaProvider(UIView *sourceView) {
	UIView *cell = rygFindSuperviewOfClass(sourceView, @"IGSundialViewerVideoCell") ?: rygFindSuperviewOfClass(sourceView, @"IGSundialViewerPhotoCell");

	if (cell) {
		id media = rygFindMediaIvar(cell);
		if (media) return media;
	}

	UIView *carousel = rygFindSuperviewOfClass(sourceView, @"IGSundialViewerCarouselCell");
	id parent = rygFindMediaIvar(carousel);
	if (!parent) return nil;

	NSArray *children = [RYGMediaActions carouselChildrenForMedia:parent];
	NSInteger index = rygCarouselIndex(carousel);

	return (index >= 0 && (NSUInteger)index < children.count) ? children[index] : parent;
}

static void rygClearHit(UIButton *hit) {
	if (!hit) return;

	hit.highlighted = NO;
	hit.selected = NO;
	hit.opaque = NO;
	hit.alpha = 1.0;
	hit.backgroundColor = UIColor.clearColor;
	hit.layer.backgroundColor = UIColor.clearColor.CGColor;
	hit.adjustsImageWhenHighlighted = NO;
}

static void rygBounceVisibleButton(UIButton *hit) {
	UIView *button = objc_getAssociatedObject(hit, &kReelVisibleButtonKey);
	if (button) [RYGActionButton bounceButton:button];
}

@interface RYGReelMenuTarget : NSObject <UIContextMenuInteractionDelegate>
+ (instancetype)shared;
- (void)touchDown:(UIButton *)sender;
- (void)tapped:(UIButton *)sender;
@end

@implementation RYGReelMenuTarget

+ (instancetype)shared {
	static RYGReelMenuTarget *target;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		target = [RYGReelMenuTarget new];
	});
	return target;
}

- (void)touchDown:(UIButton *)sender {
	rygBounceVisibleButton(sender);
}

- (void)tapped:(UIButton *)sender {
	UIContextMenuInteraction *interaction = objc_getAssociatedObject(sender, &kReelContextInteractionKey);
	if (!interaction) return;

	CGPoint point = CGPointMake(CGRectGetMidX(sender.bounds), CGRectGetMidY(sender.bounds));
	SEL selector = NSSelectorFromString(@"_presentMenuAtLocation:");

	if ([interaction respondsToSelector:selector]) {
		((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, selector, point);
		return;
	}

	selector = NSSelectorFromString(@"presentMenuAtLocation:");

	if ([interaction respondsToSelector:selector]) {
		((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, selector, point);
	}
}

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
						configurationForMenuAtLocation:(CGPoint)location {
	UIView *view = interaction.view;
	if (!view) return nil;

	return [UIContextMenuConfiguration configurationWithIdentifier:nil
												   previewProvider:nil
													actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
		return [RYGActionButton deferredMenuForContext:RYGActionContextReels
											  fromView:view
										 mediaProvider:^id (UIView *sourceView) {
			return rygReelsMediaProvider(sourceView);
		}];
	}];
}

@end

static void rygConfigureMenuHit(UIButton *hit, RYGChromeButton *button) {
	if (!hit || !button) return;

	objc_setAssociatedObject(hit, &kReelVisibleButtonKey, button, OBJC_ASSOCIATION_ASSIGN);

	[hit addTarget:RYGReelMenuTarget.shared action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
	[hit addTarget:RYGReelMenuTarget.shared action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];

	UIContextMenuInteraction *interaction = [[UIContextMenuInteraction alloc] initWithDelegate:RYGReelMenuTarget.shared];
	[hit addInteraction:interaction];

	objc_setAssociatedObject(hit, &kReelContextInteractionKey, interaction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(hit, &kReelActionDefaultKey, RYGReelDefaultAction() ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);

	rygClearHit(hit);
}

static void rygConfigureActionHit(UIButton *hit, RYGChromeButton *button) {
	if (!hit || !button) return;

	objc_setAssociatedObject(hit, &kReelVisibleButtonKey, button, OBJC_ASSOCIATION_ASSIGN);

	[RYGActionButton configureButton:hit
							 context:RYGActionContextReels
							 prefKey:@"reels_action_default"
					   mediaProvider:^id (UIView *sourceView) {
		return rygReelsMediaProvider(sourceView);
	}];

	[hit addTarget:RYGReelMenuTarget.shared action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];

	objc_setAssociatedObject(hit, &kReelActionDefaultKey, RYGReelDefaultAction() ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);

	rygClearHit(hit);
}

static void rygConfigureHit(UIButton *hit, RYGChromeButton *button) {
	if ([RYGReelActionOrMenu() isEqualToString:@"menu"]) {
		rygConfigureMenuHit(hit, button);
	} else {
		rygConfigureActionHit(hit, button);
	}
}

static void rygRemoveReelButton(UIView *root) {
	[[root viewWithTag:kReelActionHitTag] removeFromSuperview];
	[[root viewWithTag:kReelActionBtnTag] removeFromSuperview];
}

%hook _TtC26IGSundialViewerVerticalUFI26IGSundialViewerVerticalUFI

- (void)layoutSubviews {
	%orig;
	((void(*)(id, SEL))objc_msgSend)(self, @selector(rygReloadReelActionButton));
}

%new
- (void)rygReloadReelActionButton {
	if (!self.superview) return;

	RYGChromeButton *button = (RYGChromeButton *)[self viewWithTag:kReelActionBtnTag];
	UIButton *hit = (UIButton *)[self viewWithTag:kReelActionHitTag];

	if (![button isKindOfClass:RYGChromeButton.class]) button = nil;
	if (![hit isKindOfClass:UIButton.class]) hit = nil;

	if (!RYGReelsActionEnabled()) {
		rygRemoveReelButton(self);
		return;
	}

	NSString *currentAction = RYGReelDefaultAction() ?: @"";
	NSString *configuredAction = objc_getAssociatedObject(hit, &kReelActionDefaultKey);

	if (hit && configuredAction && ![configuredAction isEqualToString:currentAction]) {
		[hit removeFromSuperview];
		hit = nil;
	}

	if (!button) {
		button = [[RYGChromeButton alloc] initWithSymbol:@"" pointSize:0 diameter:40];
		button.tag = kReelActionBtnTag;
		button.bubbleColor = UIColor.clearColor;
		button.adjustsImageWhenHighlighted = NO;
		button.userInteractionEnabled = NO;
		button.menu = nil;
		button.showsMenuAsPrimaryAction = NO;

		self.clipsToBounds = NO;
		[self addSubview:button];

		[NSLayoutConstraint activateConstraints:@[
			[button.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
			[button.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-10.0],
			[button.widthAnchor constraintEqualToConstant:40.0],
			[button.heightAnchor constraintEqualToConstant:40.0]
		]];

		[RYGActionIcon attachAutoUpdate:button source:RYGActionSourceReels pointSize:24 style:RYGActionIconStyleShadowBaked];

		if (button.iconView.image && ![RYGIcon isPetAssetName:button.symbolName]) {
			button.iconView.image = [button.iconView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
		}
	}

	if (!hit) {
		hit = [RYGReelHitButton buttonWithType:UIButtonTypeCustom];
		hit.tag = kReelActionHitTag;
		hit.translatesAutoresizingMaskIntoConstraints = NO;
		rygClearHit(hit);

		[self addSubview:hit];

		[NSLayoutConstraint activateConstraints:@[
			[hit.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
			[hit.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
			[hit.widthAnchor constraintEqualToConstant:1.0],
			[hit.heightAnchor constraintEqualToConstant:1.0]
		]];

		rygConfigureHit(hit, button);
	}

	button.transform = CGAffineTransformIdentity;
	rygApplyReelIconColor(button, rygNativeReelColor(self));

	hit.hidden = NO;
	rygClearHit(hit);

	[self bringSubviewToFront:button];
	[self bringSubviewToFront:hit];
}

%end