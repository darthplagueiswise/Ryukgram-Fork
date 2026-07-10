// Force Instagram Plus subscriber benefits on. IGConsumerSubsService exposes
// each benefit as -is<Name>BenefitEnabled; peek features add a second
// *Eligibility gate. Resolve classes by their mangled Swift name, not a runtime
// scan: the process registers duplicate classes and a scan can bind a copy IG
// never messages. Server-fetched content (peek, themes) reveals but may be empty.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

typedef struct { const char *pref; const char *sel; } SCIBenefit;

static const SCIBenefit kBenefits[] = {
	{"igt_ip_appicon",         "isCustomAppIconBenefitEnabled"},
	{"igt_ip_storyfonts",      "isStoryFontsBenefitEnabled"},
	{"igt_ip_chatfonts",       "isChatFontsBenefitEnabled"},
	{"igt_ip_biofont",         "isCustomBioFontInProfileBenefitEnabled"},
	{"igt_ip_customlists",     "isCustomListsBenefitEnabled"},
	{"igt_ip_storypeek",       "isStoryPeeksBenefitEnabled"},
	{"igt_ip_dmpeek",          "isDirectMessagePeekBenefitEnabled"},
	{"igt_ip_brandedthreads",  "isBrandedThreadsBenefitEnabled"},
	{"igt_ip_timestampviewers","isTimestampViewersListBenefitEnabled"},
	{"igt_ip_searchviewers",   "isSearchStoryViewersBenefitEnabled"},
	{"igt_ip_storyspotlight",  "isStorySpotlightBenefitEnabled"},
	{"igt_ip_superlikes",      "isStorySuperlikesBenefitEnabled"},
	{"igt_ip_storyrewatch",    "isStoryRewatchBenefitEnabled"},
	{"igt_ip_storyextend",     "isStoryExtendBenefitEnabled"},
	{"igt_ip_pinnedposts",     "isPinnedPostsIncreasedLimitEnabled"},
	{"igt_ip_silentprofile",   "isSilentPostToProfileBenefitEnabled"},
	{"igt_ip_silenthighlights","isSilentPostToHighlightsBenefitEnabled"},
};
static const size_t kBenefitCount = sizeof(kBenefits) / sizeof(kBenefits[0]);

static BOOL (*orig_bool[kBenefitCount])(id, SEL);
#define BENEFIT_STUB(i) static BOOL new_bool_##i(id self, SEL _cmd) { return YES; }
BENEFIT_STUB(0)  BENEFIT_STUB(1)  BENEFIT_STUB(2)  BENEFIT_STUB(3)  BENEFIT_STUB(4)
BENEFIT_STUB(5)  BENEFIT_STUB(6)  BENEFIT_STUB(7)  BENEFIT_STUB(8)  BENEFIT_STUB(9)
BENEFIT_STUB(10) BENEFIT_STUB(11) BENEFIT_STUB(12) BENEFIT_STUB(13) BENEFIT_STUB(14)
BENEFIT_STUB(15) BENEFIT_STUB(16)
static const IMP kBenefitIMP[kBenefitCount] = {
	(IMP)new_bool_0,  (IMP)new_bool_1,  (IMP)new_bool_2,  (IMP)new_bool_3,  (IMP)new_bool_4,
	(IMP)new_bool_5,  (IMP)new_bool_6,  (IMP)new_bool_7,  (IMP)new_bool_8,  (IMP)new_bool_9,
	(IMP)new_bool_10, (IMP)new_bool_11, (IMP)new_bool_12, (IMP)new_bool_13, (IMP)new_bool_14,
	(IMP)new_bool_15, (IMP)new_bool_16,
};

static BOOL ret_yes(id self, SEL _cmd) { return YES; }
static BOOL ret_no(id self, SEL _cmd)  { return NO; }

static void hook(Class cls, const char *sel, IMP imp, IMP *out) {
	SEL s = sel_registerName(sel);
	if (class_getInstanceMethod(cls, s)) MSHookMessageEx(cls, s, imp, out);
}

// Resolve a Swift class by mangled-then-bare name, hook its instance or class method.
static void hookNamed(const char *mangled, const char *bare, const char *sel, IMP imp) {
	Class cls = objc_getClass(mangled) ?: objc_getClass(bare);
	if (!cls) return;
	SEL s = sel_registerName(sel);
	static IMP sink;
	if (class_getInstanceMethod(cls, s)) { MSHookMessageEx(cls, s, imp, &sink); return; }
	Class meta = object_getClass(cls);
	if (class_getInstanceMethod(meta, s)) MSHookMessageEx(meta, s, imp, &sink);
}

%ctor {
	BOOL anyBenefit = NO;
	for (size_t i = 0; i < kBenefitCount; i++) {
		if ([SCIUtils getBoolPref:@(kBenefits[i].pref)]) { anyBenefit = YES; break; }
	}
	if (!anyBenefit) return;

	Class cls = objc_getClass("_TtC21IGConsumerSubsService21IGConsumerSubsService")
	         ?: NSClassFromString(@"IGConsumerSubsService");
	if (!cls) return;

	for (size_t i = 0; i < kBenefitCount; i++) {
		if ([SCIUtils getBoolPref:@(kBenefits[i].pref)]) hook(cls, kBenefits[i].sel, kBenefitIMP[i], (IMP *)&orig_bool[i]);
	}

	if ([SCIUtils getBoolPref:@"igt_ip_appicon"]) {
		hookNamed("_TtC27IGConsumerSubsCustomAppIcon33IGConsumerSubsCustomAppIconHelper",
		          "IGConsumerSubsCustomAppIconHelper", "isCustomAppIconAvailableWithUserSession:", (IMP)ret_yes);
	}

	if ([SCIUtils getBoolPref:@"igt_ip_storypeek"]) {
		const char *m = "_TtC34IGConsumerSubsStoryPeekEligibility34IGConsumerSubsStoryPeekEligibility";
		const char *b = "IGConsumerSubsStoryPeekEligibility";
		hookNamed(m, b, "isPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:",       (IMP)ret_yes);
		hookNamed(m, b, "isAnyPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:",    (IMP)ret_yes);
		hookNamed(m, b, "isUpsellPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", (IMP)ret_no);
	}

	if ([SCIUtils getBoolPref:@"igt_ip_dmpeek"]) {
		const char *m = "_TtC29IGConsumerSubsDirectChatPeeks39IGConsumerSubsDirectChatPeekEligibility";
		const char *b = "IGConsumerSubsDirectChatPeekEligibility";
		hookNamed(m, b, "isPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:",       (IMP)ret_yes);
		hookNamed(m, b, "isAnyPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:",    (IMP)ret_yes);
		hookNamed(m, b, "isUpsellPeekEligibleForEntryPoint:viewModelType:consumerSubsService:launcherSet:", (IMP)ret_no);
		hookNamed(m, b, "isChatPeekFeatureEligibleWithLauncherSet:consumerSubsService:", (IMP)ret_yes);
		hookNamed(m, b, "_isChatPeekEligibleForThreadId:", (IMP)ret_yes);
	}
}
