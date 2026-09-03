// Long-press entry point for the reel Playback menu: the ⋯ and audio buttons on the reel UFI.

#import "RYGReelsPlaybackEntry.h"
#import "../../../Utils.h"
#import "../../../InstagramHeaders.h"
#import <objc/runtime.h>

static __weak UIView *sCapturedReelCell;

@implementation RYGReelsPlaybackEntry

+ (UIView *)capturedReelCell { return sCapturedReelCell; }

@end

static void rygCaptureReelCellFromAnchor(UIView *anchor) {
	UIView *cell = nil;
	for (UIView *node = anchor; node; node = node.superview) {
		if ([NSStringFromClass([node class]) hasSuffix:@"IGSundialViewerVideoCell"]) {
			cell = node; break;
		}
	}
	sCapturedReelCell = cell;
}

static void rygInstallReelsLongPress(id ufi, NSString *key) {
	UIButton *btn = nil;
	@try { btn = [ufi valueForKey:key]; } @catch (__unused id e) {}
	[RYGPlaybackMenu installLongPressOnView:btn surface:RYGPlaybackSurfaceReels];
}

%hook _TtC26IGSundialViewerVerticalUFI26IGSundialViewerVerticalUFI

- (void)layoutSubviews {
	%orig;
	if (![RYGPlaybackMenu anyModuleEnabledForSurface:RYGPlaybackSurfaceReels]) return;
	rygInstallReelsLongPress(self, @"moreOptionsButton");
	rygInstallReelsLongPress(self, @"audioAttributionButton");
}

%end

%ctor {
	[RYGPlaybackMenu setAnchorHandler:^(UIView *anchor) {
		rygCaptureReelCellFromAnchor(anchor);
	} forSurface:RYGPlaybackSurfaceReels];
}
