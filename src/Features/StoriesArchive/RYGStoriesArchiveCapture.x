#import "RYGStoriesArchiveManager.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

// IGStoryTraySectionController fires this on every tray refresh (~3x/feed load).
// It's our "own stories may have changed" signal; the manager gates on prefs.
static void (*orig_trayDidUpdate)(id, SEL, id, long long, long long, id, id, unsigned long long);
static void hook_trayDidUpdate(id self, SEL _cmd, id dataController, long long refreshType,
                               long long requestReason, id storyRankToken, id deliveryLoggingKey,
                               unsigned long long prefetchTrigger) {
	orig_trayDidUpdate(self, _cmd, dataController, refreshType, requestReason, storyRankToken, deliveryLoggingKey, prefetchTrigger);

	RYGProbeOnce(@"stories-archive.tray-did-update", @"refreshType=%lld", refreshType);
	[[RYGStoriesArchiveManager shared] handleTraySectionController:self];
	[[RYGStoriesArchiveManager shared] checkAndFetchViewers];
}

// Opening the story viewer (yours or anyone's) re-checks the tray, so a story you
// just posted is captured the moment you open it, not only on the next feed load.
static void (*orig_storyViewerDidAppear)(id, SEL, BOOL);
static void hook_storyViewerDidAppear(id self, SEL _cmd, BOOL animated) {
	orig_storyViewerDidAppear(self, _cmd, animated);
	[[RYGStoriesArchiveManager shared] recheck];
}

%ctor {
	// Zero overhead when off: the hook isn't installed at all until enabled, so
	// the toggle requires a restart to take effect.
	if (![RYGUtils getBoolPref:@"ryg_stories_archive"]) return;

	Class sc = NSClassFromString(@"IGStoryTraySectionController");
	SEL sel = NSSelectorFromString(@"storyDataController:didUpdateWithRefreshType:requestReason:storyRankToken:deliveryLoggingKey:prefetchTrigger:");
	if (sc && class_getInstanceMethod(sc, sel))
		MSHookMessageEx(sc, sel, (IMP)hook_trayDidUpdate, (IMP *)&orig_trayDidUpdate);

	Class viewer = NSClassFromString(@"IGStoryViewerViewController");
	SEL appear = @selector(viewDidAppear:);
	if (viewer && class_getInstanceMethod(viewer, appear))
		MSHookMessageEx(viewer, appear, (IMP)hook_storyViewerDidAppear, (IMP *)&orig_storyViewerDidAppear);
}
