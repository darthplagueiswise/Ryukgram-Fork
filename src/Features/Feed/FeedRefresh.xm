// Home-feed pull-to-refresh: confirm dialog + stories-only refresh

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL rygFeedRefreshBypassing = NO;
static BOOL rygFeedRefreshAlertShowing = NO;
static NSTimeInterval rygFeedLastStoriesFetch = 0;

static inline BOOL rygFeedConfirm(void) { return [RYGUtils getBoolPref:@"refresh_feed_confirm"]; }
static inline BOOL rygFeedStoriesOnly(void) { return [RYGUtils getBoolPref:@"refresh_feed_stories_only"]; }

static IGMainFeedViewModel *rygFeedViewModel(id vc) {
	if ([vc respondsToSelector:@selector(viewModel)]) {
		return ((id (*)(id, SEL))objc_msgSend)(vc, @selector(viewModel));
	}
	return nil;
}

static void RYGFeedEndRefresh(id vc) {
	if (!vc) return;

	Ivar iv = class_getInstanceVariable([vc class], "_refreshControl");
	IGRefreshControl *rc = iv ? object_getIvar(vc, iv) : nil;

	if (rc) {
		Ivar st = class_getInstanceVariable([rc class], "_refreshState");
		if (st) *(long long *)((char *)(__bridge void *)rc + ivar_getOffset(st)) = 0;
	}

	if ([vc respondsToSelector:@selector(refreshControlDidEndFinishLoadingAnimation:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(vc, @selector(refreshControlDidEndFinishLoadingAnimation:), rc);
	}
}

static void RYGFeedStoriesOnlyRefresh(id vc) {
	NSTimeInterval now = [NSDate date].timeIntervalSinceReferenceDate;
	if (now - rygFeedLastStoriesFetch > 1.0) {
		rygFeedLastStoriesFetch = now;

		IGMainFeedViewModel *vm = rygFeedViewModel(vc);
		long long reason = 0;
		if ([vm respondsToSelector:@selector(lastFetchReasonForRefresh)]) reason = [vm lastFetchReasonForRefresh];
		if ([vm respondsToSelector:@selector(fetchDataOnStoryTrayWithMainFeedFetchReason:)]) {
			[vm fetchDataOnStoryTrayWithMainFeedFetchReason:reason];
		}
		if ([vc respondsToSelector:@selector(reloadStoryTray)]) {
			((void (*)(id, SEL))objc_msgSend)(vc, @selector(reloadStoryTray));
		}
	}
	RYGFeedEndRefresh(vc);
}

static void rygFeedHandlePTR(id vc, void (^orig)(void)) {
	RYGProbeOnce(@"feedrefresh.ptr", @"home feed pull-to-refresh fired");

	BOOL confirm = rygFeedConfirm();
	BOOL storiesOnly = rygFeedStoriesOnly();

	if (rygFeedRefreshBypassing || (!confirm && !storiesOnly)) { orig(); return; }

	void (^effective)(void) = ^{
		if (storiesOnly) { RYGFeedStoriesOnlyRefresh(vc); }
		else { orig(); }
	};

	if (!confirm) { effective(); return; }

	UIViewController *presenter = (UIViewController *)vc;
	if (![presenter isViewLoaded] || rygFeedRefreshAlertShowing || presenter.presentedViewController) {
		RYGFeedEndRefresh(vc);
		return;
	}

	RYGFeedEndRefresh(vc);
	rygFeedRefreshAlertShowing = YES;

	UIAlertController *alert = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Refresh feed?")
		message:nil
		preferredStyle:UIAlertControllerStyleAlert];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel")
		style:UIAlertActionStyleCancel
		handler:^(__unused UIAlertAction *action) {
			rygFeedRefreshAlertShowing = NO;
		}]];

	[alert addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Refresh")
		style:UIAlertActionStyleDefault
		handler:^(__unused UIAlertAction *action) {
			effective();
			rygFeedRefreshAlertShowing = NO;
		}]];

	[presenter presentViewController:alert animated:YES completion:nil];
}

%group RYGFeedRefreshObjc
%hook IGMainFeedViewController_objc
- (void)_refreshWhenPTR {
	rygFeedHandlePTR(self, ^{ %orig; });
}
%end
%end

%group RYGFeedRefreshSwift
%hook _TtC15IGMainFeedSwift30IGMainFeedViewController_swift
- (void)refreshWhenPTR {
	rygFeedHandlePTR(self, ^{ %orig; });
}
%end
%end

%ctor {
	if (NSClassFromString(@"IGMainFeedViewController_objc")) %init(RYGFeedRefreshObjc);
	if (NSClassFromString(@"_TtC15IGMainFeedSwift30IGMainFeedViewController_swift")) %init(RYGFeedRefreshSwift);
}
