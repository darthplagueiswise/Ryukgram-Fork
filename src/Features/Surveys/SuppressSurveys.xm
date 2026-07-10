// Suppress in-app surveys / feedback prompts by neutering each subsystem's
// "try to show" entry, so nothing is ever built. Gated on suppress_surveys.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static void sci_survey_noop_void(id self, SEL _cmd) {}
static BOOL sci_survey_noop_bool(id self, SEL _cmd) { return NO; }

static char sciSurveyReturnType(Method m) {
	const char *t = method_getTypeEncoding(m);
	if (!t) return 0;
	while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V') t++;
	return *t;
}

static NSMutableSet *sciSurveyHooked(void) {
	static NSMutableSet *s = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ s = [NSMutableSet new]; });
	return s;
}

static void sciSuppress(NSString *className, NSString *selName) {
	Class cls = NSClassFromString(className);
	if (!cls) return;
	SEL sel = NSSelectorFromString(selName);
	Method m = class_getInstanceMethod(cls, sel);
	if (!m) return;
	NSString *key = [NSString stringWithFormat:@"%@|%@", className, selName];
	if ([sciSurveyHooked() containsObject:key]) return;
	char ret = sciSurveyReturnType(m);
	IMP replacement = (ret == 'v') ? (IMP)sci_survey_noop_void
				   : (ret == 'B' || ret == 'c') ? (IMP)sci_survey_noop_bool : NULL;
	if (!replacement) return;
	[sciSurveyHooked() addObject:key];
	IMP orig = NULL;
	MSHookMessageEx(cls, sel, replacement, &orig);
}

static void sciSuppressAll(NSString *className, NSArray<NSString *> *sels) {
	for (NSString *s in sels) sciSuppress(className, s);
}

static void sciInstallSurveySuppression(void) {
	sciSuppressAll(@"_TtC13IGSurveySwift21IGSurveyManager_swift", @[
		@"showSurveyWhenAppropriateWithInfo:", @"showBrandSurveyWithInfo:", @"showPendingSurvey" ]);
	sciSuppressAll(@"_TtC13IGSurveySwift32IGFeedSharingSurveyManager_swift", @[
		@"tryToShowFundraiserHalfCancelSurvey", @"tryToShowFundraiserFullCancelSurvey",
		@"tryToShowFundraiserSuccessSurvey", @"tryToShowCarouselCreationAbandonmentSurvey",
		@"tryToShowSingleMediaCreationSurvey",
		@"tryToShowOrganicCarouselSwipeSurveyForMediaAccess:sponsoredInfoProvider:fromPageIndex:" ]);
	sciSuppress(@"_TtC15IGGenericSearch33IGSearchSatisfactionSurveyManager", @"markReturnToSearchAndTriggerSurveyIfNecessary");
	sciSuppress(@"_TtC21IGSearchSurveyManager21IGSearchSurveyManager", @"tryToShowSurvey");
	sciSuppress(@"_TtC28IGExploreViewControllerSwift27IGExploreSurveyManagerSwift", @"tryToShowSurveyAndEndSession");
	sciSuppress(@"_TtC20IGSundialAdsMultiAds37IGSundialAdsMultiAdsSectionController", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	sciSuppress(@"_TtC24IGIntentAwareAdsSwiftNew51IGIntentAwareAdsPivotCarouselSectionControllerSwift", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	sciSuppress(@"_TtC21IGStoryItemContextAds35IGStoryAdsRapidFeedbackSurveyHelper", @"canShowMultiAdsSentimentSurveyFor:previousStoryController:didShowStoriesSurvey:");
	sciSuppress(@"_TtC32IGDirectInboxViewControllerSwift33IGDirectInboxLifecycleCoordinator", @"showNavigationSurvey");
	sciSuppress(@"_TtC39IGDirectThreadViewODNCFeatureController39IGDirectThreadViewODNCFeatureController", @"showODNCSurveyIfNeeded");
	sciSuppress(@"_TtC32IGFeedAdsPostAdEngagementHandler32IGFeedAdsPostAdEngagementHandler", @"showAdsFeedbackInterfaceWithTriggerType:");
	sciSuppressAll(@"_TtC26IGSundialViewerVideoSurvey43IGSundialViewerVideoSurveySectionController", @[
		@"startSurvey", @"startSurveyWith:" ]);

	sciSuppress(@"IGSundialViewerVideoSectionController", @"tryToShowSurveyWithIntegrationPointID:contextData:");
	sciSuppressAll(@"IGRapidFeedbackController", @[ @"tryToShowSurvey", @"presentSurvey" ]);
	sciSuppress(@"IGVideoCallSimpleStateProviderCallEndedModel", @"showEndCallFeedback");
	sciSuppressAll(@"PXForYouSettings", @[ @"showSurveyQuestions", @"showSurveyQuestionsWithProfile" ]);
	sciSuppress(@"FBKLaunchAction", @"launchesSurvey");
	sciSuppress(@"IGIntentAwareAdsPivotCarouselSectionController", @"showSurveyOnUnitExitForAdItemIndex:triggerType:");
	sciSuppress(@"IGStoryArchiveViewController", @"_tryToShowSurveyWithIntegrationPoint:");
	sciSuppress(@"IGMainFeedViewController_objc", @"_showMultiAccountSurveyIfNecessary");
	sciSuppress(@"IGProfileAndBrowseViewController", @"tryToShowBlockSurvey");
	sciSuppress(@"IGProfileViewController", @"tryToShowBlockSurvey");
	sciSuppressAll(@"IGSearchSerpGridViewController", @[
		@"tryToShowMetaAIHCMSurvey", @"_startShopEverythingSurveyDwellTimer", @"_canShowSurvey" ]);
	sciSuppressAll(@"IGSearchNewSerpGridViewController", @[
		@"tryToShowMetaAIHCMSurvey", @"_startShopEverythingSurveyDwellTimer", @"_canShowSurvey" ]);
	sciSuppress(@"IGSundialFeedViewController", @"_showCTABarriersSurveyIfNeeded");
	sciSuppress(@"IGTabBarController", @"_tryToShowSelfProfileBounceSurvey");
}

%ctor {
	if (![SCIUtils getBoolPref:@"suppress_surveys"]) return;
	sciInstallSurveySuppression();
	[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
													  object:nil queue:[NSOperationQueue mainQueue]
												  usingBlock:^(NSNotification *n) { sciInstallSurveySuppression(); }];
}
