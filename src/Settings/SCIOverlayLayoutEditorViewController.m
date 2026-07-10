#import "SCIOverlayLayoutEditorViewController.h"
#import "../UI/DragLayout/SCIOverlayButtonLayout.h"
#import "../UI/SCIIcon.h"
#import "../Utils.h"

#pragma mark - Preview mock (full-screen media + reply bar)

@interface SCIOverlayMockView : UIView
@property (nonatomic, assign) CGFloat bottomFraction;
@end

@implementation SCIOverlayMockView {
	CAGradientLayer *_gradient;
	UIView *_progress, *_avatar, *_nameBar, *_replyPill;
	UILabel *_replyLabel;
	UIImageView *_heart, *_share;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;

	_gradient = [CAGradientLayer layer];
	_gradient.colors = @[(id)[UIColor colorWithRed:0.36 green:0.20 blue:0.55 alpha:1.0].CGColor,
						  (id)[UIColor colorWithRed:0.12 green:0.10 blue:0.22 alpha:1.0].CGColor];
	_gradient.startPoint = CGPointMake(0.2, 0.0);
	_gradient.endPoint = CGPointMake(0.8, 1.0);
	[self.layer addSublayer:_gradient];

	_progress = [self barWithAlpha:0.9];
	_avatar = [UIView new];
	_avatar.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.85];
	[self addSubview:_avatar];
	_nameBar = [self barWithAlpha:0.5];

	_replyPill = [UIView new];
	_replyPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
	_replyPill.layer.borderWidth = 1.0;
	[self addSubview:_replyPill];

	_replyLabel = [UILabel new];
	_replyLabel.text = SCILocalized(@"Send message");
	_replyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
	_replyLabel.font = [UIFont systemFontOfSize:11.0];
	[self addSubview:_replyLabel];

	_heart = [self glyph:@"heart"];
	_share = [self glyph:@"paperplane"];
	return self;
}

- (UIImageView *)glyph:(NSString *)name {
	UIImageView *v = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:name] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
	v.tintColor = [UIColor colorWithWhite:1.0 alpha:0.85];
	v.contentMode = UIViewContentModeScaleAspectFit;
	[self addSubview:v];
	return v;
}

- (UIView *)barWithAlpha:(CGFloat)a {
	UIView *v = [UIView new];
	v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:a];
	v.layer.cornerRadius = 2.0;
	[self addSubview:v];
	return v;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_gradient.frame = self.bounds;

	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;
	CGFloat pad = 12.0;

	_progress.frame = CGRectMake(pad, 10.0, w - pad * 2.0, 3.0);
	_progress.layer.cornerRadius = 1.5;

	CGFloat avatarD = 30.0;
	_avatar.frame = CGRectMake(pad, 22.0, avatarD, avatarD);
	_avatar.layer.cornerRadius = avatarD / 2.0;
	_nameBar.frame = CGRectMake(pad + avatarD + 8.0, 22.0 + avatarD / 2.0 - 4.0, w * 0.4, 8.0);

	CGFloat bandH = h * MAX(self.bottomFraction, 0.001);
	CGFloat bandTop = h - bandH;
	CGFloat pillH = MAX(20.0, MIN(32.0, bandH - 6.0));
	CGFloat rowY = bandTop + (bandH - pillH) / 2.0;
	CGFloat iconD = pillH * 0.7;
	CGFloat pillW = w - pad * 2.0 - (iconD + 10.0) * 2.0;

	_replyPill.frame = CGRectMake(pad, rowY, pillW, pillH);
	_replyPill.layer.cornerRadius = pillH / 2.0;
	_replyLabel.frame = CGRectMake(pad + 12.0, rowY, pillW - 18.0, pillH);
	_heart.frame = CGRectMake(CGRectGetMaxX(_replyPill.frame) + 10.0, rowY + (pillH - iconD) / 2.0, iconD, iconD);
	_share.frame = CGRectMake(CGRectGetMaxX(_heart.frame) + 10.0, rowY + (pillH - iconD) / 2.0, iconD, iconD);
}

@end

#pragma mark - Editor

@interface SCIOverlayLayoutEditorViewController ()
@property (nonatomic, assign) Class layoutClass;
@end

@implementation SCIOverlayLayoutEditorViewController

static NSArray<SCIDragLayoutItem *> *sciBuildItems(Class L) {
	NSMutableArray *items = NSMutableArray.array;
	for (NSString *bid in [L allIDs]) {
		UIImage *icon = [SCIIcon imageNamed:[L iconForID:bid] pointSize:20];
		SCIDragLayoutItem *item = [SCIDragLayoutItem itemWithIdentifier:bid
																   icon:icon
																  title:nil
															   position:[L nearestSlotTo:[L positionForID:bid]]];
		item.diameter = [L diameterForID:bid];
		item.disabled = ![L idEnabled:bid];
		[items addObject:item];
	}
	return items;
}

- (instancetype)initWithLayoutClass:(Class)layoutClass {
	if (!(self = [super initWithItems:sciBuildItems(layoutClass)])) return nil;
	_layoutClass = layoutClass;

	self.title = SCILocalized(@"Overlay layout");
	self.placeableInsets = [layoutClass placeableInsetsNormalized];
	self.slots = [layoutClass slotPositions];
	self.showsSlots = NO;
	self.scalesItemsToCanvas = YES;

	// Buttons render over the real story safe area, not the full screen, so make the
	// canvas match the safe-area aspect — otherwise vertical gaps stretch in preview.
	UIWindow *kw = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if (![s isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)s).windows) { if (w.isKeyWindow) { kw = w; break; } }
		if (kw) break;
	}
	if (kw) {
		UIEdgeInsets ins = kw.safeAreaInsets;
		CGFloat sw = kw.bounds.size.width - ins.left - ins.right;
		CGFloat sh = kw.bounds.size.height - ins.top - ins.bottom;
		if (sw > 0 && sh > 0) self.canvasAspect = sw / sh;
	}
	self.instructions = SCILocalized(@"Drag the buttons onto the story. The dimmed strip is the reply bar.");

	SCIOverlayMockView *mock = [SCIOverlayMockView new];
	mock.bottomFraction = self.placeableInsets.bottom;
	self.backgroundContentView = mock;

	Class L = layoutClass;
	self.onChange = ^(NSArray<SCIDragLayoutItem *> *items) {
		for (SCIDragLayoutItem *item in items) [L setPosition:item.position forID:item.identifier];
	};

	__weak typeof(self) weakSelf = self;
	self.onReset = ^{
		[L reset];
		[weakSelf applyItems:sciBuildItems(L)];
	};

	return self;
}

@end
