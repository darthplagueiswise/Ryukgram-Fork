#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static inline BOOL rygHideAds(NSString *surface) {
	return [RYGUtils getBoolPref:@"hide_ads"] && [RYGUtils getBoolPref:[@"hide_ads_" stringByAppendingString:surface]];
}

static inline BOOL rygKind(id obj, Class cls) {
	return cls && [obj isKindOfClass:cls];
}

// Swift-ified — only the mangled name is registered with the runtime.
static Class rygInFeedStoriesTrayCls(void) {
	static Class cls;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cls = objc_getClass("_TtC15IGInFeedStories24IGInFeedStoriesTrayModel") ?: objc_getClass("IGInFeedStoriesTrayModel");
	});
	return cls;
}

// Cached pref snapshot — objectsForListAdapter runs per list-diff on the scroll path.
static struct {
	BOOL hideMetaAI, noSuggestedPost, noSuggestedReels, noSuggestedAccount;
	BOOL noSuggestedThreads, hideStoriesTray, hideEntireFeed;
} rygFeedPrefs;
static BOOL rygFeedPrefsStale = YES;

static void rygRefreshFeedPrefs(void) {
	if (!rygFeedPrefsStale) return;
	rygFeedPrefs.hideMetaAI = [RYGUtils getBoolPref:@"hide_meta_ai"];
	rygFeedPrefs.noSuggestedPost = [RYGUtils getBoolPref:@"no_suggested_post"];
	rygFeedPrefs.noSuggestedReels = [RYGUtils getBoolPref:@"no_suggested_reels"];
	rygFeedPrefs.noSuggestedAccount = [RYGUtils getBoolPref:@"no_suggested_account"];
	rygFeedPrefs.noSuggestedThreads = [RYGUtils getBoolPref:@"no_suggested_threads"];
	rygFeedPrefs.hideStoriesTray = [RYGUtils getBoolPref:@"hide_stories_tray"];
	rygFeedPrefs.hideEntireFeed = [RYGUtils getBoolPref:@"hide_entire_feed"];
	rygFeedPrefsStale = NO;
}

static NSArray *removeItemsInList(NSArray *list, BOOL isFeed, BOOL hideAds) {
	if (![list isKindOfClass:NSArray.class] || !list.count) return list;

	rygRefreshFeedPrefs();
	BOOL hideMetaAI = isFeed && rygFeedPrefs.hideMetaAI;
	BOOL noSuggestedPost = isFeed && rygFeedPrefs.noSuggestedPost;
	BOOL noSuggestedReels = isFeed && rygFeedPrefs.noSuggestedReels;
	BOOL noSuggestedAccount = rygFeedPrefs.noSuggestedAccount;
	BOOL noSuggestedThreads = rygFeedPrefs.noSuggestedThreads;
	BOOL hideStoriesTray = isFeed && rygFeedPrefs.hideStoriesTray;
	BOOL hideEntireFeed = isFeed && rygFeedPrefs.hideEntireFeed;

	NSMutableArray *filtered = nil;

	for (id obj in list) {
		BOOL remove = NO;

		// Meta AI in-feed unit ("Try free AI creation tools"). Ivar read — no public getter.
		if (hideMetaAI && [obj isKindOfClass:%c(IGBloksFeedUnitModel)]) {
			static Ivar iv;
			static dispatch_once_t once;
			dispatch_once(&once, ^{
				iv = class_getInstanceVariable(%c(IGBloksFeedUnitModel), "_viewStateItemType");
			});
			if (iv) {
				NSInteger t = *(NSInteger *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
				remove = (t == 251);
			}
		}

		// Suggested posts
		if (!remove && noSuggestedPost) {
			if (([obj isKindOfClass:%c(IGMedia)] && [((IGMedia *)obj).explorePostInFeed isEqual:@YES])
				|| ([obj isKindOfClass:%c(IGFeedGroupHeaderViewModel)] && [[obj title] isEqualToString:@"Suggested Posts"])) remove = YES;
		}

		// Mid-feed stories carousel (suggested / expiring-soon / highlights unit)
		if (!remove && (noSuggestedPost || hideStoriesTray || hideEntireFeed) && rygKind(obj, rygInFeedStoriesTrayCls()))
			remove = YES;

		// Suggested reels carousel
		if (!remove && noSuggestedReels && [obj isKindOfClass:%c(IGFeedScrollableClipsModel)]) remove = YES;

		// Suggested accounts
		if (!remove && noSuggestedAccount) {
			if (([obj isKindOfClass:%c(IGHScrollAYMFModel)]) || [obj isKindOfClass:%c(IGSuggestedUserInReelsModel)]) remove = YES;
		}

		// Suggested threads posts
		if (!remove && noSuggestedThreads) {
			if ((isFeed && ([obj isKindOfClass:%c(IGBloksFeedUnitModel)] || [obj isKindOfClass:objc_getClass("IGThreadsInFeedModels.IGThreadsInFeedModel")]))
				|| [obj isKindOfClass:%c(IGSundialNetegoItem)]) remove = YES;
		}

		// Story tray
		if (!remove && hideStoriesTray && [obj isKindOfClass:%c(IGStoryDataController)]) remove = YES;

		// Hide entire feed
		if (!remove && hideEntireFeed) {
			if ([obj isKindOfClass:%c(IGPostCreationManager)] || [obj isKindOfClass:%c(IGMedia)]
				|| [obj isKindOfClass:%c(IGEndOfFeedDemarcatorModel)] || [obj isKindOfClass:%c(IGSpinnerLabelViewModel)]) remove = YES;
		}

		// Ads
		if (!remove && hideAds) {
			if (([obj isKindOfClass:%c(IGFeedItem)] && ([obj isSponsored] || [obj isSponsoredApp]))
				|| ([obj isKindOfClass:%c(IGDiscoveryGridItem)] && [[obj model] isKindOfClass:%c(IGAdItem)])
				|| [obj isKindOfClass:%c(IGAdItem)]) remove = YES;
		}

		if (remove) {
			if (!filtered) {
				filtered = [NSMutableArray arrayWithCapacity:list.count];
				NSUInteger idx = [list indexOfObjectIdenticalTo:obj];
				if (idx) [filtered addObjectsFromArray:[list subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}

		if (filtered) [filtered addObject:obj];
	}

	return filtered ? filtered.copy : list;
}

static NSArray *removeShortFeedSpinner(NSArray *list) {
	if (list.count > 5) return list;

	NSMutableArray *filtered = nil;
	for (id obj in list) {
		if ([obj isKindOfClass:%c(IGSpinnerLabelViewModel)]) {
			if (!filtered) {
				filtered = [NSMutableArray arrayWithCapacity:list.count];
				NSUInteger idx = [list indexOfObjectIdenticalTo:obj];
				if (idx) [filtered addObjectsFromArray:[list subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}
		if (filtered) [filtered addObject:obj];
	}

	return filtered ? filtered.copy : list;
}

%hook IGMainFeedListAdapterDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
	return removeShortFeedSpinner(removeItemsInList(%orig, YES, rygHideAds(@"feed")));
}
%end

// Doom-scroll windowing — the window sits around the entry media (`initialState.initialVideo`)
// so a reel opened from a profile, explore or DM isn't truncated out of its own list.

static NSString *rygMediaPk(id media) {
	if (![media respondsToSelector:@selector(pk)]) return nil;
	id pk = ((id (*)(id, SEL))objc_msgSend)(media, @selector(pk));
	return [pk isKindOfClass:NSString.class] ? pk : nil;
}

static id rygReadIvar(id obj, const char *name) {
	if (!obj) return nil;
	Ivar iv = class_getInstanceVariable([obj class], name);
	return iv ? object_getIvar(obj, iv) : nil;
}

static NSString *rygEntryMediaPk(id dataSource) {
	id state = rygReadIvar(dataSource, "initialState") ?: rygReadIvar(rygReadIvar(dataSource, "delegate"), "_initialState");
	if (![state respondsToSelector:@selector(initialVideo)]) return nil;

	id media = ((id (*)(id, SEL))objc_msgSend)(state, @selector(initialVideo));
	return rygMediaPk(media);
}

static long long rygReelFCCount(id media, NSString *key) {
	id fc = [RYGUtils fieldCacheValue:media forKey:key];
	if ([fc isKindOfClass:NSNumber.class]) return [fc longLongValue];
	if ([fc isKindOfClass:NSString.class] && [(NSString *)fc length]) return [(NSString *)fc longLongValue];
	return -1;
}

static long long rygReelFCFirst(id media, NSArray<NSString *> *keys) {
	for (NSString *key in keys) {
		long long n = rygReelFCCount(media, key);
		if (n >= 0) return n;
	}
	return -1;
}

static long long rygReelLikes(id media) {
	Ivar iv = class_getInstanceVariable([media class], "_likeCount");
	if (iv) {
		const char *enc = ivar_getTypeEncoding(iv);
		if (enc && (enc[0] == 'q' || enc[0] == 'Q')) {
			long long n = *(long long *)((char *)(__bridge void *)media + ivar_getOffset(iv));
			if (n > 0) return n;
		}
	}
	long long n = rygReelFCFirst(media, @[@"like_count", @"fb_aggregated_like_count", @"fb_like_count"]);
	if (n >= 0) return n;
	if ([media respondsToSelector:@selector(computedLikeCount)]) {
		id v = ((id (*)(id, SEL))objc_msgSend)(media, @selector(computedLikeCount));
		if ([v isKindOfClass:NSNumber.class]) return [v longLongValue];
	}
	return -1;
}

static long long rygReelComments(id media) {
	return rygReelFCFirst(media, @[@"comment_count", @"fb_aggregated_comment_count", @"fb_comment_count"]);
}

static long long rygReelViews(id media) {
	return rygReelFCFirst(media, @[@"play_count", @"view_count", @"ig_play_count", @"fb_play_count"]);
}

static BOOL rygBelowThreshold(long long count, long long minimum) {
	return minimum > 0 && count >= 0 && count < minimum;
}

static BOOL rygReelStatsHidden(id media) {
	id fc = [RYGUtils fieldCacheValue:media forKey:@"like_and_view_counts_disabled"];
	if ([fc respondsToSelector:@selector(boolValue)] && [fc boolValue]) return YES;
	fc = [RYGUtils fieldCacheValue:media forKey:@"hide_like_and_view_counts"];
	return [fc respondsToSelector:@selector(boolValue)] && [fc boolValue];
}

static BOOL rygReelRefilterAttempt(NSString *pk) {
	static NSMutableDictionary *attempts;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ attempts = [NSMutableDictionary new]; });
	if (attempts.count > 600) [attempts removeAllObjects];
	NSInteger n = [attempts[pk] integerValue];
	if (n >= 5) return NO;
	attempts[pk] = @(n + 1);
	return YES;
}

static void rygScheduleReelRefilter(id adapter) {
	static char kPending;
	if (!adapter || objc_getAssociatedObject(adapter, &kPending)) return;
	objc_setAssociatedObject(adapter, &kPending, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	__weak id weakAdapter = adapter;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		id a = weakAdapter;
		if (!a) return;
		objc_setAssociatedObject(a, &kPending, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		if ([a respondsToSelector:@selector(performUpdatesAnimated:completion:)])
			((void (*)(id, SEL, BOOL, id))objc_msgSend)(a, @selector(performUpdatesAnimated:completion:), NO, nil);
	});
}

static NSArray *rygFilterReelsByEngagement(NSArray *list, NSString *entryPk, BOOL *needsRefilter) {
	if (![RYGUtils getBoolPref:@"reels_engagement_filter"]) return list;

	long long minLikes    = (long long)[RYGUtils getDoublePref:@"reels_filter_min_likes"];
	long long minComments = (long long)[RYGUtils getDoublePref:@"reels_filter_min_comments"];
	long long minViews    = (long long)[RYGUtils getDoublePref:@"reels_filter_min_views"];
	long long minReshares = (long long)[RYGUtils getDoublePref:@"reels_filter_min_reshares"];
	BOOL hideHiddenStats = [RYGUtils getBoolPref:@"reels_filter_hide_hidden_stats"];
	if (minLikes <= 0 && minComments <= 0 && minViews <= 0 && minReshares <= 0 && !hideHiddenStats) return list;

	NSMutableArray *filtered = nil;

	for (id obj in list) {
		BOOL hide = NO;
		NSString *pk = [obj isKindOfClass:%c(IGMedia)] ? rygMediaPk(obj) : nil;

		if (pk.length && ![pk isEqualToString:entryPk]) {
			@try {
				long long likes    = rygReelLikes(obj);
				long long comments = rygReelComments(obj);
				long long views    = rygReelViews(obj);
				long long reshares = rygReelFCCount(obj, @"reshare_count");
				BOOL statsHidden   = rygReelStatsHidden(obj);

				hide = (hideHiddenStats && statsHidden)
					|| rygBelowThreshold(likes, minLikes)
					|| rygBelowThreshold(comments, minComments)
					|| rygBelowThreshold(views, minViews)
					|| rygBelowThreshold(reshares, minReshares);

				BOOL unknownRelevant = !statsHidden &&
					(  (minLikes    > 0 && likes    < 0)
					|| (minComments > 0 && comments < 0)
					|| (minViews    > 0 && views    < 0)
					|| (minReshares > 0 && reshares < 0));

				if (!hide && unknownRelevant && needsRefilter && rygReelRefilterAttempt(pk))
					*needsRefilter = YES;
			} @catch (__unused id e) {
				hide = NO;
			}
		}

		if (hide) {
			if (!filtered) {
				filtered = [NSMutableArray arrayWithCapacity:list.count];
				NSUInteger idx = [list indexOfObjectIdenticalTo:obj];
				if (idx) [filtered addObjectsFromArray:[list subarrayWithRange:NSMakeRange(0, idx)]];
			}
			continue;
		}
		if (filtered) [filtered addObject:obj];
	}

	return filtered ? filtered.copy : list;
}

static NSString *rygFeedNetworkSourceName(id obj) {
	if (!obj) return nil;

	unsigned int count = 0;
	Ivar *ivars = class_copyIvarList([obj class], &count);
	NSString *found = nil;

	for (unsigned int i = 0; i < count && !found; i++) {
		const char *enc = ivar_getTypeEncoding(ivars[i]);
		if (!enc || enc[0] != '@' || enc[1] == '?') continue;

		id value = object_getIvar(obj, ivars[i]);
		if (!value) continue;

		NSString *cls = NSStringFromClass([value class]);
		if ([cls containsString:@"FeedNetworkSource"]) found = cls;
	}

	free(ivars);
	return found;
}

static NSString *rygGridFeedSourceName(id gridVC) {
	NSString *name = rygFeedNetworkSourceName(gridVC);
	UIViewController *vc = [gridVC isKindOfClass:UIViewController.class] ? gridVC : nil;
	for (UIViewController *cur = vc.parentViewController; cur && !name; cur = cur.parentViewController)
		name = rygFeedNetworkSourceName(cur);
	return name;
}

// The same grid backs a profile's reels tab, which is browsing, not doom scrolling.
static BOOL rygGridSourceIsPivot(NSString *sourceName) {
	if (!sourceName.length) return NO;
	for (NSString *pivot in @[@"Audio", @"Effects", @"Template", @"Remix", @"CreativeTool", @"ThirdPartyApp", @"OriginalContentPivot"])
		if ([sourceName containsString:pivot]) return YES;
	return NO;
}

static NSArray *rygApplyDoomWindow(id dataSource, NSArray *filtered) {
	if (![RYGUtils getBoolPref:@"prevent_doom_scrolling"]) return filtered;

	NSUInteger limit = (NSUInteger)[RYGUtils getDoublePref:@"doom_scrolling_reel_count"];
	if (!limit || filtered.count <= limit) return filtered;

	NSString *entryPk = rygEntryMediaPk(dataSource);
	if (!entryPk.length)
		return [filtered subarrayWithRange:NSMakeRange(0, MIN(limit, filtered.count))];

	NSInteger entryIdx = NSNotFound;

	for (NSUInteger i = 0; i < filtered.count; i++) {
		id obj = filtered[i];

		if ([rygMediaPk(obj) isEqualToString:entryPk]) {
			entryIdx = (NSInteger)i;
			break;
		}
	}

	// Tapped reel not in list yet — return as-is so IG keeps fetching until it lands.
	if (entryIdx == NSNotFound) return filtered;

	NSUInteger start = (NSUInteger)entryIdx;
	NSUInteger count = MIN(limit, filtered.count - start);

	return [filtered subarrayWithRange:NSMakeRange(start, count)];
}

// The reels tab is the only sundial surface at the root; every tapped reel sits above it.
static BOOL rygReelsSurfaceIsOpenedChain(id listAdapter) {
	UIViewController *vc = nil;
	if ([listAdapter respondsToSelector:@selector(viewController)])
		vc = ((id (*)(id, SEL))objc_msgSend)(listAdapter, @selector(viewController));
	if (![vc isKindOfClass:UIViewController.class]) return YES;

	for (UIViewController *cur = vc; cur; cur = cur.parentViewController) {
		if (cur.presentingViewController.presentedViewController == cur) return YES;
		UINavigationController *nav = cur.navigationController;
		if (nav) {
			NSUInteger i = [nav.viewControllers indexOfObjectIdenticalTo:cur];
			if (i != NSNotFound && i > 0) return YES;
		}
	}
	return NO;
}

static NSArray *rygSundialFilterAndLimit(id dataSource, NSArray *list, id listAdapter) {
	NSArray *filtered = removeItemsInList(list, NO, rygHideAds(@"reels"));

	if (![RYGUtils getBoolPref:@"reels_engagement_filter"]) return rygApplyDoomWindow(dataSource, filtered);

	BOOL tabOnly = [RYGUtils getBoolPref:@"reels_filter_tab_only"];
	if (tabOnly && rygReelsSurfaceIsOpenedChain(listAdapter)) return rygApplyDoomWindow(dataSource, filtered);

	BOOL needsRefilter = NO;
	filtered = rygFilterReelsByEngagement(filtered, tabOnly ? nil : rygEntryMediaPk(dataSource), &needsRefilter);
	if (needsRefilter) rygScheduleReelRefilter(listAdapter);

	return rygApplyDoomWindow(dataSource, filtered);
}

%hook IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {return rygSundialFilterAndLimit(self, %orig, arg1);}
%end

%hook _TtC13IGSundialFeed23IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {return rygSundialFilterAndLimit(self, %orig, arg1);}
%end

// IG 434 renamed the Swift module: IGSundialFeed -> IGSundialFeedDataSource.
%hook _TtC23IGSundialFeedDataSource23IGSundialFeedDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {return rygSundialFilterAndLimit(self, %orig, arg1);}
%end

%hook IGSundialGridVideoViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *list = %orig;
	if (![RYGUtils getBoolPref:@"prevent_doom_scrolling"] || ![RYGUtils getBoolPref:@"doom_limit_pivot_grids"]) return list;

	NSUInteger limit = (NSUInteger)[RYGUtils getDoublePref:@"doom_scrolling_reel_count"];
	if (!limit || list.count <= limit) return list;

	if (!rygGridSourceIsPivot(rygGridFeedSourceName(self))) return list;

	NSUInteger media = 0, cut = list.count;
	for (NSUInteger i = 0; i < list.count; i++) {
		if (!rygMediaPk(list[i])) continue;
		if (++media == limit) { cut = i + 1; break; }
	}

	return [list subarrayWithRange:NSMakeRange(0, cut)];
}
%end

%hook IGContextualFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *list = %orig;
	return rygHideAds(@"feed") ? removeItemsInList(list, NO, YES) : list;
}
%end

%hook IGVideoFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
	RYGProbeOnce(@"hook.hidefeed.videofeedvc", @"IGVideoFeedViewController fired");
	NSArray *list = %orig;
	return rygHideAds(@"feed") ? removeItemsInList(list, NO, YES) : list;
}
%end

%hook IGChainingFeedViewController
- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *list = %orig;
	return rygHideAds(@"feed") ? removeItemsInList(list, NO, YES) : list;
}
%end

%hook IGStoryAdPool
- (id)initWithUserSession:(id)arg1 {
	RYGProbeOnce(@"hook.hideads.storyadpool", @"IGStoryAdPool fired (legacy)");
	return rygHideAds(@"stories") ? nil : %orig;
}
%end

%hook _TtC17IGStoryAdsManager17IGStoryAdsManager
- (id)initWithUserSession:(id)arg1 storyAdsManagerDelegate:(id)arg2 storyViewerLoggingContext:(id)arg3 sectionLoggingContext:(id)arg4 viewController:(id)arg5 storyViewerNavigator:(id)arg6 {
	RYGProbeOnce(@"hook.hideads.adsmanager", @"IGStoryAdsManager fired (current)");
	return rygHideAds(@"stories") ? nil : %orig;
}
%end

%hook IGStoryAdsFetcher
- (id)initWithUserSession:(id)arg1 delegate:(id)arg2 {
	RYGProbeOnce(@"hook.hideads.adsfetcher", @"IGStoryAdsFetcher fired (legacy)");
	return rygHideAds(@"stories") ? nil : %orig;
}
%end

// IG 148.0
%hook IGStoryAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
	return rygHideAds(@"stories") ? nil : %orig;
}

- (id)initWithReelStore:(id)arg1 {
	return rygHideAds(@"stories") ? nil : %orig;
}
%end

%hook IGStoryAdsOptInTextView
- (id)initWithBrandedContentStyledString:(id)arg1 sponsoredPostLabel:(id)arg2 {
	return rygHideAds(@"stories") ? nil : %orig;
}
%end

%hook IGSundialAdsResponseParser
- (id)parsedObjectFromResponse:(id)arg1 {
	return rygHideAds(@"reels") ? nil : %orig;
}

- (id)initWithMediaStore:(id)arg1 userStore:(id)arg2 {
	return rygHideAds(@"reels") ? nil : %orig;
}
%end

// "Sponsored" posts on discover / search
%hook IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *list = %orig;
	return rygHideAds(@"explore") ? removeItemsInList(list, NO, YES) : list;
}
%end

%hook _TtC28IGExploreViewControllerSwift26IGExploreListKitDataSource
- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *list = %orig;
	return rygHideAds(@"explore") ? removeItemsInList(list, NO, YES) : list;
}
%end

// Shopping carousel in reel comments
%hook _TtC35IGCommentThreadCommerceCarouselPill31IGCommentThreadCommerceCarousel
- (id)initWithFrame:(CGRect)frame pillText:(id)text pillStyle:(NSInteger)style {
	return rygHideAds(@"shopping") ? nil : %orig(frame, text, style);
}
%end

// Suggested search / shopping on reels
%hook _TtC27IGShoppableEverythingCommon23IGRapEntrypointResolver
- (id)initWithLauncherSet:(id)arg1 {
	return rygHideAds(@"shopping") ? nil : %orig(arg1);
}
%end

%hook _TtC32IGSundialOrganicCTAContainerView32IGSundialOrganicCTAContainerView
- (void)didMoveToWindow {
	%orig;
	if (self.window && rygHideAds(@"shopping")) [self removeFromSuperview];
}
%end

// "Suggested for you" label at end of feed
%hook IGEndOfFeedDemarcatorCellTopOfFeed
- (void)configureWithViewConfig:(id)arg1 {
	%orig;
	if (![RYGUtils getBoolPref:@"no_suggested_post"]) return;

	UILabel *_titleLabel = MSHookIvar<UILabel *>(self, "_titleLabel");
	if (_titleLabel) _titleLabel.text = @"";
}
%end

%ctor {
	[NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
	                                                object:nil queue:nil
	                                             usingBlock:^(__unused NSNotification *n) { rygFeedPrefsStale = YES; }];

	%init(IGContextualFeedViewController = NSClassFromString(@"_TtC30IGContextualFeedViewController30IGContextualFeedViewController") ?: NSClassFromString(@"IGContextualFeedViewController"),
	      IGChainingFeedViewController = NSClassFromString(@"_TtC18IGPostChainingFeed28IGChainingFeedViewController") ?: NSClassFromString(@"IGChainingFeedViewController"),
	      IGStoryAdsOptInTextView = NSClassFromString(@"_TtC12IGStoryAdsUI23IGStoryAdsOptInTextView") ?: NSClassFromString(@"IGStoryAdsOptInTextView"));
}