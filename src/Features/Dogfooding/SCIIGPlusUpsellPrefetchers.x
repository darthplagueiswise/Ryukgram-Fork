// ============================================================================
// SCIIGPlusUpsellPrefetchers.x — silencia os prefetchers de UPSELL do IGPlus.
// ============================================================================
// Validado no binário: _TtC29IGConsumerSubsBloksPrefetcher29IGConsumerSubsBloksPrefetcher
// tem ~15 métodos *UpsellPrefetchWithUserSession: que fazem prefetch de
// carrosséis de "assine o IG+ pra desbloquear X" (Bloks-driven). Cada um recebe
// (userSession) ou (userSession, entrypoint) e retorna void.
//
// Não força YES/NO — apenas SKIP (retorna void sem fazer nada). Isso reduz
// spam de upsell/latência de rede quando o usuário força os benefits mesmo
// sem subscription real. Cada superfície tem seu próprio pref igt_ip_up_*.
//
// Bonus: 3 métodos BOOL que abrem tela de upsell (openXxxUpsellDestinationScreen)
// — forçar NO evita navegação para a tela de compra.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <os/log.h>
#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import "SCIInstallOnce.h"

#define UPLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] IGPlusUp " fmt, ##__VA_ARGS__)

static inline BOOL UP_ON(NSString *k) { return [SCIUtils getBoolPref:k]; }

#define UP_MAX 24
static IMP        gUpOrig[UP_MAX];
static SEL        gUpSel[UP_MAX];
static NSString  *gUpKey[UP_MAX];
static int        gUpN = 0;
static NSMutableSet<NSString *> *gUpDone;

// void method (id userSession) or (id userSession, id entrypoint) — no-op se pref ON
static void upHookVoid1(Class cls, SEL sel, NSString *k) {
	if (gUpN >= UP_MAX || !cls || !sel || !class_getInstanceMethod(cls, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gUpDone containsObject:tag]) return;
	int idx = gUpN++;
	gUpSel[idx] = sel; gUpKey[idx] = k;
	IMP newImp = imp_implementationWithBlock(^void(id self, id a) {
		if (UP_ON(gUpKey[idx])) return; // no-op
		void (*o)(id, SEL, id) = (void (*)(id, SEL, id))gUpOrig[idx];
		if (o) o(self, gUpSel[idx], a);
	});
	IMP orig = NULL; MSHookMessageEx(cls, sel, newImp, &orig); gUpOrig[idx] = orig;
	[gUpDone addObject:tag];
	UPLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}
static void upHookVoid2(Class cls, SEL sel, NSString *k) {
	if (gUpN >= UP_MAX || !cls || !sel || !class_getInstanceMethod(cls, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gUpDone containsObject:tag]) return;
	int idx = gUpN++;
	gUpSel[idx] = sel; gUpKey[idx] = k;
	IMP newImp = imp_implementationWithBlock(^void(id self, id a, id b) {
		if (UP_ON(gUpKey[idx])) return; // no-op
		void (*o)(id, SEL, id, id) = (void (*)(id, SEL, id, id))gUpOrig[idx];
		if (o) o(self, gUpSel[idx], a, b);
	});
	IMP orig = NULL; MSHookMessageEx(cls, sel, newImp, &orig); gUpOrig[idx] = orig;
	[gUpDone addObject:tag];
	UPLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}
// BOOL (id, id) — force NO (bloqueia navegar para tela de compra)
static void upHookBoolFalse2(Class cls, SEL sel, NSString *k) {
	if (gUpN >= UP_MAX || !cls || !sel || !class_getInstanceMethod(cls, sel)) return;
	NSString *tag = [NSString stringWithFormat:@"%s#%s", class_getName(cls), sel_getName(sel)];
	if ([gUpDone containsObject:tag]) return;
	int idx = gUpN++;
	gUpSel[idx] = sel; gUpKey[idx] = k;
	IMP newImp = imp_implementationWithBlock(^BOOL(id self, id a, id b) {
		if (UP_ON(gUpKey[idx])) return NO;
		BOOL (*o)(id, SEL, id, id) = (BOOL (*)(id, SEL, id, id))gUpOrig[idx];
		return o ? o(self, gUpSel[idx], a, b) : NO;
	});
	IMP orig = NULL; MSHookMessageEx(cls, sel, newImp, &orig); gUpOrig[idx] = orig;
	[gUpDone addObject:tag];
	UPLOG("%{public}@: %{public}s", tag, orig ? "HOOKED" : "FAILED");
}

static BOOL upAnyPrefOn(void) {
	static NSString *const keys[] = {
		@"igt_ip_up_prefetch", @"igt_ip_up_block_dest", nil
	};
	for (int i = 0; keys[i]; i++) if (UP_ON(keys[i])) return YES;
	return NO;
}

static void upInstall(void) {
	if (!gUpDone) gUpDone = [NSMutableSet set];
	Class pf = NSClassFromString(@"_TtC29IGConsumerSubsBloksPrefetcher29IGConsumerSubsBloksPrefetcher");
	if (!pf) { UPLOG("BloksPrefetcher not loaded"); return; }

	NSString *keyP = @"igt_ip_up_prefetch";
	NSString *keyD = @"igt_ip_up_block_dest";

	// 1-arg void prefetchers (userSession)
	SEL v1[] = {
		@selector(superlikeUpsellPrefetchWithUserSession:),
		@selector(viewerListUpsellPrefetchWithUserSession:),
		@selector(customListsReceiverUpsellPrefetchWithUserSession:),
		@selector(customListsInlineUpsellPrefetchWithUserSession:),
		@selector(silentPostToProfileUpsellPrefetchWithUserSession:),
		@selector(customAppIconUpsellPrefetchWithUserSession:),
		@selector(storyFontsUpsellPrefetchWithUserSession:),
		@selector(chatFontsUpsellPrefetchWithUserSession:),
		@selector(directMessagePeekUpsellPrefetchWithUserSession:),
		@selector(storyViewNotifyComposerUpsellPrefetchWithUserSession:),
		@selector(storyViewNotifyOverflowMenuUpsellPrefetchWithUserSession:),
	};
	for (size_t i = 0; i < sizeof(v1)/sizeof(v1[0]); i++) upHookVoid1(pf, v1[i], keyP);

	// 2-arg void prefetchers (userSession, entrypoint)
	SEL v2[] = {
		@selector(storyPeekContextMenuUpsellPrefetchWithUserSession:entrypoint:),
		@selector(customBioFontUpsellPrefetchWithUserSession:entrypoint:),
		@selector(pinLimitIncreaseUpsellPrefetchWithUserSession:entrypoint:),
		@selector(linksInMediaUpsellPrefetchWithUserSession:entrypoint:),
		@selector(prefetchQuotaCommsBannerWithUserSession:entrypoint:),
	};
	for (size_t i = 0; i < sizeof(v2)/sizeof(v2[0]); i++) upHookVoid2(pf, v2[i], keyP);

	// BOOL destination-screen openers -> force NO (não abre tela de compra)
	SEL b2[] = {
		@selector(openLinksInMediaUpsellDestinationScreenWithUserSession:entrypoint:),
		@selector(openConsumerSubsUpsellDestinationScreenWithUserSession:entrypoint:),
		@selector(openQuotaCommsBannerWithUserSession:entrypoint:),
	};
	for (size_t i = 0; i < sizeof(b2)/sizeof(b2[0]); i++) upHookBoolFalse2(pf, b2[i], keyD);
}

%ctor {
	@autoreleasepool {
		if (!upAnyPrefOn()) return;
		SCIInstallOnceOnActive(^{
			[SCIInternalGatePrefs installCrashGuardIfNeeded];
			upInstall();
		});
	}
}
