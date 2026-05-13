#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciPrismEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_prism"];
}

static NSMutableDictionary<NSString *, NSValue *> *gPrismOriginals;

static NSString *SCIPrismKeyForHookClass(Class hookClass, SEL sel) {
    if (!hookClass || !sel) return @"";
    NSString *kind = class_isMetaClass(hookClass) ? @"+" : @"-";
    return [NSString stringWithFormat:@"%@[%s %@]", kind, class_getName(hookClass), NSStringFromSelector(sel)];
}

static IMP SCIPrismOriginalFor(id self, SEL sel) {
    Class hookClass = object_getClass(self);
    NSString *key = SCIPrismKeyForHookClass(hookClass, sel);
    NSValue *value = gPrismOriginals[key];
    if (value) return (IMP)(uintptr_t)value.pointerValue;

    Class c = hookClass;
    while ((c = class_getSuperclass(c))) {
        key = SCIPrismKeyForHookClass(c, sel);
        value = gPrismOriginals[key];
        if (value) return (IMP)(uintptr_t)value.pointerValue;
    }
    return NULL;
}

static void SCIPrismStoreOriginal(Class hookClass, SEL sel, IMP original) {
    if (!hookClass || !sel || !original) return;
    if (!gPrismOriginals) gPrismOriginals = [NSMutableDictionary dictionary];
    gPrismOriginals[SCIPrismKeyForHookClass(hookClass, sel)] = [NSValue valueWithPointer:(const void *)(uintptr_t)original];
}

static BOOL new_prism_bool0(id self, SEL _cmd) {
    return YES;
}

static BOOL new_prism_bool1(id self, SEL _cmd, id arg1) {
    return YES;
}

static void new_set_subtitle_header(id self, SEL _cmd, BOOL value) {
    void (*orig)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))SCIPrismOriginalFor(self, _cmd);
    if (orig) orig(self, _cmd, YES);
}

static id new_prism_menu_init3(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled) {
    id (*orig)(id, SEL, id, id, BOOL) = (id (*)(id, SEL, id, id, BOOL))SCIPrismOriginalFor(self, _cmd);
    return orig ? orig(self, _cmd, menuElements, headerText, YES) : self;
}

static id new_prism_menu_init4(id self, SEL _cmd, id menuItem, BOOL edrEnabled, BOOL isHeader, BOOL isSubmenu) {
    id (*orig)(id, SEL, id, BOOL, BOOL, BOOL) = (id (*)(id, SEL, id, BOOL, BOOL, BOOL))SCIPrismOriginalFor(self, _cmd);
    return orig ? orig(self, _cmd, menuItem, YES, isHeader, isSubmenu) : self;
}

static id new_prism_menu_init5(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment) {
    id (*orig)(id, SEL, id, id, BOOL, BOOL, BOOL) = (id (*)(id, SEL, id, id, BOOL, BOOL, BOOL))SCIPrismOriginalFor(self, _cmd);
    return orig ? orig(self, _cmd, menuElements, headerText, YES, allowScrollingItems, allowMixedTextAlignment) : self;
}

static id new_prism_menu_init6(id self, SEL _cmd, id menuElements, id headerText, BOOL edrEnabled, BOOL allowScrollingItems, BOOL allowMixedTextAlignment, BOOL enableScrollToDismiss) {
    id (*orig)(id, SEL, id, id, BOOL, BOOL, BOOL, BOOL) = (id (*)(id, SEL, id, id, BOOL, BOOL, BOOL, BOOL))SCIPrismOriginalFor(self, _cmd);
    return orig ? orig(self, _cmd, menuElements, headerText, YES, allowScrollingItems, allowMixedTextAlignment, enableScrollToDismiss) : self;
}

static void sciHookMessage(Class hookClass, NSString *selName, IMP repl) {
    if (!hookClass || !selName.length || !repl) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(hookClass, sel)) return;
    NSString *key = SCIPrismKeyForHookClass(hookClass, sel);
    if (gPrismOriginals[key]) return;
    IMP orig = NULL;
    MSHookMessageEx(hookClass, sel, repl, &orig);
    SCIPrismStoreOriginal(hookClass, sel, orig);
}

static void sciHookInst(Class cls, NSString *selName, IMP repl) {
    sciHookMessage(cls, selName, repl);
}

static void sciHookClass(Class cls, NSString *selName, IMP repl) {
    if (!cls) return;
    sciHookMessage(object_getClass(cls), selName, repl);
}

static void sciHookBool0OnKnownPrismGateClasses(NSArray<NSString *> *selectors) {
    NSArray<NSString *> *classes = @[
        @"IGDSLauncherConfig",
        @"IGDSMenu",
        @"IGDSPrismMenuItem",
        @"IGDSPrismMenuItemBuilder",
        @"IGDSPrismMenuElement",
        @"IGDSPrismMenuItemAccessory",
        @"_TtC13IGDSPrismMenu13IGDSPrismMenu",
        @"_TtC13IGDSPrismMenu17IGDSPrismMenuView",
        @"_TtC13IGDSPrismMenu27IGDSPrismMenuViewController",
        @"_TtC13IGDSPrismMenu23IGDSPrismMenuHeaderView",
        @"_TtC13IGDSPrismMenu21IGDSPrismMenuItemView",
        @"_TtC13IGDSPrismMenu31IGDSPrismMenuHorizontalItemView",
        @"_TtC13IGDSPrismMenu33IGDSPrismMenuHorizontalItemButton"
    ];

    for (NSString *className in classes) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        for (NSString *selName in selectors) {
            sciHookInst(cls, selName, (IMP)new_prism_bool0);
            sciHookClass(cls, selName, (IMP)new_prism_bool0);
        }
    }
}

static void sciHookPrismMenuConstructors(Class cls) {
    if (!cls) return;
    sciHookInst(cls, @"initWithMenuElements:headerText:edrEnabled:", (IMP)new_prism_menu_init3);
    sciHookInst(cls, @"initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:", (IMP)new_prism_menu_init5);
    sciHookInst(cls, @"initWithMenuElements:headerText:edrEnabled:allowScrollingItems:allowMixedTextAlignment:enableScrollToDismiss:", (IMP)new_prism_menu_init6);
    sciHookInst(cls, @"initWithMenuItem:edrEnabled:isHeader:isSubmenu:", (IMP)new_prism_menu_init4);
}

%ctor {
    if (!sciPrismEnabled()) return;

    NSArray<NSString *> *boolSelectors = @[
        @"isPrismEnabled",
        @"isRevertedPrismColorEnabled",
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

    Class prismMenu = NSClassFromString(@"_TtC13IGDSPrismMenu13IGDSPrismMenu");
    Class prismMenuView = NSClassFromString(@"_TtC13IGDSPrismMenu17IGDSPrismMenuView");
    sciHookPrismMenuConstructors(prismMenu);
    sciHookPrismMenuConstructors(prismMenuView);

    sciHookInst(prismMenuView, @"shouldDisplaySubtitleInOverflowMenuHeader", (IMP)new_prism_bool0);
    sciHookInst(prismMenuView, @"setShouldDisplaySubtitleInOverflowMenuHeader:", (IMP)new_set_subtitle_header);

    Class launcher = NSClassFromString(@"IGDSLauncherConfig");
    sciHookInst(launcher, @"isPrismEnabledForUpcomingEventHalfSheetWithSponsoredInfoProvider:launcherSet:", (IMP)new_prism_bool1);
    sciHookClass(launcher, @"isPrismEnabledForUpcomingEventHalfSheetWithSponsoredInfoProvider:launcherSet:", (IMP)new_prism_bool1);

    NSLog(@"[RyukGram][Prism] Prism hooks installed. IGDSPrismMenu=%@ IGDSPrismMenuView=%@", prismMenu, prismMenuView);
}
