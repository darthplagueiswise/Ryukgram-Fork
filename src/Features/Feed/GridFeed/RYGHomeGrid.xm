#import "RYGHomeGridController.h"
#import "RYGGridFeedInfo.h"
#import <objc/runtime.h>

static char kRYGHomeGridKey;

static RYGHomeGridController *rygGridFor(id vc) {
	RYGHomeGridController *c = objc_getAssociatedObject(vc, &kRYGHomeGridKey);
	if (!c) {
		c = [[RYGHomeGridController alloc] initWithHost:vc];
		objc_setAssociatedObject(vc, &kRYGHomeGridKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	return c;
}

// Only installed when the feature is on at launch (see %ctor) — zero overhead when off.
// The grid/native-feed switch inside a session is the controller's live toggle.
%group RYGHomeGrid
%hook _TtC14IGHomeMainFeed28IGHomeMainFeedViewController

- (void)viewDidLoad {
	%orig;
	[rygGridFor(self) syncActive];
}

- (void)viewWillAppear:(BOOL)animated {
	%orig;
	[rygGridFor(self) syncActive];
}

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	[rygGridFor(self) recoverStoryTray];
}

- (void)viewDidLayoutSubviews {
	%orig;
	[rygGridFor(self) hostDidLayout];
}

%end
%end

%ctor {
	if ([RYGGridFeedInfo active]) %init(RYGHomeGrid);
}
