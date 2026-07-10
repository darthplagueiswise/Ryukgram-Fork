// Auto-scroll section for the reel Playback menu — 3-way mode segmented control.

#import "SCIReelsPlaybackMenu.h"
#import "../../../Utils.h"
#import <objc/runtime.h>

static inline BOOL sciAutoScrollMenuEnabled(void) {
	return [SCIUtils getBoolPref:@"reels_playback_autoscroll"];
}

static NSArray<NSString *> *sciAutoScrollValues(void) {
	return @[ @"off", @"ig", @"custom" ];
}

@interface SCIReelsAutoScrollView : UIView
@end

@implementation SCIReelsAutoScrollView {
	UISegmentedControl *_seg;
}

- (instancetype)init {
	if ((self = [super initWithFrame:CGRectZero])) {
		self.translatesAutoresizingMaskIntoConstraints = NO;

		_seg = [[UISegmentedControl alloc] initWithItems:@[
			SCILocalized(@"Off"), SCILocalized(@"IG default"), SCILocalized(@"RyukGram") ]];
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
	NSString *mode = [SCIUtils getStringPref:@"auto_scroll_reels_mode"];
	NSUInteger idx = [sciAutoScrollValues() indexOfObject:mode ?: @"off"];
	_seg.selectedSegmentIndex = (idx == NSNotFound) ? 0 : idx;
}

- (void)_onChange {
	NSArray<NSString *> *vals = sciAutoScrollValues();
	NSInteger i = _seg.selectedSegmentIndex;
	if (i < 0 || i >= (NSInteger)vals.count) return;
	[[NSUserDefaults standardUserDefaults] setObject:vals[i] forKey:@"auto_scroll_reels_mode"];
	UISelectionFeedbackGenerator *h = [UISelectionFeedbackGenerator new];
	[h selectionChanged];
}

@end

#pragma mark - Module registration

%ctor {
	[SCIReelsPlaybackMenu registerModuleWithID:@"autoscroll"
		isOn:^BOOL { return sciAutoScrollMenuEnabled(); }
		buildSection:^UIView *{
			return [[SCIReelsPlaybackSection alloc] initWithTitle:SCILocalized(@"Auto-scroll reels")
														 content:[SCIReelsAutoScrollView new]];
		}];
}
