#import <Foundation/Foundation.h>
#import <substrate.h>
#import "../../Utils.h"

static NSInteger const IGHomeFeedPickerMenuItemForYou = 0;
static NSInteger const IGHomeFeedPickerMenuItemFollowing = 5;

static BOOL rygFollowingFeedEnabled(void) {
    return [[RYGUtils getStringPref:@"main_feed_mode"] isEqualToString:@"following"];
}

%hook _TtC16IGHomeFeedPicker30IGHomeFeedPickerMenuController
- (id)initWithUserSession:(id)userSession menuItems:(NSArray *)menuItems homeFeedViewModel:(id)homeViewModel analyticsModule:(id)analyticsModule navigationController:(id)navigationController isForYouContentLaneEnabled:(BOOL)forYouEnabled {
    if (!rygFollowingFeedEnabled())
        return %orig;

    NSMutableArray *items = menuItems.mutableCopy;
    [items removeObject:@(IGHomeFeedPickerMenuItemFollowing)];
    [items removeObject:@(IGHomeFeedPickerMenuItemForYou)];
    [items insertObject:@(IGHomeFeedPickerMenuItemFollowing) atIndex:0];
    return %orig(userSession, items, homeViewModel, analyticsModule, navigationController, YES);
}
%end

%hook _TtC14IGHomeMainFeed28IGHomeMainFeedViewController
- (void)viewWillAppear:(BOOL)animated {
    if (rygFollowingFeedEnabled())
        MSHookIvar<id>(self, "currentFeedMenuItem") = @(IGHomeFeedPickerMenuItemFollowing);
    %orig;
}
%end

%hook _TtC16IGHomeFeedHeader20IGHomeFeedHeaderView
- (void)setTitle:(id)title animated:(BOOL)animated {
    if (rygFollowingFeedEnabled() && [title isEqual:@"For you"])
        %orig(RYGLocalized(@"Following"), animated);
    else
        %orig;
}
%end

%hook _TtC11IGDSAShared18IGDSAGatingManager
- (NSInteger)feedStickyContentLaneSelection {
    if (rygFollowingFeedEnabled())
        return 1;
    return %orig;
}
%end

%hook IGMainFeedViewModel
- (id)initWithDeps:(id)deps posts:(id)posts nextMaxID:(id)nextMaxID initialPaginationSource:(NSString *)paginationSource contentCoordinator:(id)coordinator dataSourceSupplementaryItemsProvider:(id)supplementaryProvider disableAutomaticRefresh:(BOOL)disableRefresh disableSerialization:(BOOL)disableSerialization sessionId:(id)sessionId analyticsModule:(id)analyticsModule disableFlashFeedTLI:(BOOL)disableFlashFeedTLI disableFlashFeedOnColdStart:(BOOL)disableColdStart disableResponseDeferral:(BOOL)disableResponseDeferral hidesStoriesTray:(BOOL)hidesStoriesTray shouldRegisterAsStoryDataListener:(BOOL)shouldRegisterAsStoryDataListener isSecondaryFeed:(BOOL)isSecondaryFeed collectionViewBackgroundColorOverride:(id)backgroundColor minWarmStartFetchInterval:(double)minWarmStart peakMinWarmStartFetchInterval:(double)peakMinWarmStart minimumWarmStartBackgroundedInterval:(double)backgroundedMinWarmStart peakMinimumWarmStartBackgroundedInterval:(double)peakBackgroundedMinWarmStart supplementalFeedHoistedMediaID:(id)hoistedMediaId headerTitleOverride:(id)headerTitle isInFollowingTab:(BOOL)isInFollowingTab useShimmerLoadingWhenNoStoriesTray:(BOOL)useShimmer mainFeedDataFetcher:(id)dataFetcher {
    if (rygFollowingFeedEnabled()) {
        paginationSource = @"following";
        isInFollowingTab = YES;
    }
    return %orig;
}
%end

%hook IGMainFeedNetworkSource
- (id)initWithPosts:(id)posts nextMaxID:(id)nextMaxID initialPaginationSource:(NSString *)paginationSource fetchPath:(id)fetchPath responseParser:(id)responseParser mainFeedNetworkSourceSessionDeps:(id)deps sessionTracker:(id)sessionTracker analyticsModule:(id)analyticsModule useNewUIGraph:(BOOL)useNewGraph {
    if (rygFollowingFeedEnabled())
        paginationSource = @"following";
    return %orig;
}
- (void)updatePaginationSource:(id)paginationSource nextMaxID:(id)nextMaxID {
    if (rygFollowingFeedEnabled())
        paginationSource = @"following";
    %orig;
}
%end

%hook _TtC24IGMainFeedDataFetcherKit30IGMainFeedRequestConfigFactory
- (id)generateHeadLoadRequestConfigWithReason:(NSInteger)reason trackingWith:(id)tracking cancelOngoingFetch:(BOOL)cancel hoistedMediaID:(id)hoistedMediaID hoistedMediaShortcode:(id)shortcode deeplinkURL:(id)deeplinkURL isNonFeedSurface:(BOOL)isNonFeedSurface additionalParams:(id)params prewarmConfig:(id)prewarmConfig containerModule:(id)containerModule paginationSource:(id)paginationSource secondaryFeedFilter:(id)secondaryFeedFilter vpvdSeenIds:(id)seenIds {
    if (rygFollowingFeedEnabled() && [paginationSource isEqual:@"following"])
        reason = 3;
    return %orig;
}
%end
