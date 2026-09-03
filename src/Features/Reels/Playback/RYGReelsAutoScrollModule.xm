// Auto-scroll section for the reel Playback menu — 3-way mode segmented control.

#import "../../Playback/RYGPlaybackMenu.h"
#import "../../../Utils.h"
#import <objc/runtime.h>

static inline BOOL rygAutoScrollMenuEnabled(void) {
	return [RYGUtils getBoolPref:@"reels_playback_autoscroll"];
}

static NSArray<NSString *> *rygAutoScrollValues(void) {
	return @[ @"off", @"ig", @"custom" ];
}

@interface RYGReelsAutoScrollView : UIView
@end

@implementation RYGReelsAutoScrollView {
	UISegmentedControl *_seg;
}

- (instancetype)init {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		_seg = [[UISegmentedControl alloc] initWithItems:@[
			RYGLocalized(@"Off"), RYGLocalized(@"IG default"), RYGLocalized(@"RyukGram") ]];
		_seg.translatesAutoresizingMaskIntoConstraints = NO;
		_seg.selectedSegmentTintColor = [UIColor whiteColor];
		_seg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
		[_seg setTitleTextAttributes:@{ NSForegroundColorAttributeName: [UIColor whiteColor],
			NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] }
							forState:UIControlStateNormal];
		[_seg setTitleTextAttributes:@{ NSForegroundColorAttributeName: [UIColor blackColor],
			NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] }
							forState:UIControlStateSelected];
		[_seg addTarget:self action:@selector(_onChange) forControlEvents:UIControlEventValueChanged];
		[self addSubview:_seg];

		[NSLayoutConstraint activateConstraints:@[
			[_seg.topAnchor constraintEqualToAnchor:self.topAnchor],
			[_seg.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
			[_seg.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
			[_seg.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
			[_seg.heightAnchor constraintEqualToConstant:36],
		]];

		[self _refresh];
	}
	return self;
}

- (void)_refresh {
	NSString *mode = [RYGUtils getStringPref:@"auto_scroll_reels_mode"];
	NSUInteger idx = [rygAutoScrollValues() indexOfObject:mode ?: @"off"];
	_seg.selectedSegmentIndex = (idx == NSNotFound) ? 0 : idx;
}

- (void)_onChange {
	NSArray<NSString *> *vals = rygAutoScrollValues();
	NSInteger i = _seg.selectedSegmentIndex;
	if (i < 0 || i >= (NSInteger)vals.count) return;
	[[NSUserDefaults standardUserDefaults] setObject:vals[i] forKey:@"auto_scroll_reels_mode"];
	UISelectionFeedbackGenerator *h = [UISelectionFeedbackGenerator new];
	[h selectionChanged];
}

@end

#pragma mark - Module registration

%ctor {
	[RYGPlaybackMenu registerModuleWithID:@"autoscroll"
		surface:RYGPlaybackSurfaceReels
		isOn:^BOOL { return rygAutoScrollMenuEnabled(); }
		buildSection:^UIView *{
			return [[RYGPlaybackSection alloc] initWithTitle:RYGLocalized(@"Auto-scroll reels")
													content:[RYGReelsAutoScrollView new]];
		}];
}
