#import "SCIDragLayoutEditor.h"
#import "../SCIPopupChrome.h"
#import "../../Utils.h"

@implementation SCIDragLayoutItem

+ (instancetype)itemWithIdentifier:(NSString *)identifier icon:(UIImage *)icon title:(NSString *)title position:(CGPoint)position {
	SCIDragLayoutItem *item = [self new];
	item.identifier = identifier;
	item.icon = icon;
	item.title = title;
	item.position = position;
	item.homePosition = CGPointMake(-1.0, -1.0);
	item.diameter = 44.0;
	return item;
}

@end

@interface SCIDragLayoutChip : UIView
@property (nonatomic, strong) SCIDragLayoutItem *item;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIView *bar1;
@property (nonatomic, strong) UIView *bar2;
@property (nonatomic, assign) CGPoint dragStart;
@property (nonatomic, assign) CGFloat displayScale;
@end

@implementation SCIDragLayoutChip

- (BOOL)isPill { return self.item.width > self.item.diameter; }

- (instancetype)initWithItem:(SCIDragLayoutItem *)item {
	if (!(self = [super initWithFrame:CGRectZero])) return nil;
	_item = item;
	_displayScale = 1.0;

	_bubble = [UIView new];
	_bubble.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
	_bubble.userInteractionEnabled = NO;
	[self addSubview:_bubble];

	_iconView = [UIImageView new];
	_iconView.contentMode = UIViewContentModeScaleAspectFit;
	_iconView.tintColor = UIColor.whiteColor;
	_iconView.image = [item.icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	[_bubble addSubview:_iconView];

	if (self.isPill) {
		_bar1 = [self barWithAlpha:0.85];
		_bar2 = [self barWithAlpha:0.45];
	}

	self.alpha = item.disabled ? 0.4 : 1.0;
	return self;
}

- (UIView *)barWithAlpha:(CGFloat)a {
	UIView *v = [UIView new];
	v.backgroundColor = [UIColor colorWithWhite:1.0 alpha:a];
	v.layer.cornerRadius = 2.0;
	[self.bubble addSubview:v];
	return v;
}

- (CGSize)chipSize {
	CGFloat s = self.displayScale > 0.0 ? self.displayScale : 1.0;
	CGFloat h = self.item.diameter * s;
	return CGSizeMake(self.isPill ? self.item.width * s : h, h);
}

- (void)layoutChrome {
	CGFloat s = self.displayScale > 0.0 ? self.displayScale : 1.0;
	CGFloat h = self.item.diameter * s;
	self.bubble.layer.cornerRadius = h / 2.0;

	if (self.isPill) {
		self.bubble.frame = self.bounds;
		CGFloat iconD = h * 0.5;
		CGFloat pad = h * 0.28;
		self.iconView.frame = CGRectMake(pad, (h - iconD) / 2.0, iconD, iconD);

		CGFloat barX = CGRectGetMaxX(self.iconView.frame) + 8.0;
		CGFloat barW = self.bounds.size.width - barX - pad;
		self.bar1.frame = CGRectMake(barX, h * 0.32, barW, 4.0);
		self.bar2.frame = CGRectMake(barX, h * 0.56, barW * 0.6, 4.0);
		return;
	}

	self.bubble.frame = CGRectMake((self.bounds.size.width - h) / 2.0, 0, h, h);
	CGFloat inset = h * 0.28;
	self.iconView.frame = CGRectInset(self.bubble.bounds, inset, inset);
}

@end

@interface SCIDragLayoutEditorViewController ()
@property (nonatomic, strong) NSMutableArray<SCIDragLayoutItem *> *mutableItems;
@property (nonatomic, strong) UIView *canvas;
@property (nonatomic, strong) NSMutableArray<SCIDragLayoutChip *> *chips;
@property (nonatomic, strong) UIView *vGuide;
@property (nonatomic, strong) UIView *hGuide;
@property (nonatomic, strong) CAShapeLayer *blockedFill;
@property (nonatomic, strong) CAShapeLayer *placeableBorder;
@property (nonatomic, strong) CAShapeLayer *homeMarkers;
@property (nonatomic, strong) CAShapeLayer *slotDots;
@property (nonatomic, strong) CAShapeLayer *slotHighlight;
@property (nonatomic, weak) SCIDragLayoutChip *draggingChip;
@property (nonatomic, assign) CGFloat canvasScale;
@end

@implementation SCIDragLayoutEditorViewController

- (instancetype)initWithItems:(NSArray<SCIDragLayoutItem *> *)items {
	if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
	_mutableItems = [items mutableCopy] ?: NSMutableArray.array;
	_chips = NSMutableArray.array;
	_canvasAspect = 9.0 / 19.5;
	_canvasCornerRadius = 28.0;
	_snapMask = SCIDragLayoutSnapAll;
	_gridDivisions = 6;
	_placeableInsets = UIEdgeInsetsZero;
	_showsSlots = YES;
	return self;
}

- (NSArray<SCIDragLayoutItem *> *)items { return self.mutableItems.copy; }

- (void)viewDidLoad {
	[super viewDidLoad];

	self.view.backgroundColor = [SCIPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;

	self.canvas = [UIView new];
	self.canvas.backgroundColor = UIColor.blackColor;
	self.canvas.layer.cornerRadius = self.canvasCornerRadius;
	self.canvas.layer.masksToBounds = YES;
	self.canvas.layer.borderWidth = 1.0;
	self.canvas.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
	[self.view addSubview:self.canvas];

	if (self.backgroundContentView) {
		self.backgroundContentView.userInteractionEnabled = NO;
		[self.canvas addSubview:self.backgroundContentView];
	}

	if (!UIEdgeInsetsEqualToEdgeInsets(self.placeableInsets, UIEdgeInsetsZero)) {
		self.blockedFill = [CAShapeLayer layer];
		self.blockedFill.fillRule = kCAFillRuleEvenOdd;
		self.blockedFill.fillColor = [UIColor colorWithWhite:0.0 alpha:0.4].CGColor;
		[self.canvas.layer addSublayer:self.blockedFill];

		self.placeableBorder = [CAShapeLayer layer];
		self.placeableBorder.fillColor = UIColor.clearColor.CGColor;
		self.placeableBorder.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
		self.placeableBorder.lineWidth = 1.0;
		self.placeableBorder.lineDashPattern = @[@6, @4];
		[self.canvas.layer addSublayer:self.placeableBorder];
	}

	if (self.slots.count && self.showsSlots) {
		self.slotDots = [CAShapeLayer layer];
		self.slotDots.fillColor = UIColor.clearColor.CGColor;
		self.slotDots.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
		self.slotDots.lineWidth = 1.0;
		[self.canvas.layer addSublayer:self.slotDots];

		self.slotHighlight = [CAShapeLayer layer];
		self.slotHighlight.fillColor = [[SCIUtils SCIColor_Primary] colorWithAlphaComponent:0.25].CGColor;
		self.slotHighlight.strokeColor = [SCIUtils SCIColor_Primary].CGColor;
		self.slotHighlight.lineWidth = 2.0;
		self.slotHighlight.opacity = 0.0;
		[self.canvas.layer addSublayer:self.slotHighlight];
	} else if (!self.slots.count) {
		self.homeMarkers = [CAShapeLayer layer];
		self.homeMarkers.fillColor = UIColor.clearColor.CGColor;
		self.homeMarkers.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
		self.homeMarkers.lineWidth = 1.5;
		self.homeMarkers.lineDashPattern = @[@3, @3];
		[self.canvas.layer addSublayer:self.homeMarkers];
	}

	self.vGuide = [self makeGuide];
	self.hGuide = [self makeGuide];

	if (self.instructions.length) {
		UILabel *hint = [UILabel new];
		hint.text = self.instructions;
		hint.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
		hint.textColor = UIColor.secondaryLabelColor;
		hint.textAlignment = NSTextAlignmentCenter;
		hint.numberOfLines = 0;
		hint.tag = 7788;
		[self.view addSubview:hint];
	}

	if (self.onReset) {
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:SCILocalized(@"Reset")
																				 style:UIBarButtonItemStylePlain
																				target:self
																				action:@selector(resetTapped)];
	}

	[self rebuildChips];
}

- (UIView *)makeGuide {
	UIView *g = [UIView new];
	g.backgroundColor = [SCIUtils SCIColor_Primary] ?: UIColor.systemYellowColor;
	g.alpha = 0.0;
	g.userInteractionEnabled = NO;
	[self.canvas addSubview:g];
	return g;
}

- (void)applyItems:(NSArray<SCIDragLayoutItem *> *)items {
	self.mutableItems = [items mutableCopy] ?: NSMutableArray.array;
	[self rebuildChips];
}

- (void)rebuildChips {
	for (SCIDragLayoutChip *c in self.chips) [c removeFromSuperview];
	[self.chips removeAllObjects];

	for (SCIDragLayoutItem *item in self.mutableItems) {
		SCIDragLayoutChip *chip = [[SCIDragLayoutChip alloc] initWithItem:item];
		UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
		[chip addGestureRecognizer:pan];
		[self.canvas addSubview:chip];
		[self.chips addObject:chip];
	}

	[self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
	CGFloat pad = 20.0;
	CGFloat hintH = 0.0;

	UILabel *hint = (UILabel *)[self.view viewWithTag:7788];
	if (hint) {
		CGFloat w = safe.size.width - pad * 2.0;
		CGSize fit = [hint sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)];
		hintH = fit.height + 12.0;
		hint.frame = CGRectMake(safe.origin.x + pad, CGRectGetMaxY(safe) - fit.height - 8.0, w, fit.height);
	}

	CGFloat availW = safe.size.width - pad * 2.0;
	CGFloat availH = safe.size.height - pad * 2.0 - hintH;

	CGFloat h = availH;
	CGFloat w = h * self.canvasAspect;
	if (w > availW) { w = availW; h = w / self.canvasAspect; }

	CGFloat x = safe.origin.x + (safe.size.width - w) / 2.0;
	CGFloat y = safe.origin.y + pad + (availH - h) / 2.0;
	self.canvas.frame = CGRectMake(x, y, w, h);
	self.backgroundContentView.frame = self.canvas.bounds;

	// Scale chips by canvas/real-screen ratio so preview spacing matches the real overlay.
	CGFloat refW = MIN(UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
	self.canvasScale = (self.scalesItemsToCanvas && refW > 0) ? w / refW : 1.0;
	for (SCIDragLayoutChip *chip in self.chips) chip.displayScale = self.canvasScale;

	if (self.blockedFill) {
		CGRect pr = [self placeableRect];
		UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.canvas.bounds];
		[path appendPath:[UIBezierPath bezierPathWithRoundedRect:pr cornerRadius:10.0]];
		self.blockedFill.frame = self.canvas.bounds;
		self.blockedFill.path = path.CGPath;
		self.placeableBorder.frame = self.canvas.bounds;
		self.placeableBorder.path = [UIBezierPath bezierPathWithRoundedRect:pr cornerRadius:10.0].CGPath;
	}

	if (self.slotDots) {
		UIBezierPath *dots = [UIBezierPath bezierPath];
		for (NSValue *v in self.slots) {
			CGPoint sp = [self canvasPointForNormalized:v.CGPointValue];
			CGFloat r = 14.0;
			[dots appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(sp.x - r, sp.y - r, r * 2.0, r * 2.0)]];
		}
		self.slotDots.frame = self.canvas.bounds;
		self.slotDots.path = dots.CGPath;
	} else if (self.homeMarkers) {
		UIBezierPath *homes = [UIBezierPath bezierPath];
		for (SCIDragLayoutItem *item in self.mutableItems) {
			if (item.homePosition.x < 0) continue;
			CGPoint hp = [self pointForNormalized:item.homePosition size:sciVisualSize(item)];
			CGFloat r = item.diameter * (self.canvasScale > 0 ? self.canvasScale : 1.0) / 2.0 + 2.0;
			[homes appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(hp.x - r, hp.y - r, r * 2.0, r * 2.0)]];
		}
		self.homeMarkers.frame = self.canvas.bounds;
		self.homeMarkers.path = homes.CGPath;
	}

	if (self.draggingChip) return;
	[self positionChipsFromModel];
}

- (CGPoint)canvasPointForNormalized:(CGPoint)norm {
	CGRect b = self.canvas.bounds;
	return CGPointMake(b.origin.x + norm.x * b.size.width, b.origin.y + norm.y * b.size.height);
}

- (CGRect)placeableRect {
	CGRect b = self.canvas.bounds;
	UIEdgeInsets in = self.placeableInsets;
	return CGRectMake(b.origin.x + in.left * b.size.width,
					  b.origin.y + in.top * b.size.height,
					  b.size.width * (1.0 - in.left - in.right),
					  b.size.height * (1.0 - in.top - in.bottom));
}

static CGSize sciVisualSize(SCIDragLayoutItem *item) {
	CGFloat h = item.diameter;
	return CGSizeMake(item.width > h ? item.width : h, h);
}

- (void)positionChipsFromModel {
	for (SCIDragLayoutChip *chip in self.chips) {
		CGSize cs = [chip chipSize];
		chip.bounds = CGRectMake(0, 0, cs.width, cs.height);
		[chip layoutChrome];
		chip.center = [self pointForNormalized:chip.item.position size:[chip chipSize]];
	}
}

- (CGPoint)pointForNormalized:(CGPoint)norm size:(CGSize)size {
	CGRect b = self.canvas.bounds;
	CGPoint raw = CGPointMake(b.origin.x + norm.x * b.size.width, b.origin.y + norm.y * b.size.height);
	return [self clampCenter:raw size:size];
}

- (CGPoint)clampCenter:(CGPoint)c size:(CGSize)size {
	CGRect pr = [self placeableRect];
	CGFloat hw = size.width / 2.0 + 4.0;
	CGFloat hh = size.height / 2.0 + 4.0;
	CGFloat cx = MIN(MAX(c.x, CGRectGetMinX(pr) + hw), CGRectGetMaxX(pr) - hw);
	CGFloat cy = MIN(MAX(c.y, CGRectGetMinY(pr) + hh), CGRectGetMaxY(pr) - hh);
	return CGPointMake(cx, cy);
}

- (CGPoint)normalizedForPoint:(CGPoint)center {
	CGRect b = self.canvas.bounds;
	if (b.size.width <= 0 || b.size.height <= 0) return CGPointMake(0.5, 0.5);
	return CGPointMake(center.x / b.size.width, center.y / b.size.height);
}

#pragma mark - Drag

- (void)handlePan:(UIPanGestureRecognizer *)pan {
	SCIDragLayoutChip *chip = (SCIDragLayoutChip *)pan.view;
	CGPoint t = [pan translationInView:self.canvas];

	if (pan.state == UIGestureRecognizerStateBegan) {
		self.draggingChip = chip;
		[self.canvas bringSubviewToFront:chip];
		chip.dragStart = chip.center;
		[UIView animateWithDuration:0.12 animations:^{ chip.transform = CGAffineTransformMakeScale(1.12, 1.12); }];
	}

	BOOL ending = pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled;

	if (self.slots.count) { [self handleSlotPan:chip translation:t ending:ending]; return; }

	CGFloat d = chip.item.diameter * (self.canvasScale > 0 ? self.canvasScale : 1.0);

	CGPoint kNone = CGPointMake(NAN, NAN);

	// A tap (no real travel) must leave the chip exactly where it was.
	if (hypot(t.x, t.y) < 6.0) {
		chip.center = chip.dragStart;
		[self showGuidesX:NAN y:NAN];
		if (ending) [self endDragOfChip:chip storeNormalized:kNone];
		return;
	}

	CGPoint raw = [self clampCenter:CGPointMake(chip.dragStart.x + t.x, chip.dragStart.y + t.y) size:[chip chipSize]];

	// Home snap wins over everything and skips collision, so the default arrangement is reproducible by hand.
	CGPoint home = [self homePointForChip:chip];
	if (!isnan(home.x) && hypot(raw.x - home.x, raw.y - home.y) < 18.0) {
		chip.center = home;
		[self showGuidesX:home.x y:home.y];
		if (ending) [self endDragOfChip:chip storeNormalized:chip.item.homePosition];
		return;
	}

	CGPoint snapped = raw;
	CGFloat snapX = NAN, snapY = NAN;
	[self snapPoint:raw diameter:d outX:&snapX outY:&snapY result:&snapped];

	CGPoint resolved = [self resolveCollisions:snapped chip:chip diameter:d];
	if (!CGPointEqualToPoint(resolved, snapped)) { snapX = NAN; snapY = NAN; }
	snapped = resolved;

	chip.center = snapped;
	[self showGuidesX:snapX y:snapY];

	if (ending) [self endDragOfChip:chip storeNormalized:[self normalizedForPoint:snapped]];
}

- (void)handleSlotPan:(SCIDragLayoutChip *)chip translation:(CGPoint)t ending:(BOOL)ending {
	if (hypot(t.x, t.y) < 6.0) {
		chip.center = chip.dragStart;
		self.slotHighlight.opacity = 0.0;
		if (ending) { self.draggingChip = nil; [self resetTransform:chip]; }
		return;
	}

	CGRect b = self.canvas.bounds;
	CGSize cs = [chip chipSize];
	CGFloat hw = cs.width / 2.0, hh = cs.height / 2.0;
	CGPoint p = CGPointMake(chip.dragStart.x + t.x, chip.dragStart.y + t.y);
	p.x = MIN(MAX(p.x, hw), b.size.width - hw);
	p.y = MIN(MAX(p.y, hh), b.size.height - hh);
	chip.center = p;

	NSInteger ti = [self nearestSlotIndexToPoint:p];
	CGPoint sp = [self canvasPointForNormalized:self.slots[ti].CGPointValue];
	CGFloat r = hh + 3.0;
	self.slotHighlight.frame = b;
	self.slotHighlight.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(sp.x - r, sp.y - r, r * 2.0, r * 2.0)].CGPath;
	self.slotHighlight.opacity = 1.0;

	if (!ending) return;

	CGPoint targetNorm = self.slots[ti].CGPointValue;
	CGPoint prevNorm = chip.item.position;
	SCIDragLayoutChip *occupant = [self chipAtSlotNorm:targetNorm excluding:chip];

	chip.item.position = targetNorm;
	if (occupant) occupant.item.position = prevNorm;

	self.draggingChip = nil;
	self.slotHighlight.opacity = 0.0;
	[self resetTransform:chip];
	[UIView animateWithDuration:0.18 animations:^{ [self positionChipsFromModel]; }];
	if (self.onChange) self.onChange(self.mutableItems.copy);
}

- (void)resetTransform:(SCIDragLayoutChip *)chip {
	[UIView animateWithDuration:0.15 animations:^{ chip.transform = CGAffineTransformIdentity; }];
}

- (NSInteger)nearestSlotIndexToPoint:(CGPoint)p {
	NSInteger best = 0;
	CGFloat bestDist = CGFLOAT_MAX;
	for (NSInteger i = 0; i < (NSInteger)self.slots.count; i++) {
		CGPoint sp = [self canvasPointForNormalized:self.slots[i].CGPointValue];
		CGFloat dd = hypot(p.x - sp.x, p.y - sp.y);
		if (dd < bestDist) { bestDist = dd; best = i; }
	}
	return best;
}

- (SCIDragLayoutChip *)chipAtSlotNorm:(CGPoint)norm excluding:(SCIDragLayoutChip *)excluding {
	for (SCIDragLayoutChip *c in self.chips) {
		if (c == excluding) continue;
		CGPoint pos = c.item.position;
		if (fabs(pos.x - norm.x) < 0.001 && fabs(pos.y - norm.y) < 0.001) return c;
	}
	return nil;
}

- (CGPoint)homePointForChip:(SCIDragLayoutChip *)chip {
	if (chip.item.homePosition.x < 0) return CGPointMake(NAN, NAN);
	return [self pointForNormalized:chip.item.homePosition size:[chip chipSize]];
}

- (void)endDragOfChip:(SCIDragLayoutChip *)chip storeNormalized:(CGPoint)norm {
	self.draggingChip = nil;
	[UIView animateWithDuration:0.15 animations:^{
		chip.transform = CGAffineTransformIdentity;
		self.vGuide.alpha = 0.0;
		self.hGuide.alpha = 0.0;
	}];

	if (isnan(norm.x)) return;
	chip.item.position = norm;
	if (self.onChange) self.onChange(self.mutableItems.copy);
}

- (CGPoint)resolveCollisions:(CGPoint)c chip:(SCIDragLayoutChip *)chip diameter:(CGFloat)d {
	if (self.minimumSpacing <= 0.0) return c;

	for (NSInteger pass = 0; pass < 3; pass++) {
		BOOL moved = NO;

		for (SCIDragLayoutChip *other in self.chips) {
			if (other == chip) continue;

			CGFloat minD = d / 2.0 + other.item.diameter / 2.0 + self.minimumSpacing;
			CGFloat dx = c.x - other.center.x;
			CGFloat dy = c.y - other.center.y;
			CGFloat dist = hypot(dx, dy);

			if (dist >= minD) continue;

			if (dist < 0.5) { dx = 1.0; dy = 0.0; dist = 1.0; }
			c.x = other.center.x + dx / dist * minD;
			c.y = other.center.y + dy / dist * minD;
			c = [self clampCenter:c size:CGSizeMake(d, d)];
			moved = YES;
		}

		if (!moved) break;
	}

	return c;
}

- (void)snapPoint:(CGPoint)p diameter:(CGFloat)d outX:(CGFloat *)outX outY:(CGFloat *)outY result:(CGPoint *)result {
	CGRect b = [self placeableRect];
	CGFloat half = d / 2.0;
	CGFloat margin = 10.0;
	CGFloat thresh = 11.0;

	NSMutableArray<NSNumber *> *xs = NSMutableArray.array;
	NSMutableArray<NSNumber *> *ys = NSMutableArray.array;

	if (self.snapMask & SCIDragLayoutSnapEdges) {
		[xs addObject:@(CGRectGetMinX(b) + margin + half)];
		[xs addObject:@(CGRectGetMaxX(b) - margin - half)];
		[ys addObject:@(CGRectGetMinY(b) + margin + half)];
		[ys addObject:@(CGRectGetMaxY(b) - margin - half)];
	}
	if (self.snapMask & SCIDragLayoutSnapCenter) {
		[xs addObject:@(CGRectGetMidX(b))];
		[ys addObject:@(CGRectGetMidY(b))];
	}
	if ((self.snapMask & SCIDragLayoutSnapGrid) && self.gridDivisions > 1) {
		for (NSInteger i = 1; i < self.gridDivisions; i++) {
			[xs addObject:@(CGRectGetMinX(b) + b.size.width * i / self.gridDivisions)];
			[ys addObject:@(CGRectGetMinY(b) + b.size.height * i / self.gridDivisions)];
		}
	}

	CGPoint out = p;
	*outX = NAN; *outY = NAN;

	CGFloat best = thresh;
	for (NSNumber *n in xs) {
		CGFloat dx = fabs(p.x - n.doubleValue);
		if (dx < best) { best = dx; out.x = n.doubleValue; *outX = out.x; }
	}
	best = thresh;
	for (NSNumber *n in ys) {
		CGFloat dy = fabs(p.y - n.doubleValue);
		if (dy < best) { best = dy; out.y = n.doubleValue; *outY = out.y; }
	}

	*result = out;
}

- (void)showGuidesX:(CGFloat)x y:(CGFloat)y {
	CGRect b = self.canvas.bounds;
	if (!isnan(x)) {
		self.vGuide.frame = CGRectMake(x - 0.5, 0, 1.0, b.size.height);
		self.vGuide.alpha = 0.9;
	} else {
		self.vGuide.alpha = 0.0;
	}
	if (!isnan(y)) {
		self.hGuide.frame = CGRectMake(0, y - 0.5, b.size.width, 1.0);
		self.hGuide.alpha = 0.9;
	} else {
		self.hGuide.alpha = 0.0;
	}
}

- (void)resetTapped {
	if (self.onReset) self.onReset();
}

@end
