// Home feed status bar tap: the scroll-to-top gesture that also refreshes.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>

static NSTimeInterval rygTopTapAt = 0;

static NSString *rygTopTapMode(void) {
	return [RYGUtils getStringPref:@"feed_statusbar_tap"];
}

static BOOL rygTopTapDisabled(void) { return [rygTopTapMode() isEqualToString:@"off"]; }

static void rygTopTapMark(void) {
	rygTopTapAt = [NSDate date].timeIntervalSinceReferenceDate;
}

static void rygTopTapApply(id vc) {
	Ivar iv = class_getInstanceVariable([vc class], "_collectionView");
	UIScrollView *sv = iv ? object_getIvar(vc, iv) : nil;
	if ([sv isKindOfClass:UIScrollView.class]) sv.scrollsToTop = !rygTopTapDisabled();
}

static BOOL rygTopTapSkipRefresh(void) {
	if (![rygTopTapMode() isEqualToString:@"scroll"]) return NO;
	if ([NSDate date].timeIntervalSinceReferenceDate - rygTopTapAt >= 2.0) return NO;
	rygTopTapAt = 0;
	return YES;
}

%group RYGTopTapObjc
%hook IGMainFeedViewController_objc

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygTopTapApply(self);
}

- (void)scrollViewWillScrollToTop:(UIScrollView *)scrollView {
	RYGProbeOnce(@"feedtoptap.will", @"status bar scroll-to-top on home feed");
	rygTopTapMark();
	%orig;
}

- (void)refreshFeedWithFetchReason:(long long)reason animated:(BOOL)animated {
	RYGProbeOnce(@"feedtoptap.refresh", @"refreshFeedWithFetchReason reached");
	if (rygTopTapSkipRefresh()) return;
	%orig;
}

%end
%end

%group RYGTopTapSwift
%hook _TtC15IGMainFeedSwift30IGMainFeedViewController_swift

- (void)viewDidAppear:(BOOL)animated {
	%orig;
	rygTopTapApply(self);
}

- (void)scrollViewWillScrollToTop:(UIScrollView *)scrollView {
	RYGProbeOnce(@"feedtoptap.will.swift", @"status bar scroll-to-top on home feed");
	rygTopTapMark();
	%orig;
}

- (void)refreshFeedWithFetchReason:(long long)reason animated:(BOOL)animated {
	RYGProbeOnce(@"feedtoptap.refresh.swift", @"refreshFeedWithFetchReason reached");
	if (rygTopTapSkipRefresh()) return;
	%orig;
}

%end
%end

%ctor {
	if ([rygTopTapMode() isEqualToString:@"default"]) return;
	if (NSClassFromString(@"IGMainFeedViewController_objc")) %init(RYGTopTapObjc);
	if (NSClassFromString(@"_TtC15IGMainFeedSwift30IGMainFeedViewController_swift")) %init(RYGTopTapSwift);
}
