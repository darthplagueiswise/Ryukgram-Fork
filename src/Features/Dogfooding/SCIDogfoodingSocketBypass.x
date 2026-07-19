// SCIDogfoodingSocketBypass.x
// =====================================================================
// Bypass do socket-nil do Dogfooding Assistant: quando o usuário toca a row
// "Dogfooding Assistant" no menu de bug report, constrói e apresenta o
// IGSundialYourAlgoDogfoodingAssistantViewController diretamente.
// =====================================================================
// Base binária (LIEF + Capstone; Instagram UUID 4C4C4424..., FBSharedFramework
// 4C4C446A...):
//
//   O tap da row é dispatchado por ObjC:
//     -[IGBugReportMenuViewController bugReportingActionCellButtonTapped:]
//     @0x1084C3A94   types="v24@0:8@16"   (void, self, _cmd, id row)
//
//   O caminho nativo desse tap para case 6 (Dogfooding) invoca o lazy
//   `$__lazy_storage_$_dogfoodingAssistantSocket` (ivar +0x85) via witness-table
//   (blr x8 em 0x104AAF9C8 no didSelectRow case 6). Se o socket é nil (usuário
//   não-employee), não faz nada — por isso a row aparece mas não abre.
//
//   O DESTINO real é IGSundialYourAlgoDogfoodingAssistantViewController
//   (metadata 0x10FBCABC0), construível via ObjC ABI:
//     -initWithAnalyticsModule:   @0x106DEC6AC   types="@24@0:8@16"
//     -initWithAnalyticsModule:performanceListener:  @0x10746CB04
//
// ESTRATÉGIA: hookar o dispatcher ObjC do tap (MSHookMessageEx, sideload-safe:
// swizzle em runtime, sem patch em __TEXT, sem crash de code-signing). Se a row
// é "Dogfooding Assistant" (title/subtitle), constrói o VC direto e apresenta —
// bypass total do socket nil. Toggle-controlled; se off, cai em %orig.

#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "SCIInternalGatePrefs.h"
#import "../../SCIFileLog.h"

static BOOL sBypassActive = NO;
static BOOL (*orig_tap)(id, SEL, id) = NULL;

// Extrai um texto identificador da row (title / subtitle / description) — a row
// é um objeto opaco (model do Bloks/SwiftUI), então tentamos seletores comuns.
static NSString *sci_rowTitle(id row) {
	if (!row) return nil;
	SEL sels[] = { @selector(title), @selector(text), @selector(rowTitle),
	               @selector(displayText), @selector(name), @selector(label),
	               @selector(actionTitle) };
	for (int i = 0; i < (int)(sizeof(sels)/sizeof(sels[0])); i++) {
		if ([row respondsToSelector:sels[i]]) {
			id v = ((id (*)(id, SEL))objc_msgSend)(row, sels[i]);
			if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
		}
	}
	// Fallback: description (útil pra diagnóstico)
	NSString *desc = [row description];
	return desc;
}

static UIViewController *sci_dogfoodingAssistantVC(id userSession) {
	Class cls = objc_getClass("_TtC36IGSundialYourAlgoDogfoodingAssistant50IGSundialYourAlgoDogfoodingAssistantViewController");
	if (!cls) return nil;
	// analyticsModule: tenta pela userSession
	id analyticsModule = nil;
	if (userSession && [userSession respondsToSelector:@selector(analyticsModule)]) {
		analyticsModule = ((id (*)(id, SEL))objc_msgSend)(userSession, @selector(analyticsModule));
	}
	// Fallback: passa a própria userSession se não achou analyticsModule (o init aceita id)
	if (!analyticsModule) analyticsModule = userSession;

	SEL initSel = @selector(initWithAnalyticsModule:);
	if (!class_getInstanceMethod(cls, initSel)) return nil;
	id vc = [cls alloc];
	@try {
		vc = ((id (*)(id, SEL, id))objc_msgSend)(vc, initSel, analyticsModule);
	} @catch (__unused NSException *e) { return nil; }
	return vc;
}

static void sci_tapRepl(id self, SEL _cmd, id row) {
	if (!sBypassActive) { if (orig_tap) orig_tap(self, _cmd, row); return; }

	NSString *title = sci_rowTitle(row);
	BOOL isDogfooding = title && (
		[title rangeOfString:@"Dogfooding Assistant" options:NSCaseInsensitiveSearch].location != NSNotFound
	);

	if (SCIFileLogIsEnabled())
		SCIFLog(@"SCIDFSocket", @"tap row='%@' isDogfooding=%d", title, isDogfooding);

	if (!isDogfooding) { if (orig_tap) orig_tap(self, _cmd, row); return; }

	// bypass — apresenta direto
	@try {
		// userSession fica em ivar +0x18 do menu VC (validado no binário)
		Ivar iv = class_getInstanceVariable(object_getClass(self), "userSession");
		id userSession = nil;
		if (iv) userSession = object_getIvar(self, iv);
		UIViewController *vc = sci_dogfoodingAssistantVC(userSession);
		if (!vc) {
			if (SCIFileLogIsEnabled()) SCIFLog(@"SCIDFSocket", @"VC construction FAILED, fallback to orig");
			if (orig_tap) orig_tap(self, _cmd, row);
			return;
		}
		UIViewController *presenter = (UIViewController *)self;
		if (presenter.navigationController) {
			[presenter.navigationController pushViewController:vc animated:YES];
		} else {
			UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
			nav.modalPresentationStyle = UIModalPresentationPageSheet;
			[presenter presentViewController:nav animated:YES completion:nil];
		}
		if (SCIFileLogIsEnabled()) SCIFLog(@"SCIDFSocket", @"presented DogfoodingAssistantVC");
	} @catch (NSException *e) {
		if (SCIFileLogIsEnabled()) SCIFLog(@"SCIDFSocket", @"exception: %@", e.reason);
		if (orig_tap) orig_tap(self, _cmd, row);
	}
}

%ctor {
	@autoreleasepool {
		sBypassActive = [SCIInternalGatePrefs employeeInternalMasterEnabled]
		             || [SCIUtils getBoolPref:@"sci_dogfooding_socket_bypass"];
		if (!sBypassActive) return;

		Class cls = objc_getClass("_TtC17IGBugReporterMenu29IGBugReportMenuViewController");
		if (!cls) return;
		SEL sel = @selector(bugReportingActionCellButtonTapped:);
		Method m = class_getInstanceMethod(cls, sel);
		if (!m) return;
		const char *enc = method_getTypeEncoding(m);
		if (!enc || strcmp(enc, "v24@0:8@16") != 0) {
			if (SCIFileLogIsEnabled())
				SCIFLog(@"SCIDFSocket", @"ABI mismatch: %s", enc ?: "(null)");
			return;
		}
		@try {
			MSHookMessageEx(cls, sel, (IMP)sci_tapRepl, (IMP *)&orig_tap);
		} @catch (__unused NSException *e) {}
		if (SCIFileLogIsEnabled())
			SCIFLog(@"SCIDFSocket", @"installed, orig=%p", orig_tap);
	}
}
