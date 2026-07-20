// ============================================================================
// SCIIGPlusExtraBenefits.x — benefits + eligibilities/promo NÃO cobertos pelos
// hooks IGPlus existentes (SCIIGConsumerSubsHook.x, SCIIGPlusEligibilityHook.x,
// InstaPlusUnlock.xm).
// ============================================================================
// Validado por análise binária (Instagram UUID 4C4C4424, FBSharedFramework
// 4C4C446A):
//
//   Falta em IGConsumerSubsService (2 benefits BOOL sem argumento):
//     -isStoryViewNotifyBenefitEnabled           @0x1068AC458  B16@0:8
//     -isLinksInMediaBenefitEnabled              @0x107605334  B16@0:8
//
//   Falta em IGSubscriptionAdsIncentiveTextGating (5 CLASS methods — controlam
//   o TEXTO promocional "assine IG+ pra remover ads" em cada superfície):
//     +isEnabledInFeedWithLauncherSet:sponsoredPostInfo:            @0x105DD3C1C
//     +isEnabledInStoryWithLauncherSet:sponsoredPostInfo:           @0x105DCB860
//     +isEnabledInStoryCaptainWithLauncherSet:sponsoredPostInfo:    @0x105DA4A90
//     +isEnabledInReelsWithLauncherSet:sponsoredPostInfo:           @0x105DCB8D8
//     +isPromoSheetEnabledWithLauncherSet:sponsoredPostInfo:        @0x100903874
//     (assinatura: B32@0:8@16@24)
//
//   Falta em IGConsumerSubsEntrypointOfferProvider:
//     -isFreeTrialOffer                          @0x109CF2F40  B16@0:8
//
//   Falta em IGConsumerSubsErrorHandling:
//     +isSubscriptionExpiredWithError:           @0x109D079D0  B24@0:8@16
//     (forçar NO evita banner "sua subscription expirou")
//
// Todos ObjC BOOL simples -> MSHookMessageEx (sideload-safe: swizzle em runtime,
// sem patch em __TEXT). Padrão idêntico ao SCIIGConsumerSubsHook.x:
// on-active install (evita static-init race). Prefs igt_ip_* consistentes com
// o resto da UI IGPlus.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import "SCIInstallOnce.h"

#define XLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusExtra " fmt, ##__VA_ARGS__)

// Any igt_ip_* on -> install. Individual pref decides each hook's YES/NO.
static inline BOOL EX_PREF(NSString *k) { return [SCIUtils getBoolPref:k]; }

#define EX_MAX 12
static IMP        gExOrig[EX_MAX];
static SEL        gExSel[EX_MAX];
static NSString  *gExKey[EX_MAX];
static BOOL       gExForceYes[EX_MAX];
static int        gExN = 0;
static NSMutableSet<NSString *> *gExDone;

static void exHookNoArg(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel || !class_getInstanceMethod(cls, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self) {
		if (EX_PREF(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL) = (BOOL (*)(id, SEL))gExOrig[idx];
		return o ? o(self, gExSel[idx]) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(cls, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

static void exHookClass2(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel) return;
	Class meta = object_getClass(cls);
	if (!class_getInstanceMethod(meta, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"+%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self, id a, id b) {
		if (EX_PREF(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))gExOrig[idx];
		return o ? o(self, gExSel[idx], a, b) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(meta, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

static void exHookClass1(Class cls, SEL sel, NSString *prefKey, BOOL forceYes) {
	if (gExN >= EX_MAX || !cls || !sel) return;
	Class meta = object_getClass(cls);
	if (!class_getInstanceMethod(meta, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"+%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gExDone containsObject:tag]) return;
	int idx = gExN++;
	gExSel[idx] = sel; gExKey[idx] = prefKey; gExForceYes[idx] = forceYes;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self, id a) {
		if (EX_PREF(gExKey[idx])) return gExForceYes[idx];
		BOOL (*o)(id, SEL, id) = (BOOL (*)(id, SEL, id))gExOrig[idx];
		return o ? o(self, gExSel[idx], a) : (gExForceYes[idx] ? NO : YES);
	});
	IMP orig = NULL; MSHookMessageEx(meta, sel, newImp, &orig); gExOrig[idx] = orig;
	[gExDone addObject:tag];
	XLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

static BOOL exAnyPrefOn(void) {
	static NSString *const keys[] = {
		@"igt_ip_storyviewnotify", @"igt_ip_linksmedia",
		@"igt_ip_ads_incentive_feed", @"igt_ip_ads_incentive_story",
		@"igt_ip_ads_incentive_storycaptain", @"igt_ip_ads_incentive_reels",
		@"igt_ip_ads_incentive_promo",
		@"igt_ip_freetrial", @"igt_ip_bypass_expired",
		nil
	};
	for (int i = 0; keys[i]; i++) if (EX_PREF(keys[i])) return YES;
	return NO;
}

static void exInstall(void) {
	if (!gExDone) gExDone = [NSMutableSet set];

	Class svc = NSClassFromString(@"IGConsumerSubsService")
	         ?: NSClassFromString(@"_TtC21IGConsumerSubsService21IGConsumerSubsService");
	if (svc) {
		exHookNoArg(svc, @selector(isStoryViewNotifyBenefitEnabled),
		            @"igt_ip_storyviewnotify", YES);
		exHookNoArg(svc, @selector(isLinksInMediaBenefitEnabled),
		            @"igt_ip_linksmedia", YES);
	}

	// IGSubscriptionAdsIncentiveTextGating — texto promocional de "sem ads"
	Class inc = NSClassFromString(@"_TtC35IGSubscriptionAdsIncentiveTextUtils36IGSubscriptionAdsIncentiveTextGating");
	if (inc) {
		exHookClass2(inc, @selector(isEnabledInFeedWithLauncherSet:sponsoredPostInfo:),
		             @"igt_ip_ads_incentive_feed", YES);
		exHookClass2(inc, @selector(isEnabledInStoryWithLauncherSet:sponsoredPostInfo:),
		             @"igt_ip_ads_incentive_story", YES);
		exHookClass2(inc, @selector(isEnabledInStoryCaptainWithLauncherSet:sponsoredPostInfo:),
		             @"igt_ip_ads_incentive_storycaptain", YES);
		exHookClass2(inc, @selector(isEnabledInReelsWithLauncherSet:sponsoredPostInfo:),
		             @"igt_ip_ads_incentive_reels", YES);
		exHookClass2(inc, @selector(isPromoSheetEnabledWithLauncherSet:sponsoredPostInfo:),
		             @"igt_ip_ads_incentive_promo", YES);
	}

	Class offer = NSClassFromString(@"_TtC37IGConsumerSubsEntrypointOfferProvider37IGConsumerSubsEntrypointOfferProvider");
	if (offer) {
		exHookNoArg(offer, @selector(isFreeTrialOffer), @"igt_ip_freetrial", YES);
	}

	Class err = NSClassFromString(@"_TtC16IGConsumerSubsUI27IGConsumerSubsErrorHandling");
	if (err) {
		// FORÇA NO -> bypass do banner "sua subscription expirou"
		exHookClass1(err, @selector(isSubscriptionExpiredWithError:),
		             @"igt_ip_bypass_expired", NO);
	}
}

%ctor {
	@autoreleasepool {
		if (!exAnyPrefOn()) return;
		SCIInstallOnceOnActive(^{
			[SCIInternalGatePrefs installCrashGuardIfNeeded];
			exInstall();
		});
	}
}
