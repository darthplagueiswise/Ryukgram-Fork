// ============================================================================
// SCIIGPlusExtraBenefits.x  —  benefits + eligibilities NÃO cobertos pelos
// hooks existentes (SCIIGConsumerSubsHook.x, SCIIGPlusEligibilityHook.x,
// InstaPlusUnlock.xm).
// ============================================================================
// Validado por análise binária (Instagram 4C4C4424, FBSharedFramework 4C4C446A):
//
//   Falta em IGConsumerSubsService (2 benefits BOOL sem argumento):
//     - isStoryViewNotifyBenefitEnabled        @0x1068AC458  B16@0:8
//     - isLinksInMediaBenefitEnabled           @0x107605334  B16@0:8
//
//   Falta em IGSubscriptionAdsIncentiveTextGating (5 CLASS methods, cada um
//   B32@0:8@16@24 — decidem se o TEXTO promocional "assine IG+ pra remover ads"
//   é mostrado em cada superfície):
//     +isEnabledInFeedWithLauncherSet:sponsoredPostInfo:
//     +isEnabledInStoryWithLauncherSet:sponsoredPostInfo:
//     +isEnabledInStoryCaptainWithLauncherSet:sponsoredPostInfo:
//     +isEnabledInReelsWithLauncherSet:sponsoredPostInfo:
//     +isPromoSheetEnabledWithLauncherSet:sponsoredPostInfo:
//
//   Falta em IGConsumerSubsEntrypointOfferProvider (1 BOOL):
//     - isFreeTrialOffer                        @0x109CF2F40  B16@0:8
//
//   Falta em IGConsumerSubsErrorHandling (1 CLASS method):
//     +isSubscriptionExpiredWithError:          @0x109D079D0  B24@0:8@16
//     (forçar NO evita banners de "sua subscription expirou")
//
// Todos são ObjC BOOL simples -> MSHookMessageEx (sideload-safe: swizzle em
// runtime, sem patch em __TEXT). Padrão idêntico ao SCIIGConsumerSubsHook.x:
// on-active install (evita static-init race), gated por pref individual OR o
// mestre 'sci_force_igplus_all', requiresRestart:YES no toggle.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "SCIInternalGatePrefs.h"
#import "SCIInstallOnce.h"

#define XLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusExtra " fmt, ##__VA_ARGS__)

static NSString *const kMaster = @"sci_force_igplus_all";
static inline BOOL EX_ON(NSString *k) {
	return [SCIInternalGatePrefs individualGateEnabledForKey:kMaster]
	    || [SCIInternalGatePrefs individualGateEnabledForKey:k];
}

// --- storage indexed per-hook (aligned arrays)
#define EX_MAX 12
static IMP        gExOrig[EX_MAX];
static SEL        gExSel[EX_MAX];
static NSString  *gExKey[EX_MAX];
static BOOL       gExForceYes[EX_MAX]; // YES = force YES; NO = force NO
static int        gExN = 0;
static NSMutableSet<NSString *> *gExDone;

// --- replacement blocks
static void exHookNoArg(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel || !class_getInstanceMethod(cls, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self) {
		if (EX_ON(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL) = (BOOL (*)(id, SEL))gExOrig[idx];
		return o ? o(self, gExSel[idx]) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(cls, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

// class methods with 2 id args -> B32@0:8@16@24
static void exHookClass2(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel) return;
	Class meta = object_getClass(cls);
	if (!class_getInstanceMethod(meta, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"+%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self, id a, id b) {
		if (EX_ON(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))gExOrig[idx];
		return o ? o(self, gExSel[idx], a, b) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(meta, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

// class method with 1 id arg -> B24@0:8@16
static void exHookClass1(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel) return;
	Class meta = object_getClass(cls);
	if (!class_getInstanceMethod(meta, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"+%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self, id a) {
		if (EX_ON(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL, id) = (BOOL (*)(id, SEL, id))gExOrig[idx];
		return o ? o(self, gExSel[idx], a) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(meta, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

static void exInstall(void) {
	if (!gExDone) gExDone = [NSMutableSet set];

	// (1) IGConsumerSubsService — 2 benefits BOOL sem args faltantes
	Class svc = NSClassFromString(@"IGConsumerSubsService")
	         ?: NSClassFromString(@"_TtC21IGConsumerSubsService21IGConsumerSubsService");
	if (svc) {
		exHookNoArg(svc, @selector(isStoryViewNotifyBenefitEnabled),
		            @"sci_igplus_story_view_notify", YES);
		exHookNoArg(svc, @selector(isLinksInMediaBenefitEnabled),
		            @"sci_igplus_links_in_media", YES);
	} else {
		XLOG("IGConsumerSubsService not loaded yet");
	}

	// (2) IGSubscriptionAdsIncentiveTextGating — 5 class methods de ads-incentive
	// (força YES: mostra o texto promocional; força NO: esconde)
	Class inc = NSClassFromString(@"_TtC35IGSubscriptionAdsIncentiveTextUtils36IGSubscriptionAdsIncentiveTextGating");
	if (inc) {
		BOOL show = YES; // usuario pode preferir NO no futuro; por ora consistencia com "force IGPlus"
		exHookClass2(inc, @selector(isEnabledInFeedWithLauncherSet:sponsoredPostInfo:),
		             @"sci_igplus_ads_incentive_feed", show);
		exHookClass2(inc, @selector(isEnabledInStoryWithLauncherSet:sponsoredPostInfo:),
		             @"sci_igplus_ads_incentive_story", show);
		exHookClass2(inc, @selector(isEnabledInStoryCaptainWithLauncherSet:sponsoredPostInfo:),
		             @"sci_igplus_ads_incentive_story_captain", show);
		exHookClass2(inc, @selector(isEnabledInReelsWithLauncherSet:sponsoredPostInfo:),
		             @"sci_igplus_ads_incentive_reels", show);
		exHookClass2(inc, @selector(isPromoSheetEnabledWithLauncherSet:sponsoredPostInfo:),
		             @"sci_igplus_ads_incentive_promo_sheet", show);
	}

	// (3) IGConsumerSubsEntrypointOfferProvider — isFreeTrialOffer
	Class offer = NSClassFromString(@"_TtC37IGConsumerSubsEntrypointOfferProvider37IGConsumerSubsEntrypointOfferProvider");
	if (offer) {
		exHookNoArg(offer, @selector(isFreeTrialOffer),
		            @"sci_igplus_free_trial_offer", YES);
	}

	// (4) IGConsumerSubsErrorHandling — força NO em "subscription expirou"
	Class err = NSClassFromString(@"_TtC16IGConsumerSubsUI27IGConsumerSubsErrorHandling");
	if (err) {
		exHookClass1(err, @selector(isSubscriptionExpiredWithError:),
		             @"sci_igplus_bypass_expired", NO);
	}
}

%ctor {
	@autoreleasepool {
		if (![SCIInternalGatePrefs individualGateEnabledForKey:kMaster]) return;
		SCIInstallOnceOnActive(^{
			[SCIInternalGatePrefs installCrashGuardIfNeeded];
			exInstall();
		});
	}
}
