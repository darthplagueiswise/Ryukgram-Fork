#import "RYGGridTogglePositionViewController.h"
#import "RYGGridButtonLayout.h"
#import "RYGGridFeedInfo.h"
#import "../../../UI/RYGIcon.h"
#import "../../../Utils.h"

#pragma mark - Preview mock (grid tiles + header and tab bar bands)

@interface RYGGridMockView : UIView
@property (nonatomic, assign) UIEdgeInsets safeInsetsNormalized;
@property (nonatomic, assign) CGRect headerRectInSafeArea;
@property (nonatomic, assign) CGRect tabBarRectInSafeArea;
@property (nonatomic, assign) BOOL showsTabBar;
@end

@implementation RYGGridMockView {
	NSMutableArray<CALayer *> *_tiles;
	UIView *_headerBand, *_tabBand;
	UIView *_logo;
	NSMutableArray<UIImageView *> *_headerGlyphs, *_tabGlyphs;
}

- (UIImageView *)glyphNamed:(NSString *)igName fallback:(NSString *)sf into:(NSMutableArray *)bucket {
	UIImage *img = [RYGIcon imageNamed:igName pointSize:14] ?: [UIImage systemImageNamed:sf];
	UIImageView *v = [[UIImageView alloc] initWithImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
	v.tintColor = [UIColor colorWithWhite:1.0 alpha:0.75];
	v.contentMode = UIViewContentModeScaleAspectFit;
	[self addSubview:v];
	[bucket addObject:v];
	return v;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1.0];
	_tiles = [NSMutableArray array];
	_headerGlyphs = [NSMutableArray array];
	_tabGlyphs = [NSMutableArray array];

	_headerBand = [UIView new];
	_headerBand.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
	[self addSubview:_headerBand];

	_tabBand = [UIView new];
	_tabBand.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
	[self addSubview:_tabBand];

	_logo = [UIView new];
	_logo.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.55];
	_logo.layer.cornerRadius = 2.0;
	[self addSubview:_logo];

	[self glyphNamed:@"ig_icon_heart_outline_24" fallback:@"heart" into:_headerGlyphs];

	[self glyphNamed:@"ig_icon_home_pano_prism_outline_24" fallback:@"house" into:_tabGlyphs];
	[self glyphNamed:@"ig_icon_reels_prism_outline_24" fallback:@"play.rectangle" into:_tabGlyphs];
	[self glyphNamed:@"ig_icon_direct_prism_outline_24" fallback:@"paperplane" into:_tabGlyphs];
	[self glyphNamed:@"ig_icon_search_outline_24" fallback:@"magnifyingglass" into:_tabGlyphs];
	[self glyphNamed:@"ig_icon_user_circle_pano_outline_24" fallback:@"person.circle" into:_tabGlyphs];
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
	// Drawing the whole screen, so the pill can overhang into the home indicator like it does.
	UIEdgeInsets si = self.safeInsetsNormalized;
	CGRect safe = CGRectMake(si.left * w, si.top * h, w * (1.0 - si.left - si.right), h * (1.0 - si.top - si.bottom));
	CGRect hr = self.headerRectInSafeArea, tr = self.tabBarRectInSafeArea;

	CGFloat top = hr.size.height * safe.size.height;
	_headerBand.frame = CGRectMake(safe.origin.x + hr.origin.x * safe.size.width,
								   safe.origin.y + hr.origin.y * safe.size.height,
								   hr.size.width * safe.size.width, top);

	_tabBand.hidden = !self.showsTabBar;
	CGFloat pillH = tr.size.height * safe.size.height;
	_tabBand.frame = CGRectMake(safe.origin.x + tr.origin.x * safe.size.width,
								safe.origin.y + tr.origin.y * safe.size.height,
								tr.size.width * safe.size.width, pillH);
	_tabBand.layer.cornerRadius = pillH / 2.0;
	_tabBand.layer.cornerCurve = kCACornerCurveContinuous;
	for (UIImageView *g in _tabGlyphs) g.hidden = !self.showsTabBar;

	CGFloat hg = MIN(15.0, top * 0.40);
	CGRect hb = _headerBand.frame;
	CGFloat hy = CGRectGetMidY(hb) - hg / 2.0;
	for (NSUInteger i = 0; i < _headerGlyphs.count; i++)
		_headerGlyphs[i].frame = CGRectMake(CGRectGetMaxX(hb) - 10.0 - hg - (hg + 8.0) * i, hy, hg, hg);
	_logo.frame = CGRectMake(hb.origin.x + 10.0, CGRectGetMidY(hb) - hg * 0.25, w * 0.22, hg * 0.5);

	CGFloat tg = MIN(16.0, pillH * 0.44);
	CGFloat slot = _tabBand.bounds.size.width / (CGFloat)_tabGlyphs.count;
	CGFloat tabY = CGRectGetMidY(_tabBand.frame) - tg / 2.0;
	for (NSUInteger i = 0; i < _tabGlyphs.count; i++)
		_tabGlyphs[i].frame = CGRectMake(_tabBand.frame.origin.x + slot * i + (slot - tg) / 2.0, tabY, tg, tg);

	for (CALayer *l in _tiles) [l removeFromSuperlayer];
	[_tiles removeAllObjects];

	NSInteger cols = 3;
	CGFloat gap = 2.0;
	CGFloat tile = floor((w - gap * (cols - 1)) / cols);
	CGFloat tilesTop = CGRectGetMaxY(_headerBand.frame);
	NSInteger rows = (NSInteger)ceil((h - tilesTop) / (tile + gap));
	NSArray *pairs = @[@[[UIColor colorWithRed:0.15 green:0.22 blue:0.38 alpha:1], [UIColor colorWithRed:0.38 green:0.20 blue:0.42 alpha:1]],
	                   @[[UIColor colorWithRed:0.32 green:0.18 blue:0.30 alpha:1], [UIColor colorWithRed:0.10 green:0.28 blue:0.34 alpha:1]],
	                   @[[UIColor colorWithRed:0.20 green:0.30 blue:0.20 alpha:1], [UIColor colorWithRed:0.30 green:0.28 blue:0.12 alpha:1]]];

	NSInteger idx = 0;
	for (NSInteger r = 0; r < rows; r++) {
		for (NSInteger c = 0; c < cols; c++) {
			CAGradientLayer *g = [CAGradientLayer layer];
			NSArray *pair = pairs[idx % pairs.count];
			g.colors = @[(id)[pair[0] CGColor], (id)[pair[1] CGColor]];
			g.startPoint = CGPointMake(0, 0);
			g.endPoint = CGPointMake(1, 1);
			g.frame = CGRectMake(c * (tile + gap), tilesTop + r * (tile + gap), tile, tile);
			[self.layer insertSublayer:g atIndex:0];
			[_tiles addObject:g];
			idx++;
		}
	}
}

@end

#pragma mark - Editor

static NSArray<RYGDragLayoutItem *> *rygGridToggleItems(void) {
	CGPoint pos = [RYGGridButtonLayout positionForID:RYGGridBtnToggle];
	UIImage *icon = [RYGIcon imageNamed:[RYGGridButtonLayout iconForID:RYGGridBtnToggle] pointSize:20];
	RYGDragLayoutItem *item = [RYGDragLayoutItem itemWithIdentifier:RYGGridBtnToggle icon:icon title:nil position:pos];
	item.diameter = [RYGGridButtonLayout diameterForID:RYGGridBtnToggle];
	// No home magnet: the lone chip starts on its default, which would swallow every drag.
	item.homePosition = CGPointMake(-1, -1);
	return @[item];
}

@implementation RYGGridTogglePositionViewController

- (instancetype)init {
	if (!(self = [super initWithItems:rygGridToggleItems()])) return nil;

	self.title = RYGLocalized(@"Button position");
	self.placeableInsets = [RYGGridButtonLayout placeableInsetsNormalized];
	// Edges and centre only; the grid divisions mean nothing on the feed.
	self.snapMask = RYGDragLayoutSnapEdges | RYGDragLayoutSnapCenter;
	self.scalesItemsToCanvas = YES;
	self.instructions = RYGLocalized(@"Drag the button where you want it. The dimmed strips are Instagram's header and tab bar.");

	UIWindow *kw = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if (![s isKindOfClass:UIWindowScene.class]) continue;
		for (UIWindow *w in ((UIWindowScene *)s).windows) { if (w.isKeyWindow) { kw = w; break; } }
		if (kw) break;
	}
	// Canvas is the whole screen so the tab pill draws full height instead of being clipped.
	UIEdgeInsets outsets = UIEdgeInsetsZero;
	if (kw && kw.bounds.size.width > 0 && kw.bounds.size.height > 0) {
		CGSize b = kw.bounds.size;
		UIEdgeInsets ins = kw.safeAreaInsets;
		outsets = UIEdgeInsetsMake(ins.top / b.height, ins.left / b.width, ins.bottom / b.height, ins.right / b.width);
		self.canvasAspect = b.width / b.height;
		self.referenceWidth = b.width;
	}
	self.canvasOutsetFractions = outsets;

	RYGGridMockView *mock = [RYGGridMockView new];
	mock.safeInsetsNormalized = outsets;
	mock.headerRectInSafeArea = [RYGGridButtonLayout headerRectNormalized];
	mock.tabBarRectInSafeArea = [RYGGridButtonLayout tabBarRectNormalized];
	mock.showsTabBar = [RYGGridButtonLayout hasBottomBar];
	self.backgroundContentView = mock;

	self.onChange = ^(NSArray<RYGDragLayoutItem *> *items) {
		for (RYGDragLayoutItem *item in items) [RYGGridButtonLayout setPosition:item.position forID:item.identifier];
		[[NSNotificationCenter defaultCenter] postNotificationName:RYGGridFeedVisibilityDidChange object:nil];
	};

	__weak typeof(self) weakSelf = self;
	self.onReset = ^{
		[RYGGridButtonLayout reset];
		[weakSelf applyItems:rygGridToggleItems()];
	};
	return self;
}

@end
