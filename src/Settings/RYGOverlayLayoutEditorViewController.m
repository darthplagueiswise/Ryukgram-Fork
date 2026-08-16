#import "RYGOverlayLayoutEditorViewController.h"
#import "../UI/DragLayout/RYGOverlayButtonLayout.h"
#import "../UI/RYGIcon.h"
#import "../Utils.h"

#pragma mark - Preview mock (full-screen media + reply bar)

@interface RYGOverlayMockView : UIView
@property (nonatomic, assign) CGFloat bottomFraction;
@end

@implementation RYGOverlayMockView {
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
	_replyLabel.text = RYGLocalized(@"Send message");
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

	CGFloat progressY = h * 0.010;
	_progress.frame = CGRectMake(pad, progressY, w - pad * 2.0, MAX(2.0, h * 0.004));
	_progress.layer.cornerRadius = _progress.bounds.size.height / 2.0;

	CGFloat avatarD = h * 0.030;
	CGFloat avatarY = h * 0.020;
	_avatar.frame = CGRectMake(pad, avatarY, avatarD, avatarD);
	_avatar.layer.cornerRadius = avatarD / 2.0;
	CGFloat nameH = MAX(6.0, avatarD * 0.26);
	_nameBar.frame = CGRectMake(pad + avatarD + 8.0, avatarY + (avatarD - nameH) / 2.0, w * 0.4, nameH);

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

@interface RYGOverlayLayoutEditorViewController ()
@property (nonatomic, assign) Class layoutClass;
@end

@implementation RYGOverlayLayoutEditorViewController

static NSArray<RYGDragLayoutItem *> *rygBuildItems(Class L) {
	NSArray<NSString *> *ids = [L allIDs];
	NSDictionary<NSString *, NSValue *> *resolved = [L resolvedPositionsForIDs:ids inSize:[L referenceSize]];
	NSMutableArray *items = NSMutableArray.array;
	for (NSString *bid in ids) {
		UIImage *icon = [RYGIcon imageNamed:[L iconForID:bid] pointSize:20];
		CGPoint pos = resolved[bid] ? resolved[bid].CGPointValue : [L nearestSlotTo:[L positionForID:bid]];
		RYGDragLayoutItem *item = [RYGDragLayoutItem itemWithIdentifier:bid icon:icon title:nil position:pos];
		item.diameter = [L diameterForID:bid];
		item.disabled = ![L idEnabled:bid];
		[items addObject:item];
	}
	return items;
}

- (instancetype)initWithLayoutClass:(Class)layoutClass {
	if (!(self = [super initWithItems:rygBuildItems(layoutClass)])) return nil;
	_layoutClass = layoutClass;

	self.title = RYGLocalized(@"Overlay layout");
	self.placeableInsets = [layoutClass placeableInsetsNormalized];
	self.slots = [layoutClass slotPositions];
	self.showsSlots = NO;
	self.scalesItemsToCanvas = YES;

	// Match the canonical portrait story aspect, never the device window.
	CGSize ref = [layoutClass referenceSize];
	if (ref.width > 0 && ref.height > 0) self.canvasAspect = ref.width / ref.height;
	self.referenceWidth = ref.width;
	self.instructions = RYGLocalized(@"Drag the buttons onto the story. The dimmed strip is the reply bar.");

	RYGOverlayMockView *mock = [RYGOverlayMockView new];
	mock.bottomFraction = self.placeableInsets.bottom;
	self.backgroundContentView = mock;

	Class L = layoutClass;
	self.onChange = ^(NSArray<RYGDragLayoutItem *> *items) {
		for (RYGDragLayoutItem *item in items) [L setPosition:item.position forID:item.identifier];
	};

	__weak typeof(self) weakSelf = self;
	self.onReset = ^{
		[L reset];
		[weakSelf applyItems:rygBuildItems(L)];
	};

	return self;
}

@end
