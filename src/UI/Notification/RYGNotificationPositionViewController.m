#import "RYGNotificationPositionViewController.h"
#import "../../Utils.h"

static NSString *const kPrefKey = @"notif_position";

// Reserve the notch + home indicator so placement matches the real safe area.
static const CGFloat kTopInset = 0.07;
static const CGFloat kBottomInset = 0.025;
static const CGFloat kPillWidth = 120.0;
static const CGFloat kPillHeight = 34.0;

static NSArray<NSValue *> *rygSlots(void) {
	NSArray<NSNumber *> *cols = @[@0.26, @0.50, @0.74];
	NSArray<NSNumber *> *rows = @[@0.06, @0.16, @0.27, @0.38, @0.50, @0.62, @0.73, @0.84, @0.94];
	NSMutableArray *out = NSMutableArray.array;
	for (NSNumber *y in rows)
		for (NSNumber *x in cols)
			[out addObject:[NSValue valueWithCGPoint:CGPointMake(x.doubleValue, y.doubleValue)]];
	return out;
}

static CGPoint rygCurrentPoint(void) {
	NSString *s = [RYGUtils getStringPref:kPrefKey] ?: @"";

	if ([s containsString:@","]) {
		NSArray<NSString *> *parts = [s componentsSeparatedByString:@","];
		if (parts.count == 2) return CGPointMake(parts[0].doubleValue, parts[1].doubleValue);
	}

	// Legacy string positions.
	CGFloat y = [s hasPrefix:@"bottom"] ? 0.94 : 0.06;
	CGFloat x = [s hasSuffix:@"_left"] ? 0.26 : ([s hasSuffix:@"_right"] ? 0.74 : 0.50);
	return CGPointMake(x, y);
}

static CGPoint rygNearestSlot(CGPoint p) {
	CGPoint best = CGPointMake(0.5, 0.12);
	CGFloat bestDist = CGFLOAT_MAX;
	for (NSValue *v in rygSlots()) {
		CGPoint s = v.CGPointValue;
		CGFloat dd = hypot(p.x - s.x, p.y - s.y);
		if (dd < bestDist) { bestDist = dd; best = s; }
	}
	return best;
}

#pragma mark - Phone-screen mock

@interface RYGNotifScreenMock : UIView
@end

@implementation RYGNotifScreenMock {
	UIView *_notch, *_homeBar;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.backgroundColor = [UIColor colorWithWhite:0.82 alpha:1.0];

	_notch = [UIView new];
	_notch.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
	[self addSubview:_notch];

	_homeBar = [UIView new];
	_homeBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.28];
	[self addSubview:_homeBar];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.bounds.size.width;
	CGFloat h = self.bounds.size.height;

	// Sit the island inside the reserved top inset so the placeable area starts below it.
	CGFloat notchH = 26.0;
	CGFloat notchY = MAX(8.0, (h * kTopInset - notchH) / 2.0);
	_notch.frame = CGRectMake((w - 100.0) / 2.0, notchY, 100.0, notchH);
	_notch.layer.cornerRadius = notchH / 2.0;

	CGFloat barW = w * 0.32;
	_homeBar.frame = CGRectMake((w - barW) / 2.0, h - h * kBottomInset / 2.0 - 2.0, barW, 4.0);
	_homeBar.layer.cornerRadius = 2.0;
}

@end

#pragma mark - Editor

@implementation RYGNotificationPositionViewController

static RYGDragLayoutItem *rygPillItem(void) {
	RYGDragLayoutItem *item = [RYGDragLayoutItem itemWithIdentifier:@"pill"
															  icon:[UIImage systemImageNamed:@"bell.fill"]
															 title:nil
														  position:rygNearestSlot(rygCurrentPoint())];
	item.diameter = kPillHeight;
	item.width = kPillWidth;
	return item;
}

- (instancetype)init {
	if (!(self = [super initWithItems:@[rygPillItem()]])) return nil;

	self.title = RYGLocalized(@"Position");
	self.slots = rygSlots();
	self.showsSlots = NO;
	self.placeableInsets = UIEdgeInsetsMake(kTopInset, 0.0, kBottomInset, 0.0);
	self.instructions = RYGLocalized(@"Drag the pill where you want it. Higher than center slides down, lower slides up.");

	self.backgroundContentView = [RYGNotifScreenMock new];

	self.onChange = ^(NSArray<RYGDragLayoutItem *> *items) {
		RYGDragLayoutItem *pill = items.firstObject;
		if (pill) [RYGUtils setPref:[NSString stringWithFormat:@"%.4f,%.4f", pill.position.x, pill.position.y] forKey:kPrefKey];
	};

	__weak typeof(self) weakSelf = self;
	self.onReset = ^{
		[RYGUtils setPref:@"0.5000,0.0600" forKey:kPrefKey];
		[weakSelf applyItems:@[rygPillItem()]];
	};

	return self;
}

@end
