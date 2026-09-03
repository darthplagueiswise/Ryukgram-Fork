#import "RYGPlaybackMenu.h"
#import "../../Utils.h"
#import <objc/runtime.h>

RYGPlaybackSurface const RYGPlaybackSurfaceReels = @"reels";
RYGPlaybackSurface const RYGPlaybackSurfaceStories = @"stories";

static const void *kRYGPlaybackLPRKey = &kRYGPlaybackLPRKey;
static const NSInteger kRYGPlaybackPanelTag = 988422;

#pragma mark - Registry

static NSMutableArray *rygPlaybackModules(void) {
	static NSMutableArray *arr;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ arr = [NSMutableArray array]; });
	return arr;
}

static NSMutableDictionary *rygPlaybackAnchorHandlers(void) {
	static NSMutableDictionary *d;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
	return d;
}

@interface RYGPlaybackPanel : UIView
@property (nonatomic, weak) UIWindow *hostWindow;
- (instancetype)initWithSurface:(RYGPlaybackSurface)surface;
- (void)present;
@end

@interface RYGPlaybackMenu ()
+ (NSArray<UIView *> *)sectionsForSurface:(RYGPlaybackSurface)surface;
@end

@implementation RYGPlaybackMenu

+ (void)registerModuleWithID:(NSString *)moduleID
                     surface:(RYGPlaybackSurface)surface
                        isOn:(RYGPlaybackModuleIsOn)isOn
                buildSection:(RYGPlaybackModuleBuildSection)buildSection {
	if (!moduleID || !surface || !isOn || !buildSection) return;
	NSMutableArray *list = rygPlaybackModules();
	@synchronized (list) {
		[list addObject:@{ @"id": moduleID, @"surface": surface,
						   @"isOn": [isOn copy], @"build": [buildSection copy] }];
	}
}

+ (NSArray *)_modulesForSurface:(RYGPlaybackSurface)surface {
	NSMutableArray *list = rygPlaybackModules();
	NSArray *snapshot;
	@synchronized (list) { snapshot = [list copy]; }
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *entry in snapshot)
		if ([entry[@"surface"] isEqualToString:surface]) [out addObject:entry];
	return out;
}

+ (BOOL)anyModuleEnabledForSurface:(RYGPlaybackSurface)surface {
	for (NSDictionary *entry in [self _modulesForSurface:surface]) {
		RYGPlaybackModuleIsOn isOn = entry[@"isOn"];
		if (isOn && isOn()) return YES;
	}
	return NO;
}

+ (NSArray<UIView *> *)sectionsForSurface:(RYGPlaybackSurface)surface {
	NSMutableArray<UIView *> *out = [NSMutableArray array];
	for (NSDictionary *entry in [self _modulesForSurface:surface]) {
		RYGPlaybackModuleIsOn isOn = entry[@"isOn"];
		RYGPlaybackModuleBuildSection build = entry[@"build"];
		if (!isOn || !isOn() || !build) continue;
		UIView *v = build();
		if (v) [out addObject:v];
	}
	return out;
}

+ (void)setAnchorHandler:(void (^)(UIView *))handler forSurface:(RYGPlaybackSurface)surface {
	if (!surface) return;
	rygPlaybackAnchorHandlers()[surface] = [handler copy] ?: (id)[NSNull null];
}

+ (void)installLongPressOnView:(UIView *)view surface:(RYGPlaybackSurface)surface {
	if (!view || !surface || objc_getAssociatedObject(view, kRYGPlaybackLPRKey)) return;
	UILongPressGestureRecognizer *lpr = [[UILongPressGestureRecognizer alloc]
		initWithTarget:self action:@selector(_longPress:)];
	lpr.minimumPressDuration = 0.32;
	lpr.cancelsTouchesInView = YES;
	[view addGestureRecognizer:lpr];
	objc_setAssociatedObject(view, kRYGPlaybackLPRKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (void)_longPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan) return;
	UIView *anchor = gr.view;
	RYGPlaybackSurface surface = objc_getAssociatedObject(anchor, kRYGPlaybackLPRKey);
	if (!surface || ![self anyModuleEnabledForSurface:surface]) return;

	if ([anchor isKindOfClass:[UIControl class]]) {
		UIControl *c = (UIControl *)anchor;
		[c cancelTrackingWithEvent:nil];
		c.highlighted = NO;
	}
	[self presentForSurface:surface anchor:anchor];
}

+ (void)presentForSurface:(RYGPlaybackSurface)surface anchor:(UIView *)anchor {
	if (!surface || ![self anyModuleEnabledForSurface:surface]) return;

	id anchorHandler = rygPlaybackAnchorHandlers()[surface];
	if (anchor && anchorHandler && ![anchorHandler isKindOfClass:[NSNull class]])
		((void (^)(UIView *))anchorHandler)(anchor);

	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
	RYGPlaybackPanel *panel = [[RYGPlaybackPanel alloc] initWithSurface:surface];
	panel.hostWindow = anchor.window;
	[panel present];
}

#pragma mark - Stock modules

static double rygClampedPref(NSString *key, double min, double max, double fallback) {
	double v = [RYGUtils getDoublePref:key];
	return (v < min || v > max) ? fallback : v;
}

static void rygStoreClampedPref(NSString *key, double value, double min, double max) {
	[[NSUserDefaults standardUserDefaults] setDouble:MIN(MAX(value, min), max) forKey:key];
}

+ (float)speedRateForKey:(NSString *)key {
	return (float)rygClampedPref(key, 0.5, 2.0, 1.0);
}

+ (double)seekStepForKey:(NSString *)key {
	return rygClampedPref(key, 1.0, 600.0, 10.0);
}

+ (void)registerSpeedModuleForSurface:(RYGPlaybackSurface)surface
                           enabledKey:(NSString *)enabledKey
                              rateKey:(NSString *)rateKey
                                apply:(void (^)(float))apply {
	[self registerModuleWithID:@"speed"
					   surface:surface
						  isOn:^BOOL { return [RYGUtils getBoolPref:enabledKey]; }
				  buildSection:^UIView *{
		RYGPlaybackSpeedView *content = [[RYGPlaybackSpeedView alloc]
			initWithRate:[self speedRateForKey:rateKey] onChange:^(float rate) {
				rygStoreClampedPref(rateKey, rate, 0.5, 2.0);
				if (apply) apply(rate);
			}];
		return [[RYGPlaybackSection alloc] initWithTitle:RYGLocalized(@"Speed") content:content];
	}];
}

+ (void)registerTransportModuleForSurface:(RYGPlaybackSurface)surface
                                  seekKey:(NSString *)seekKey
                                  stepKey:(NSString *)stepKey
                                   onSeek:(void (^)(double))onSeek
                                 pauseKey:(NSString *)pauseKey
                              pauseToggle:(void (^)(void))pauseToggle
                                isPlaying:(BOOL (^)(void))isPlaying {
	BOOL (^seekOn)(void) = ^BOOL { return seekKey && [RYGUtils getBoolPref:seekKey]; };
	BOOL (^pauseOn)(void) = ^BOOL { return pauseKey && [RYGUtils getBoolPref:pauseKey]; };

	[self registerModuleWithID:@"transport"
					   surface:surface
						  isOn:^BOOL { return seekOn() || pauseOn(); }
				  buildSection:^UIView *{
		BOOL seek = seekOn(), pause = pauseOn();
		RYGPlaybackSeekView *content = [[RYGPlaybackSeekView alloc]
			initWithStep:[self seekStepForKey:stepKey]
		   stepDidChange:seek ? ^(double step) { rygStoreClampedPref(stepKey, step, 1.0, 600.0); } : nil
				  onSeek:seek ? onSeek : nil
			 pauseToggle:pause ? pauseToggle : nil
			   isPlaying:pause ? isPlaying : nil];
		return [[RYGPlaybackSection alloc]
			initWithTitle:seek ? RYGLocalized(@"Seek") : RYGLocalized(@"Playback") content:content];
	}];
}

@end

#pragma mark - Section card

@implementation RYGPlaybackSection

- (instancetype)initWithTitle:(NSString *)title content:(UIView *)content {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		UILabel *header = [UILabel new];
		header.translatesAutoresizingMaskIntoConstraints = NO;
		header.text = [title uppercaseString];
		header.textColor = [UIColor colorWithWhite:1 alpha:0.55];
		header.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
		[self addSubview:header];

		content.translatesAutoresizingMaskIntoConstraints = NO;
		[self addSubview:content];

		[NSLayoutConstraint activateConstraints:@[
			[header.topAnchor constraintEqualToAnchor:self.topAnchor],
			[header.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
			[header.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-18],

			[content.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
			[content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
			[content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
		]];
	}
	return self;
}

@end

#pragma mark - Panel

@implementation RYGPlaybackPanel {
	UIView *_card;
	UIStackView *_stack;
}

- (instancetype)initWithSurface:(RYGPlaybackSurface)surface {
	if ((self = [super initWithFrame:UIScreen.mainScreen.bounds])) {
		self.tag = kRYGPlaybackPanelTag;
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(_onBackdropTap:)];
		tap.cancelsTouchesInView = NO;
		[self addGestureRecognizer:tap];

		_card = [UIView new];
		_card.translatesAutoresizingMaskIntoConstraints = NO;
		_card.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
		_card.layer.cornerRadius = 22;
		_card.layer.cornerCurve = kCACornerCurveContinuous;
		_card.layer.masksToBounds = YES;
		_card.layer.borderWidth = 0.5;
		_card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.10].CGColor;
		[self addSubview:_card];

		UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(_onCardPan:)];
		[_card addGestureRecognizer:pan];

		UILabel *title = [UILabel new];
		title.translatesAutoresizingMaskIntoConstraints = NO;
		title.text = RYGLocalized(@"Playback");
		title.textColor = [UIColor whiteColor];
		title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
		[_card addSubview:title];

		UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
		close.translatesAutoresizingMaskIntoConstraints = NO;
		UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
			configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
		[close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg]
			   forState:UIControlStateNormal];
		close.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
		close.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
		close.layer.cornerRadius = 14;
		[close addTarget:self action:@selector(_dismiss) forControlEvents:UIControlEventTouchUpInside];
		[_card addSubview:close];

		_stack = [UIStackView new];
		_stack.translatesAutoresizingMaskIntoConstraints = NO;
		_stack.axis = UILayoutConstraintAxisVertical;
		_stack.spacing = 14;
		_stack.alignment = UIStackViewAlignmentFill;
		[_card addSubview:_stack];

		NSArray<UIView *> *sections = [RYGPlaybackMenu sectionsForSurface:surface];
		for (NSUInteger i = 0; i < sections.count; i++) {
			[_stack addArrangedSubview:sections[i]];
			if (i + 1 < sections.count) {
				UIView *divider = [UIView new];
				divider.translatesAutoresizingMaskIntoConstraints = NO;
				divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
				[divider.heightAnchor constraintEqualToConstant:0.5].active = YES;
				[_stack addArrangedSubview:divider];
			}
		}

		[NSLayoutConstraint activateConstraints:@[
			[_card.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
			[_card.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
			[_card.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-100],

			[title.topAnchor constraintEqualToAnchor:_card.topAnchor constant:14],
			[title.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:18],

			[close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
			[close.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-10],
			[close.widthAnchor constraintEqualToConstant:28],
			[close.heightAnchor constraintEqualToConstant:28],

			[_stack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
			[_stack.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
			[_stack.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
			[_stack.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-16],
		]];
	}
	return self;
}

- (void)_onBackdropTap:(UITapGestureRecognizer *)gr {
	CGPoint pt = [gr locationInView:self];
	if (CGRectContainsPoint(_card.frame, pt)) return;
	[self _dismiss];
}

- (void)_onCardPan:(UIPanGestureRecognizer *)gr {
	CGFloat ty = [gr translationInView:self].y;
	switch (gr.state) {
		case UIGestureRecognizerStateChanged: {
			CGFloat y = ty > 0 ? ty : ty * 0.2;
			_card.transform = CGAffineTransformMakeTranslation(0, y);
			CGFloat p = ty > 0 ? MAX(0, 1 - ty / 400.0) : 1;
			self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18 * p];
			break;
		}
		case UIGestureRecognizerStateEnded:
		case UIGestureRecognizerStateCancelled: {
			CGFloat vy = [gr velocityInView:self].y;
			if (ty > 90 || vy > 800) { [self _dismiss]; return; }
			[UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5
								options:UIViewAnimationOptionCurveEaseOut animations:^{
				self->_card.transform = CGAffineTransformIdentity;
				self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
			} completion:nil];
			break;
		}
		default: break;
	}
}

- (void)present {
	UIWindow *win = self.hostWindow;
	if (!win) {
		for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
			if (![s isKindOfClass:[UIWindowScene class]]) continue;
			for (UIWindow *w in ((UIWindowScene *)s).windows) {
				if (w.isKeyWindow) { win = w; break; }
			}
			if (win) break;
			win = ((UIWindowScene *)s).windows.firstObject;
		}
	}
	if (!win) return;

	[[win viewWithTag:kRYGPlaybackPanelTag] removeFromSuperview];

	self.frame = win.bounds;
	self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[win addSubview:self];

	_card.transform = CGAffineTransformMakeTranslation(0, 140);
	_card.alpha = 0;
	[UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0.6
						options:UIViewAnimationOptionCurveEaseOut animations:^{
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
		self->_card.transform = CGAffineTransformIdentity;
		self->_card.alpha = 1.0;
	} completion:nil];
}

- (void)_dismiss {
	[UIView animateWithDuration:0.20 animations:^{
		self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.0];
		self->_card.transform = CGAffineTransformMakeTranslation(0, 140);
		self->_card.alpha = 0;
	} completion:^(BOOL fin) {
		[self removeFromSuperview];
	}];
}

@end
