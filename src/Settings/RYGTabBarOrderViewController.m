#import "RYGTabBarOrderViewController.h"
#import "../UI/RYGIcon.h"
#import "../UI/RYGPopupChrome.h"
#import "../UI/RYGLiquidGlass.h"
#import "../Utils.h"

static NSArray<NSDictionary *> *rygTabCatalog(void) {
	return @[
		@{@"key": @"FEED",    @"title": @"Feed",     @"icon": @"ig_icon_home_pano_prism_outline_24",        @"sfFallback": @"house",              @"hidePref": @"hide_feed_tab"},
		@{@"key": @"CLIPS",   @"title": @"Reels",    @"icon": @"ig_icon_reels_pano_prism_outline_24",       @"sfFallback": @"play.rectangle",     @"hidePref": @"hide_reels_tab"},
		@{@"key": @"DIRECT",  @"title": @"Messages", @"icon": @"ig_icon_direct_prism_outline_24",           @"sfFallback": @"paperplane",         @"hidePref": @"hide_messages_tab"},
		@{@"key": @"SEARCH",  @"title": @"Explore",  @"icon": @"ig_icon_search_pano_outline_24",            @"sfFallback": @"magnifyingglass",    @"hidePref": @"hide_explore_tab"},
		@{@"key": @"PROFILE", @"title": @"Profile",  @"icon": @"ig_icon_user_circle_pano_prism_outline_24", @"sfFallback": @"person.crop.circle", @"hidePref": @"hide_profile_tab"},
		@{@"key": @"SHARE",   @"title": @"Create",   @"icon": @"ig_icon_add_pano_outline_24",               @"sfFallback": @"plus.app",           @"hidePref": @"hide_create_tab"},
	];
}

static NSDictionary *rygTabEntryForKey(NSString *key) {
	for (NSDictionary *entry in rygTabCatalog())
		if ([entry[@"key"] isEqualToString:key]) return entry;
	return nil;
}

static UIImage *rygIconForEntry(NSDictionary *entry, CGFloat pt) {
	return [RYGIcon imageNamed:entry[@"icon"] pointSize:pt] ?: [UIImage systemImageNamed:entry[@"sfFallback"]];
}

static UIVisualEffectView *rygMakeGlass(void) {
	return RYGLiquidGlassView(YES, NO, nil);
}

#pragma mark - Bottom bar preview

@class RYGTabBarPreview;
@protocol RYGTabBarPreviewDelegate <NSObject>
- (BOOL)tabBarPreviewCanRemove:(RYGTabBarPreview *)p;
- (void)tabBarPreview:(RYGTabBarPreview *)p didReorderToKeys:(NSArray<NSString *> *)keys;
- (void)tabBarPreview:(RYGTabBarPreview *)p didRemoveKey:(NSString *)key;
@end

@interface RYGTabBarPreview : UIView
@property (nonatomic, weak) id<RYGTabBarPreviewDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<NSString *> *keys;
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *iconForKey;
@property (nonatomic, copy) NSString *draggingKey;
@property (nonatomic, assign) BOOL removeArmed;
@end

@implementation RYGTabBarPreview

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	_keys = [NSMutableArray array];
	_iconForKey = [NSMutableDictionary dictionary];

	_glass = rygMakeGlass();
	_glass.clipsToBounds = YES;
	_glass.userInteractionEnabled = NO;
	[self addSubview:_glass];
	_glass.layer.borderWidth = 1.0;
	_glass.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.6].CGColor;

	self.layer.shadowColor = UIColor.blackColor.CGColor;
	self.layer.shadowOpacity = 0.16;
	self.layer.shadowRadius = 16.0;
	self.layer.shadowOffset = CGSizeMake(0, 6);

	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	lp.minimumPressDuration = 0.14;
	[self addGestureRecognizer:lp];
	return self;
}

- (void)setKeys:(NSArray<NSString *> *)keys animatingInKey:(NSString *)newKey {
	_keys = [keys mutableCopy];
	for (UIView *v in _iconForKey.allValues) [v removeFromSuperview];
	[_iconForKey removeAllObjects];

	for (NSString *key in _keys) {
		UIImageView *icon = [[UIImageView alloc] initWithImage:rygIconForEntry(rygTabEntryForKey(key), 26.0)];
		icon.contentMode = UIViewContentModeScaleAspectFit;
		icon.tintColor = UIColor.labelColor;
		[self addSubview:icon];
		_iconForKey[key] = icon;
	}
	[self setNeedsLayout];
	[self layoutIfNeeded];

	if (newKey && _iconForKey[newKey]) {
		UIView *icon = _iconForKey[newKey];
		icon.transform = CGAffineTransformMakeScale(0.2, 0.2);
		icon.alpha = 0.0;
		[UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.7 options:0 animations:^{
			icon.transform = CGAffineTransformIdentity;
			icon.alpha = 1.0;
		} completion:nil];
	}
}

- (void)layoutSubviews {
	[super layoutSubviews];
	_glass.frame = self.bounds;
	CGFloat r = MIN(self.bounds.size.height / 2.0, 28.0);
	_glass.layer.cornerRadius = r;
	_glass.layer.cornerCurve = kCACornerCurveContinuous;
	self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r].CGPath;
	[self layoutIconsAnimated:NO];
}

- (CGPoint)slotCenterForIndex:(NSInteger)i count:(NSInteger)count {
	CGFloat inset = 14.0;
	CGFloat usable = self.bounds.size.width - inset * 2.0;
	CGFloat slot = count > 0 ? usable / count : usable;
	return CGPointMake(inset + slot * (i + 0.5), self.bounds.size.height / 2.0);
}

- (void)layoutIconsAnimated:(BOOL)animated {
	NSInteger count = self.keys.count;
	void (^work)(void) = ^{
		for (NSInteger i = 0; i < count; i++) {
			NSString *key = self.keys[i];
			if ([key isEqualToString:self.draggingKey]) continue;
			UIView *icon = self.iconForKey[key];
			icon.bounds = CGRectMake(0, 0, 30, 30);
			icon.center = [self slotCenterForIndex:i count:count];
		}
	};
	if (animated) [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:work completion:nil];
	else work();
}

- (NSInteger)slotIndexAtX:(CGFloat)x count:(NSInteger)count {
	CGFloat inset = 14.0;
	CGFloat usable = self.bounds.size.width - inset * 2.0;
	CGFloat slot = count > 0 ? usable / count : usable;
	NSInteger i = (NSInteger)floor((x - inset) / slot);
	return MAX(0, MIN(count - 1, i));
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)g {
	CGPoint pt = [g locationInView:self];

	if (g.state == UIGestureRecognizerStateBegan) {
		NSInteger idx = [self slotIndexAtX:pt.x count:self.keys.count];
		if (idx < 0 || idx >= (NSInteger)self.keys.count) return;
		self.draggingKey = self.keys[idx];
		UIView *icon = self.iconForKey[self.draggingKey];
		[self bringSubviewToFront:icon];
		self.removeArmed = NO;
		[UIView animateWithDuration:0.18 animations:^{
			icon.transform = CGAffineTransformMakeScale(1.35, 1.35);
		}];
		[[UIImpactFeedbackGenerator new] impactOccurred];
		return;
	}

	if (!self.draggingKey) return;
	UIView *icon = self.iconForKey[self.draggingKey];

	if (g.state == UIGestureRecognizerStateChanged) {
		icon.center = pt;
		BOOL canRemove = [self.delegate tabBarPreviewCanRemove:self];
		BOOL arm = canRemove && pt.y < -22.0;
		if (arm != self.removeArmed) {
			self.removeArmed = arm;
			[UIView animateWithDuration:0.15 animations:^{
				icon.alpha = arm ? 0.55 : 1.0;
				icon.transform = CGAffineTransformMakeScale(arm ? 1.05 : 1.35, arm ? 1.05 : 1.35);
			}];
			[[UISelectionFeedbackGenerator new] selectionChanged];
		}
		if (!arm) {
			NSInteger from = [self.keys indexOfObject:self.draggingKey];
			NSInteger to = [self slotIndexAtX:pt.x count:self.keys.count];
			if (from != NSNotFound && to != from) {
				[self.keys removeObjectAtIndex:from];
				[self.keys insertObject:self.draggingKey atIndex:to];
				[self layoutIconsAnimated:YES];
				[[UISelectionFeedbackGenerator new] selectionChanged];
			}
		}
		return;
	}

	if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
		NSString *key = self.draggingKey;
		self.draggingKey = nil;

		if (self.removeArmed && g.state == UIGestureRecognizerStateEnded) {
			[UIView animateWithDuration:0.22 animations:^{
				icon.alpha = 0.0;
				icon.center = CGPointMake(icon.center.x, -40.0);
				icon.transform = CGAffineTransformMakeScale(0.4, 0.4);
			} completion:^(__unused BOOL f) {
				[self.delegate tabBarPreview:self didRemoveKey:key];
			}];
			[[UIImpactFeedbackGenerator new] impactOccurred];
			return;
		}

		NSInteger idx = [self.keys indexOfObject:key];
		[UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.4 options:0 animations:^{
			icon.transform = CGAffineTransformIdentity;
			icon.alpha = 1.0;
			icon.center = [self slotCenterForIndex:idx count:self.keys.count];
		} completion:nil];
		[self.delegate tabBarPreview:self didReorderToKeys:[self.keys copy]];
	}
}

@end

#pragma mark - Hidden tile

@interface RYGHiddenTile : UIControl
@property (nonatomic, copy) NSString *key;
- (instancetype)initWithKey:(NSString *)key;
@end

@implementation RYGHiddenTile
- (instancetype)initWithKey:(NSString *)key {
	if (!(self = [super initWithFrame:CGRectZero])) return nil;
	_key = [key copy];
	NSDictionary *entry = rygTabEntryForKey(key);

	UIView *tile = UIView.new;
	tile.translatesAutoresizingMaskIntoConstraints = NO;
	tile.userInteractionEnabled = NO;
	tile.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
	tile.layer.cornerRadius = 18.0;
	tile.layer.cornerCurve = kCACornerCurveContinuous;
	tile.layer.borderWidth = 1.0;
	tile.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.5].CGColor;
	[self addSubview:tile];

	UIImageView *icon = [[UIImageView alloc] initWithImage:rygIconForEntry(entry, 24.0)];
	icon.translatesAutoresizingMaskIntoConstraints = NO;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	icon.tintColor = UIColor.secondaryLabelColor;

	UILabel *label = UILabel.new;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	label.text = RYGLocalized(entry[@"title"]);
	label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightMedium];
	label.textColor = UIColor.tertiaryLabelColor;
	label.textAlignment = NSTextAlignmentCenter;
	label.adjustsFontSizeToFitWidth = YES;
	label.minimumScaleFactor = 0.8;

	[tile addSubview:icon];
	[tile addSubview:label];

	[NSLayoutConstraint activateConstraints:@[
		[tile.topAnchor constraintEqualToAnchor:self.topAnchor],
		[tile.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		[tile.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
		[tile.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
		[icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor],
		[icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-9.0],
		[icon.widthAnchor constraintEqualToConstant:26.0],
		[icon.heightAnchor constraintEqualToConstant:26.0],
		[label.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:4.0],
		[label.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-4.0],
		[label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:7.0],
	]];
	return self;
}
- (void)setHighlighted:(BOOL)highlighted {
	[super setHighlighted:highlighted];
	[UIView animateWithDuration:0.15 animations:^{
		self.transform = highlighted ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
		self.alpha = highlighted ? 0.7 : 1.0;
	}];
}
@end

#pragma mark - Controller

@interface RYGTabBarOrderViewController () <RYGTabBarPreviewDelegate>
@property (nonatomic, strong) RYGTabBarPreview *preview;
@property (nonatomic, strong) UIScrollView *hiddenScroll;
@property (nonatomic, strong) UIStackView *hiddenStack;
@property (nonatomic, strong) UILabel *hiddenEmptyLabel;
@property (nonatomic, strong) NSMutableArray<NSString *> *barKeys;
@property (nonatomic, strong) NSMutableArray<NSString *> *hiddenKeys;
@end

@implementation RYGTabBarOrderViewController

- (instancetype)init {
	if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
	self.title = RYGLocalized(@"Icon order");
	[self loadOrder];
	return self;
}

- (void)loadOrder {
	NSString *orderPref = [RYGUtils getStringPref:@"nav_tab_order"];
	BOOL pristine = orderPref.length == 0;

	NSMutableArray *all = [NSMutableArray array];
	for (NSString *key in [orderPref componentsSeparatedByString:@","])
		if (rygTabEntryForKey(key) && ![all containsObject:key]) [all addObject:key];
	for (NSDictionary *entry in rygTabCatalog())
		if (![all containsObject:entry[@"key"]]) [all addObject:entry[@"key"]];

	self.barKeys = [NSMutableArray array];
	self.hiddenKeys = [NSMutableArray array];
	for (NSString *key in all) {
		BOOL hidden = pristine ? [key isEqualToString:@"SHARE"] : [RYGUtils getBoolPref:rygTabEntryForKey(key)[@"hidePref"]];
		if (hidden) [self.hiddenKeys addObject:key];
		else [self.barKeys addObject:key];
	}
}

- (void)commit {
	NSMutableArray *all = [self.barKeys mutableCopy];
	[all addObjectsFromArray:self.hiddenKeys];
	[RYGUtils setPref:[all componentsJoinedByString:@","] forKey:@"nav_tab_order"];
	for (NSString *key in self.barKeys)
		[RYGUtils setPref:@(NO) forKey:rygTabEntryForKey(key)[@"hidePref"]];
	for (NSString *key in self.hiddenKeys)
		[RYGUtils setPref:@(YES) forKey:rygTabEntryForKey(key)[@"hidePref"]];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [RYGPopupChrome backgroundColor] ?: UIColor.systemGroupedBackgroundColor;

	UILabel *hiddenTitle = UILabel.new;
	hiddenTitle.text = RYGLocalized(@"Hidden tabs");
	hiddenTitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
	hiddenTitle.textColor = UIColor.secondaryLabelColor;
	hiddenTitle.translatesAutoresizingMaskIntoConstraints = NO;

	self.hiddenScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
	self.hiddenScroll.showsHorizontalScrollIndicator = NO;
	self.hiddenScroll.translatesAutoresizingMaskIntoConstraints = NO;

	self.hiddenStack = [[UIStackView alloc] initWithFrame:CGRectZero];
	self.hiddenStack.axis = UILayoutConstraintAxisHorizontal;
	self.hiddenStack.spacing = 12.0;
	self.hiddenStack.alignment = UIStackViewAlignmentCenter;
	self.hiddenStack.translatesAutoresizingMaskIntoConstraints = NO;
	[self.hiddenScroll addSubview:self.hiddenStack];

	self.hiddenEmptyLabel = UILabel.new;
	self.hiddenEmptyLabel.text = RYGLocalized(@"All tabs are on the bar");
	self.hiddenEmptyLabel.font = [UIFont systemFontOfSize:13.0];
	self.hiddenEmptyLabel.textColor = UIColor.tertiaryLabelColor;
	self.hiddenEmptyLabel.textAlignment = NSTextAlignmentCenter;
	self.hiddenEmptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:self.hiddenEmptyLabel];

	UILabel *caption = UILabel.new;
	caption.font = [UIFont systemFontOfSize:12.5];
	caption.textColor = UIColor.secondaryLabelColor;
	caption.textAlignment = NSTextAlignmentCenter;
	caption.numberOfLines = 0;
	caption.text = RYGLocalized(@"Hold and drag to reorder. Drag an icon up to hide it. Tap a hidden tab to add it back.");
	caption.translatesAutoresizingMaskIntoConstraints = NO;

	self.preview = [[RYGTabBarPreview alloc] initWithFrame:CGRectZero];
	self.preview.delegate = self;
	self.preview.translatesAutoresizingMaskIntoConstraints = NO;
	[self.preview setKeys:self.barKeys animatingInKey:nil];

	UIButton *reset = [self buttonWithTitle:RYGLocalized(@"Reset") filled:NO tint:UIColor.secondaryLabelColor];
	[reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
	UIButton *apply = [self buttonWithTitle:RYGLocalized(@"Apply") filled:YES tint:[RYGUtils RYGColor_Primary] ?: UIColor.systemBlueColor];
	[apply addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];

	UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[reset, apply]];
	buttons.axis = UILayoutConstraintAxisHorizontal;
	buttons.distribution = UIStackViewDistributionFillEqually;
	buttons.spacing = 12.0;
	buttons.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:hiddenTitle];
	[self.view addSubview:self.hiddenScroll];
	[self.view addSubview:caption];
	[self.view addSubview:self.preview];
	[self.view addSubview:buttons];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[hiddenTitle.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18.0],
		[hiddenTitle.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22.0],
		[hiddenTitle.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22.0],

		[self.hiddenScroll.topAnchor constraintEqualToAnchor:hiddenTitle.bottomAnchor constant:12.0],
		[self.hiddenScroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.hiddenScroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.hiddenScroll.heightAnchor constraintEqualToConstant:90.0],

		[self.hiddenStack.topAnchor constraintEqualToAnchor:self.hiddenScroll.contentLayoutGuide.topAnchor],
		[self.hiddenStack.bottomAnchor constraintEqualToAnchor:self.hiddenScroll.contentLayoutGuide.bottomAnchor],
		[self.hiddenStack.leadingAnchor constraintEqualToAnchor:self.hiddenScroll.contentLayoutGuide.leadingAnchor constant:16.0],
		[self.hiddenStack.trailingAnchor constraintEqualToAnchor:self.hiddenScroll.contentLayoutGuide.trailingAnchor constant:-16.0],
		[self.hiddenStack.heightAnchor constraintEqualToAnchor:self.hiddenScroll.frameLayoutGuide.heightAnchor],

		[self.hiddenEmptyLabel.centerYAnchor constraintEqualToAnchor:self.hiddenScroll.centerYAnchor],
		[self.hiddenEmptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:22.0],
		[self.hiddenEmptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-22.0],

		[buttons.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0],
		[buttons.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
		[buttons.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
		[buttons.heightAnchor constraintEqualToConstant:50.0],

		[self.preview.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-22.0],
		[self.preview.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
		[self.preview.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
		[self.preview.heightAnchor constraintEqualToConstant:64.0],

		[caption.bottomAnchor constraintEqualToAnchor:self.preview.topAnchor constant:-12.0],
		[caption.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24.0],
		[caption.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24.0],
	]];

	[self rebuildHidden];
}

- (UIButton *)buttonWithTitle:(NSString *)title filled:(BOOL)filled tint:(UIColor *)tint {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	UIButtonConfiguration *cfg = filled ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
	cfg.title = title;
	cfg.cornerStyle = UIButtonConfigurationCornerStyleLarge;
	cfg.baseBackgroundColor = filled ? tint : UIColor.tertiarySystemFillColor;
	cfg.baseForegroundColor = filled ? UIColor.whiteColor : tint;
	UIFont *f = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
	cfg.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: f}];
	b.configuration = cfg;
	b.translatesAutoresizingMaskIntoConstraints = NO;
	return b;
}

- (void)rebuildHidden {
	for (UIView *v in self.hiddenStack.arrangedSubviews) {
		[self.hiddenStack removeArrangedSubview:v];
		[v removeFromSuperview];
	}
	for (NSString *key in self.hiddenKeys) {
		RYGHiddenTile *tile = [[RYGHiddenTile alloc] initWithKey:key];
		tile.translatesAutoresizingMaskIntoConstraints = NO;
		[tile addTarget:self action:@selector(hiddenTileTapped:) forControlEvents:UIControlEventTouchUpInside];
		[NSLayoutConstraint activateConstraints:@[
			[tile.widthAnchor constraintEqualToConstant:76.0],
			[tile.heightAnchor constraintEqualToConstant:76.0],
		]];
		[self.hiddenStack addArrangedSubview:tile];
	}
	self.hiddenEmptyLabel.hidden = self.hiddenKeys.count > 0;
	self.hiddenScroll.hidden = self.hiddenKeys.count == 0;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self.hiddenScroll layoutIfNeeded];
	CGFloat content = self.hiddenStack.frame.size.width;
	CGFloat frameW = self.hiddenScroll.frame.size.width;
	CGFloat pad = content < frameW ? (frameW - content) / 2.0 : 0.0;
	self.hiddenScroll.contentInset = UIEdgeInsetsMake(0, pad, 0, pad);
}

#pragma mark - Actions

- (void)hiddenTileTapped:(RYGHiddenTile *)tile {
	NSString *key = tile.key;
	if (![self.hiddenKeys containsObject:key]) return;
	[self.hiddenKeys removeObject:key];
	[self.barKeys addObject:key];
	[self commit];
	[self.preview setKeys:self.barKeys animatingInKey:key];
	[self rebuildHidden];
	[self.view setNeedsLayout];
}

- (void)applyTapped {
	[RYGUtils showRestartConfirmation];
}

- (void)resetTapped {
	[RYGUtils setPref:@"" forKey:@"nav_tab_order"];
	for (NSDictionary *entry in rygTabCatalog())
		[RYGUtils setPref:@(NO) forKey:entry[@"hidePref"]];
	[self loadOrder];
	[self.preview setKeys:self.barKeys animatingInKey:nil];
	[self rebuildHidden];
	[self.view setNeedsLayout];
	[[UIImpactFeedbackGenerator new] impactOccurred];
}

#pragma mark - Preview delegate

- (BOOL)tabBarPreviewCanRemove:(RYGTabBarPreview *)p { return self.barKeys.count > 1; }

- (void)tabBarPreview:(RYGTabBarPreview *)p didReorderToKeys:(NSArray<NSString *> *)keys {
	self.barKeys = [keys mutableCopy];
	[self commit];
}

- (void)tabBarPreview:(RYGTabBarPreview *)p didRemoveKey:(NSString *)key {
	[self.barKeys removeObject:key];
	if (![self.hiddenKeys containsObject:key]) [self.hiddenKeys insertObject:key atIndex:0];
	[self commit];
	[self.preview setKeys:self.barKeys animatingInKey:nil];
	[self rebuildHidden];
	[self.view setNeedsLayout];
}

@end
