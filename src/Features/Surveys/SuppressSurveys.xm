// Neuter every in-app survey / feedback prompt entry point. Gated on suppress_surveys.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static void ryg_survey_noop_void(id self, SEL _cmd) {}
static BOOL ryg_survey_noop_bool(id self, SEL _cmd) { return NO; }

static char rygSurveyReturnType(Method m) {
	const char *t = method_getTypeEncoding(m);
	if (!t) return 0;
	while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V') t++;
	return *t;
}

static NSMutableSet *rygSurveyHooked(void) {
	static NSMutableSet *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static void rygSuppress(NSString *className, NSString *selName) {
	Class cls = NSClassFromString(className);
	if (!cls) return;
	SEL sel = NSSelectorFromString(selName);
	Method m = class_getInstanceMethod(cls, sel);
	if (!m) return;
	NSString *key = [NSString stringWithFormat:@"%@|%@", className, selName];
	if ([rygSurveyHooked() containsObject:key]) return;
	char ret = rygSurveyReturnType(m);
	IMP replacement = (ret == 'v') ? (IMP)ryg_survey_noop_void
				   : (ret == 'B' || ret == 'c') ? (IMP)ryg_survey_noop_bool : NULL;
	if (!replacement) return;
	[rygSurveyHooked() addObject:key];
	IMP orig = NULL;
	MSHookMessageEx(cls, sel, replacement, &orig);
}

static void rygSuppressAll(NSString *className, NSArray<NSString *> *sels) {
	for (NSString *s in sels) rygSuppress(className, s);
}

static BOOL ryg_wyt_should_display(id self, SEL _cmd) { return NO; }
static CGSize ryg_wyt_zero_size(id self, SEL _cmd, CGFloat width) { return CGSizeZero; }

static void rygHookWYT(NSString *className, NSString *selName, IMP replacement) {
	Class cls = NSClassFromString(className);
	if (!cls) return;
	SEL sel = NSSelectorFromString(selName);
	if (!class_getInstanceMethod(cls, sel)) return;
	NSString *key = [NSString stringWithFormat:@"%@|%@", className, selName];
	if ([rygSurveyHooked() containsObject:key]) return;
	[rygSurveyHooked() addObject:key];
	IMP orig = NULL;
	MSHookMessageEx(cls, sel, replacement, &orig);
}

static void rygInstallWYTKill(void) {
	rygHookWYT(@"_TtC32IGFeedItemWYTSurveyCellViewModel32IGFeedItemWYTSurveyCellViewModel",
			   @"shouldDisplayWYTSurvey", (IMP)ryg_wyt_should_display);
	rygHookWYT(@"_TtC23IGFeedItemWYTSurveyCell33IGFeedItemWYTSurveyCellController",
			   @"sizeForWidth:", (IMP)ryg_wyt_zero_size);
}

static void rygInstallSurveySuppression(void) {
	rygInstallWYTKill();
	rygSuppressAll(@"_TtC13IGSurveySwift21IGSurveyManager_swift", @[
		@"showSurveyWhenAppropriateWithInfo:", @"showBrandSurveyWithInfo:", @"showPendingSurvey" ]);
	rygSuppressAll(@"_TtC13IGSurveySwift32IGFeedSharingSurveyManager_swift", @[
		@"tryToShowFundraiserHalfCancelSurvey", @"tryToShowFundraiserFullCancelSurvey",
		@"tryToShowFundraiserSuccessSurvey", @"tryToShowCarouselCreationAbandonmentSurvey",
		@"tryToShowSingleMediaCreationSurvey",
		@"tryToShowOrganicCarouselSwipeSurveyForMediaAccess:sponsoredInfoProvider:fromPageIndex:" ]);
	rygSuppress(@"_TtC15IGGenericSearch33IGSearchSatisfactionSurveyManager", @"markReturnToSearchAndTriggerSurveyIfNecessary");
	rygSuppress(@"_TtC21IGSearchSurveyManager21IGSearchSurveyManager", @"tryToShowSurvey");
	rygSuppress(@"_TtC28IGExploreViewControllerSwift27IGExploreSurveyManagerSwift", @"tryToShowSurveyAndEndSession");
	rygSuppress(@"_TtC20IGSundialAdsMultiAds37IGSundialAdsMultiAdsSectionController", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	rygSuppress(@"_TtC24IGIntentAwareAdsSwiftNew51IGIntentAwareAdsPivotCarouselSectionControllerSwift", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	rygSuppress(@"_TtC21IGStoryItemContextAds35IGStoryAdsRapidFeedbackSurveyHelper", @"canShowMultiAdsSentimentSurveyFor:previousStoryController:didShowStoriesSurvey:");
	rygSuppress(@"_TtC32IGDirectInboxViewControllerSwift33IGDirectInboxLifecycleCoordinator", @"showNavigationSurvey");
	rygSuppress(@"_TtC39IGDirectThreadViewODNCFeatureController39IGDirectThreadViewODNCFeatureController", @"showODNCSurveyIfNeeded");
	rygSuppress(@"_TtC32IGFeedAdsPostAdEngagementHandler32IGFeedAdsPostAdEngagementHandler", @"showAdsFeedbackInterfaceWithTriggerType:");
	rygSuppressAll(@"_TtC26IGSundialViewerVideoSurvey43IGSundialViewerVideoSurveySectionController", @[
		@"startSurvey", @"startSurveyWith:" ]);

	rygSuppress(@"IGSundialViewerVideoSectionController", @"tryToShowSurveyWithIntegrationPointID:contextData:");
	rygSuppressAll(@"IGRapidFeedbackController", @[ @"tryToShowSurvey", @"presentSurvey" ]);
	rygSuppress(@"IGVideoCallSimpleStateProviderCallEndedModel", @"showEndCallFeedback");
	rygSuppressAll(@"PXForYouSettings", @[ @"showSurveyQuestions", @"showSurveyQuestionsWithProfile" ]);
	rygSuppress(@"FBKLaunchAction", @"launchesSurvey");
	rygSuppress(@"IGIntentAwareAdsPivotCarouselSectionController", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	rygSuppress(@"IGStoryArchiveViewController", @"_tryToShowSurveyWithIntegrationPoint:");
	rygSuppress(@"IGMainFeedViewController_objc", @"_showMultiAccountSurveyIfNecessary");
	rygSuppress(@"IGProfileAndBrowseViewController", @"tryToShowBlockSurvey");
	rygSuppress(@"IGProfileViewController", @"tryToShowBlockSurvey");
	rygSuppressAll(@"IGSearchSerpGridViewController", @[
		@"tryToShowMetaAIHCMSurvey", @"_startShopEverythingSurveyDwellTimer", @"_canShowSurvey" ]);
	rygSuppressAll(@"IGSearchNewSerpGridViewController", @[
		@"tryToShowMetaAIHCMSurvey", @"_startShopEverythingSurveyDwellTimer", @"_canShowSurvey" ]);
	rygSuppress(@"IGSundialFeedViewController", @"_showCTABarriersSurveyIfNeeded");
	rygSuppress(@"IGTabBarController", @"_tryToShowSelfProfileBounceSurvey");
}

%ctor {
	if (![RYGUtils getBoolPref:@"suppress_surveys"]) return;
	rygInstallSurveySuppression();
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
													  object:nil queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *n) { rygInstallSurveySuppression(); }];
}
