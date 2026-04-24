#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciPrismEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_prism"];
}

static BOOL (*orig_prism_bool0)(id, SEL) = NULL;
static BOOL new_prism_bool0(id self, SEL _cmd) {
    return YES;
}

static BOOL (*orig_prism_bool1)(id, SEL, id) = NULL;
static BOOL new_prism_bool1(id self, SEL _cmd, id arg1) {
    return YES;
}

static void (*orig_set_subtitle_header)(id, SEL, BOOL) = NULL;
static void new_set_subtitle_header(id self, SEL _cmd, BOOL value) {
    if (orig_set_subtitle_header) orig_set_subtitle_header(self, _cmd, YES);
}

static id (*orig_prism_menu_init3)(id, SEL, id, id, BOOL) = NULL;
static id new_prism_menu_init3(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled) {
    return orig_prism_menu_init3 ? orig_prism_menu_init3(self, _cmd, menuElements, headerText, YES) : self;
}

static id (*orig_prism_menu_init5)(id, SEL, id, id, BOOL, BOOL, BOOL) = NULL;
static id new_prism_menu_init5(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment) {
    return orig_prism_menu_init5 ? orig_prism_menu_init5(self, _cmd, menuElements, headerText, YES, allowScrollingItems, allowMixedTextAlignment) : self;
}

static id (*orig_prism_menu_init6)(id, SEL, id, id, BOOL, BOOL, BOOL, BOOL) = NULL;
static id new_prism_menu_init6(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment, BOOL enableScrollToDismiss) {
    return orig_prism_menu_init6 ? orig_prism_menu_init6(self, _cmd, menuElements, headerText, YES, allowScrollingItems, allowMixedTextAlignment, enableScrollToDismiss) : self;
}

static void sciHookInst(Class cls, NSString *selName, IMP repl, IMP *orig) {
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, repl, orig);
}

static void sciHookClass(Class cls, NSString *selName, IMP repl, IMP *orig) {
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, repl, orig);
}

static void sciHookBool0OnKnownPrismGateClasses(NSArray<NSString *> *selectors) {
    NSArray<NSString *> *classes = @[
        @"IGDSLauncherConfig",
        @"IGDSMenu",
        @"IGDSPrismMenuItem",
        @"IGDSPrismMenuItemBuilder",
        @"IGDSPrismMenuElement",
        @"_TtC13IGDSPrismMenu13IGDSPrismMenu",
        @"_TtC13IGDSPrismMenu17IGDSPrismMenuView",
        @"_TtC13IGDSPrismMenu27IGDSPrismMenuViewController",
        @"_TtC13IGDSPrismMenu23IGDSPrismMenuHeaderView"
    ];

    for (NSString *className in classes) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        for (NSString *selName in selectors) {
            sciHookInst(cls, selName, (IMP)new_prism_bool0, (IMP *)&orig_prism_bool0);
            sciHookClass(cls, selName, (IMP)new_prism_bool0, (IMP *)&orig_prism_bool0);
        }
    }
}

%ctor {
    if (!sciPrismEnabled()) return;

    NSArray<NSString *> *boolSelectors = @[
        @"isPrismEnabled",
        @"isPrismButtonEnabled",
        @"isPrismControlsEnabled",
        @"isPrismContextMenuEnabled",
        @"isPrismContextMenuRefactorEnabled",
        @"isPrismOverflowMenuEnabled",
        @"isPrismOverflowMenuStampWidthIncreased",
        @"isPrismBottomSheetEnabled",
        @"isPrismToastsEnabled",
        @"isPrismAlertDialogEnabled",
        @"isPrismDefaultTooltipEnabled",
        @"isPrismMediaButtonsEnabled",
        @"isPrismHeadlineEnabled",
        @"isPrismLoadingBarEnabled",
        @"isPrismIndigoButtonEnabled",
        @"isPrismIndigoButtonM1DirectEnabled",
        @"isPrismIndigoPolishBundleEnabled",
        @"isPrismIndigoActionCellsEnabled",
        @"isPrismAvatarRingEnabled",
        @"_isPrismAvatarRingEnabled",
        @"isIGBPrismEnabled",
        @"_isPrismDesignEnabled",
        @"prismDesignEnabled",
        @"usePrismDesign",
        @"usePrismColors",
        @"enablePrism",
        @"enablePrismStyleCTA",
        @"shouldRenderPrismStyle",
        @"shouldRenderPrismContent",
        @"badgingPrismEnabled"
    ];
    sciHookBool0OnKnownPrismGateClasses(boolSelectors);

    Class prismMenuView = NSClassFromString(@"_TtC13IGDSPrismMenu17IGDSPrismMenuView");
    sciHookInst(prismMenuView, @"shouldDisplaySubtitleInOverflowMenuHeader", (IMP)new_prism_bool0, (IMP *)&orig_prism_bool0);
    sciHookInst(prismMenuView, @"setShouldDisplaySubtitleInOverflowMenuHeader:", (IMP)new_set_subtitle_header, (IMP *)&orig_set_subtitle_header);
    sciHookInst(prismMenuView, @"initWithMenuElements:headerText:edrEnabled:", (IMP)new_prism_menu_init3, (IMP *)&orig_prism_menu_init3);
    sciHookInst(prismMenuView, @"initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:", (IMP)new_prism_menu_init5, (IMP *)&orig_prism_menu_init5);
    sciHookInst(prismMenuView, @"initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:enableScrollToDismiss:", (IMP)new_prism_menu_init6, (IMP *)&orig_prism_menu_init6);

    Class launcher = NSClassFromString(@"IGDSLauncherConfig");
    sciHookInst(launcher, @"isPrismEnabledForUpcomingEventHalfSheetWithSponsoredInfoProvider:launcherSet:", (IMP)new_prism_bool1, (IMP *)&orig_prism_bool1);
}
