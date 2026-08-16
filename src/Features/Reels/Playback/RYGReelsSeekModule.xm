// Seek section for the reel Playback menu — step presets + skip buttons.

#import "RYGReelsPlaybackMenu.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static inline BOOL rygSeekEnabled(void) {
	return [RYGUtils getBoolPref:@"reels_playback_seek"];
}

static double rygSeekStep(void) {
	double v = [RYGUtils getDoublePref:@"reels_playback_seek_step"];
	if (v < 1.0 || v > 600.0) v = 10.0;
	return v;
}

static void rygStoreSeekStep(double step) {
	if (step < 1.0) step = 1.0;
	if (step > 600.0) step = 600.0;
	[[NSUserDefaults standardUserDefaults] setDouble:step forKey:@"reels_playback_seek_step"];
}

static SEL rygCellSeekSel(void) {
	return @selector(seekToTime:preciseTime:trigger:isSeekingOnTap:completionHandler:);
}

// Tracks the playing cell so the menu follows auto-scroll without reopening.
static __weak id sCurrentReelCell;

static id rygActiveReelCell(void) {
	id c = sCurrentReelCell;
	if (c && [c respondsToSelector:rygCellSeekSel()]
		&& [c isKindOfClass:[UIView class]] && ((UIView *)c).window) return c;
	return [RYGReelsPlaybackMenu capturedReelCell];
}

%hook IGSundialViewerVideoCell
- (void)videoViewDidUnpause:(id)v { %orig; sCurrentReelCell = self; }
- (void)videoView:(id)v didInitialPlayWithStatus:(id)s { %orig; sCurrentReelCell = self; }
%end

// Accumulate from the last target when currentPlaybackTime hasn't caught up yet.
static __weak id sLastSeekCell;
static double sLastSeekTarget = -1;

static void rygSeekBy(double delta) {
	id cell = rygActiveReelCell();
	if (!cell || ![cell respondsToSelector:rygCellSeekSel()]) return;

	double cur = [cell respondsToSelector:@selector(currentPlaybackTime)]
		? ((double(*)(id, SEL))objc_msgSend)(cell, @selector(currentPlaybackTime)) : 0;

	double base = cur;
	if (cell == sLastSeekCell && sLastSeekTarget >= 0 && cur <= 0.05) base = sLastSeekTarget;

	double target = base + delta;
	if (target < 0) target = 0;

	@try {
		((void(*)(id, SEL, double, BOOL, NSInteger, BOOL, id))objc_msgSend)
			(cell, rygCellSeekSel(), target, YES, 0, NO, nil);
	} @catch (__unused id e) {}

	sLastSeekCell = cell;
	sLastSeekTarget = target;

	UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc]
		initWithStyle:UIImpactFeedbackStyleLight];
	[h impactOccurred];
}

#pragma mark - Seek section view

@interface RYGReelsSeekView : UIView
@end

@implementation RYGReelsSeekView {
	UIScrollView *_scroll;
	UIStackView *_pillRow;
	NSArray<NSNumber *> *_presets;
	NSMutableArray<UIButton *> *_presetPills;
	UIButton *_customPill;
	UIButton *_backBtn;
	UIButton *_fwdBtn;
}

- (instancetype)init {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;
		_presets = @[ @1, @5, @10, @15, @30 ];

		UIStackView *col = [UIStackView new];
		col.translatesAutoresizingMaskIntoConstraints = NO;
		col.axis = UILayoutConstraintAxisVertical;
		col.spacing = 10;
		col.alignment = UIStackViewAlignmentFill;
		[self addSubview:col];

		_scroll = [UIScrollView new];
		_scroll.translatesAutoresizingMaskIntoConstraints = NO;
		_scroll.showsHorizontalScrollIndicator = NO;
		_scroll.contentInset = UIEdgeInsetsMake(0, 18, 0, 18);

		_pillRow = [UIStackView new];
		_pillRow.translatesAutoresizingMaskIntoConstraints = NO;
		_pillRow.axis = UILayoutConstraintAxisHorizontal;
		_pillRow.spacing = 6;
		_pillRow.alignment = UIStackViewAlignmentCenter;
		[_scroll addSubview:_pillRow];

		_presetPills = [NSMutableArray array];
		for (NSNumber *n in _presets) {
			UIButton *p = [self _pillWithTitle:[NSString stringWithFormat:@"%gs", n.doubleValue]
										 action:@selector(_onPresetTap:)];
			p.tag = (NSInteger)(n.doubleValue * 10);
			[_pillRow addArrangedSubview:p];
			[_presetPills addObject:p];
		}

		_customPill = [self _pillWithTitle:RYGLocalized(@"Custom") action:@selector(_onCustomTap)];
		[_pillRow addArrangedSubview:_customPill];

		UIStackView *actionRow = [UIStackView new];
		actionRow.translatesAutoresizingMaskIntoConstraints = NO;
		actionRow.axis = UILayoutConstraintAxisHorizontal;
		actionRow.spacing = 10;
		actionRow.distribution = UIStackViewDistributionFillEqually;

		_backBtn = [self _actionPillWithSymbol:@"gobackward" action:@selector(_onBack)];
		_fwdBtn = [self _actionPillWithSymbol:@"goforward" action:@selector(_onForward)];
		[actionRow addArrangedSubview:_backBtn];
		[actionRow addArrangedSubview:_fwdBtn];

		[col addArrangedSubview:_scroll];
		[col addArrangedSubview:actionRow];

		[NSLayoutConstraint activateConstraints:@[
			[col.topAnchor constraintEqualToAnchor:self.topAnchor],
			[col.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[col.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
			[col.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

			[_scroll.heightAnchor constraintEqualToConstant:32],
			[_pillRow.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
			[_pillRow.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
			[_pillRow.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
			[_pillRow.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
			[_pillRow.heightAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.heightAnchor],

			[actionRow.leadingAnchor constraintEqualToAnchor:col.leadingAnchor constant:18],
			[actionRow.trailingAnchor constraintEqualToAnchor:col.trailingAnchor constant:-18],
		]];

		[self _refresh];
	}
	return self;
}

- (UIButton *)_pillWithTitle:(NSString *)title action:(SEL)action {
	UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
	p.translatesAutoresizingMaskIntoConstraints = NO;
	[p setTitle:title forState:UIControlStateNormal];
	p.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	p.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
	p.layer.cornerRadius = 16;
	p.layer.cornerCurve = kCACornerCurveContinuous;
	p.layer.borderWidth = 1;
	[p addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[p.heightAnchor constraintEqualToConstant:32].active = YES;
	return p;
}

- (UIButton *)_actionPillWithSymbol:(NSString *)symbol action:(SEL)action {
	UIButton *p = [UIButton buttonWithType:UIButtonTypeCustom];
	p.translatesAutoresizingMaskIntoConstraints = NO;
	UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
		configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
	[p setImage:[[UIImage systemImageNamed:symbol withConfiguration:cfg]
		imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	p.tintColor = [UIColor whiteColor];
	p.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	[p setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	p.imageEdgeInsets = UIEdgeInsetsMake(0, -6, 0, 0);
	p.layer.cornerRadius = 18;
	p.layer.cornerCurve = kCACornerCurveContinuous;
	p.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
	[p addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	[p.heightAnchor constraintEqualToConstant:40].active = YES;
	return p;
}

- (void)_stylePill:(UIButton *)p selected:(BOOL)sel {
	p.backgroundColor = sel ? [UIColor whiteColor] : [UIColor clearColor];
	p.layer.borderColor = (sel ? [UIColor clearColor]
		: [UIColor colorWithWhite:1 alpha:0.30]).CGColor;
	[p setTitleColor:sel ? [UIColor blackColor] : [UIColor whiteColor]
			forState:UIControlStateNormal];
}

- (void)_refresh {
	double step = rygSeekStep();
	BOOL isPreset = NO;
	for (NSUInteger i = 0; i < _presets.count; i++) {
		BOOL sel = (_presets[i].doubleValue == step);
		if (sel) isPreset = YES;
		[self _stylePill:_presetPills[i] selected:sel];
	}

	[self _stylePill:_customPill selected:!isPreset];
	[_customPill setTitle:isPreset ? RYGLocalized(@"Custom")
		: [NSString stringWithFormat:@"%gs", step] forState:UIControlStateNormal];

	NSString *label = [NSString stringWithFormat:@"  %gs", step];
	[_backBtn setTitle:label forState:UIControlStateNormal];
	[_fwdBtn setTitle:label forState:UIControlStateNormal];
}

- (void)_onPresetTap:(UIButton *)sender {
	rygStoreSeekStep((double)sender.tag / 10.0);
	[self _refresh];
	UISelectionFeedbackGenerator *h = [UISelectionFeedbackGenerator new];
	[h selectionChanged];
}

- (void)_onCustomTap {
	UIViewController *presenter = nil;
	for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
		if (![s isKindOfClass:[UIWindowScene class]]) continue;
		for (UIWindow *w in ((UIWindowScene *)s).windows) {
			if (w.isKeyWindow) { presenter = w.rootViewController; break; }
		}
		if (presenter) break;
	}
	while (presenter.presentedViewController) presenter = presenter.presentedViewController;
	if (!presenter) return;

	UIAlertController *ac = [UIAlertController
		alertControllerWithTitle:RYGLocalized(@"Custom seek step")
						 message:RYGLocalized(@"Enter the number of seconds to skip")
				  preferredStyle:UIAlertControllerStyleAlert];
	[ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.keyboardType = UIKeyboardTypeDecimalPad;
		tf.text = [NSString stringWithFormat:@"%g", rygSeekStep()];
		tf.clearButtonMode = UITextFieldViewModeAlways;
	}];
	__weak RYGReelsSeekView *ws = self;
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Apply")
										   style:UIAlertActionStyleDefault
										 handler:^(UIAlertAction *a) {
		double v = ac.textFields.firstObject.text.doubleValue;
		if (v < 1.0) v = 1.0;
		if (v > 600.0) v = 600.0;
		rygStoreSeekStep(v);
		[ws _refresh];
	}]];
	[ac addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[presenter presentViewController:ac animated:YES completion:nil];
}

- (void)_onBack { rygSeekBy(-rygSeekStep()); }
- (void)_onForward { rygSeekBy(rygSeekStep()); }

@end

#pragma mark - Module registration

%ctor {
	[RYGReelsPlaybackMenu registerModuleWithID:@"seek"
		isOn:^BOOL { return rygSeekEnabled(); }
		buildSection:^UIView *{
			return [[RYGReelsPlaybackSection alloc] initWithTitle:RYGLocalized(@"Seek")
														 content:[RYGReelsSeekView new]];
		}];
}
