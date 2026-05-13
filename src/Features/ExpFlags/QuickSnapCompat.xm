#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static BOOL sciQuickSnapEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_quicksnap"];
}

static BOOL (*orig_qs_enabled)(id, SEL, id) = NULL;
static BOOL new_qs_enabled(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_feed)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_feed(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_inbox)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_inbox(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_stories)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_stories(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_peek)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_peek(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_tray)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_tray(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_tray_peek)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_tray_peek(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_tray_pog)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_tray_pog(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_qs_enabled_empty_pog)(id, SEL, id) = NULL;
static BOOL new_qs_enabled_empty_pog(id self, SEL _cmd, id arg1) { return YES; }

static BOOL (*orig_qs_eligible_corner)(id, SEL) = NULL;
static BOOL new_qs_eligible_corner(id self, SEL _cmd) { return YES; }
static BOOL (*orig_qs_eligible_dialog)(id, SEL) = NULL;
static BOOL new_qs_eligible_dialog(id self, SEL _cmd) { return YES; }
static BOOL (*orig_qs_isqp)(id, SEL, id) = NULL;
static BOOL new_qs_isqp(id self, SEL _cmd, id arg1) { return YES; }
static void (*orig_qs_show_intro)(id, SEL) = NULL;
static void new_qs_show_intro(id self, SEL _cmd) {
    if (orig_qs_show_intro) orig_qs_show_intro(self, _cmd);
}

static BOOL (*orig_is_eligible_for_peek)(id, SEL) = NULL;
static BOOL new_is_eligible_for_peek(id self, SEL _cmd) { return YES; }
static BOOL (*orig_is_qs_recap)(id, SEL) = NULL;
static BOOL new_is_qs_recap(id self, SEL _cmd) { return YES; }
static BOOL (*orig__is_qs_recap)(id, SEL) = NULL;
static BOOL new__is_qs_recap(id self, SEL _cmd) { return YES; }
static BOOL (*orig_has_qs_recap_media)(id, SEL) = NULL;
static BOOL new_has_qs_recap_media(id self, SEL _cmd) { return YES; }
static BOOL (*orig_is_instants_recap_video)(id, SEL) = NULL;
static BOOL new_is_instants_recap_video(id self, SEL _cmd) { return YES; }
static BOOL (*orig_is_hidden_by_server)(id, SEL) = NULL;
static BOOL new_is_hidden_by_server(id self, SEL _cmd) { return NO; }
static BOOL (*orig__is_hidden_by_server)(id, SEL) = NULL;
static BOOL new__is_hidden_by_server(id self, SEL _cmd) { return NO; }

static BOOL (*orig_should_show_try_instants)(id, SEL) = NULL;
static BOOL new_should_show_try_instants(id self, SEL _cmd) { return NO; }
static BOOL (*orig_should_show_create_instant_cta)(id, SEL, id) = NULL;
static BOOL new_should_show_create_instant_cta(id self, SEL _cmd, id arg1) { return YES; }
static BOOL (*orig_should_show_recap_badge)(id, SEL) = NULL;
static BOOL new_should_show_recap_badge(id self, SEL _cmd) { return YES; }
static BOOL (*orig_show_recap_badge)(id, SEL) = NULL;
static BOOL new_show_recap_badge(id self, SEL _cmd) { return YES; }
static BOOL (*orig_hide_nux_dismiss)(id, SEL) = NULL;
static BOOL new_hide_nux_dismiss(id self, SEL _cmd) { return NO; }

static void sciCallInstantCreation(id self) {
    if (!self) return;

    SEL createSel = NSSelectorFromString(@"_performCreateInstant");
    if ([self respondsToSelector:createSel]) {
        ((void (*)(id, SEL))objc_msgSend)(self, createSel);
        return;
    }

    createSel = NSSelectorFromString(@"createAnInstant");
    if ([self respondsToSelector:createSel]) {
        ((void (*)(id, SEL))objc_msgSend)(self, createSel);
        return;
    }

    createSel = NSSelectorFromString(@"_showQuicksnapIntroDialog");
    if ([self respondsToSelector:createSel]) {
        ((void (*)(id, SEL))objc_msgSend)(self, createSel);
        return;
    }
}

static void (*orig_handle_try_or_create)(id, SEL) = NULL;
static void new_handle_try_or_create(id self, SEL _cmd) {
    sciCallInstantCreation(self);
}

static void (*orig_perform_try_instants)(id, SEL) = NULL;
static void new_perform_try_instants(id self, SEL _cmd) {
    sciCallInstantCreation(self);
}

static void (*orig_try_instants)(id, SEL) = NULL;
static void new_try_instants(id self, SEL _cmd) {
    sciCallInstantCreation(self);
}

static void hookClassBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, newImp, orig);
}

static void hookInstanceBool0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookInstanceBool1(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookInstanceVoid0(NSString *className, NSString *selName, IMP newImp, IMP *orig) {
    Class cls = NSClassFromString(className);
    if (!cls) return;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, newImp, orig);
}

static void hookZeroArgAcrossClasses(NSArray<NSString *> *classNames, NSString *selName, IMP newImp, IMP *orig) {
    SEL sel = NSSelectorFromString(selName);
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls || !class_getInstanceMethod(cls, sel)) continue;
        MSHookMessageEx(cls, sel, newImp, orig);
    }
}

static void hookQuickSnapFlowSelectors(NSArray<NSString *> *classNames) {
    for (NSString *className in classNames) {
        hookInstanceBool0(className, @"shouldShowTryInstants", (IMP)new_should_show_try_instants, (IMP *)&orig_should_show_try_instants);
        hookInstanceBool1(className, @"shouldShowCreateInstantCta:", (IMP)new_should_show_create_instant_cta, (IMP *)&orig_should_show_create_instant_cta);
        hookInstanceBool0(className, @"_shouldShowInstantsRecapVideoBadge", (IMP)new_should_show_recap_badge, (IMP *)&orig_should_show_recap_badge);
        hookInstanceBool0(className, @"showInstantsRecapVideoTrayBadge", (IMP)new_show_recap_badge, (IMP *)&orig_show_recap_badge);
        hookInstanceBool0(className, @"hideQuicksnapNuxDismissButton", (IMP)new_hide_nux_dismiss, (IMP *)&orig_hide_nux_dismiss);
        hookInstanceVoid0(className, @"handleTapOnTryInstantsOrCreateAnInstant", (IMP)new_handle_try_or_create, (IMP *)&orig_handle_try_or_create);
        hookInstanceVoid0(className, @"_performTryInstants", (IMP)new_perform_try_instants, (IMP *)&orig_perform_try_instants);
        hookInstanceVoid0(className, @"tryInstants", (IMP)new_try_instants, (IMP *)&orig_try_instants);
    }
}

%ctor {
    if (!sciQuickSnapEnabled()) return;

    NSString *quickSnapHelper = @"_TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper";
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabled:", (IMP)new_qs_enabled, (IMP *)&orig_qs_enabled);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInFeed:", (IMP)new_qs_enabled_feed, (IMP *)&orig_qs_enabled_feed);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInInbox:", (IMP)new_qs_enabled_inbox, (IMP *)&orig_qs_enabled_inbox);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInStories:", (IMP)new_qs_enabled_stories, (IMP *)&orig_qs_enabled_stories);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInNotesTray:", (IMP)new_qs_enabled_tray, (IMP *)&orig_qs_enabled_tray);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInNotesTrayWithPeek:", (IMP)new_qs_enabled_tray_peek, (IMP *)&orig_qs_enabled_tray_peek);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledInNotesTrayWithPog:", (IMP)new_qs_enabled_tray_pog, (IMP *)&orig_qs_enabled_tray_pog);
    hookClassBool1(quickSnapHelper, @"isQuicksnapNotesTrayEmptyPogEnabled:", (IMP)new_qs_enabled_empty_pog, (IMP *)&orig_qs_enabled_empty_pog);
    hookClassBool1(quickSnapHelper, @"isQuicksnapEnabledAsPeek:", (IMP)new_qs_enabled_peek, (IMP *)&orig_qs_enabled_peek);

    NSString *trayController = @"_TtC21IGNotesTrayController21IGNotesTrayController";
    hookInstanceBool0(trayController, @"_isEligibleForQuicksnapCornerStackTransitionDialog", (IMP)new_qs_eligible_corner, (IMP *)&orig_qs_eligible_corner);
    hookInstanceBool0(trayController, @"_isEligibleForQuicksnapDialog", (IMP)new_qs_eligible_dialog, (IMP *)&orig_qs_eligible_dialog);
    hookInstanceBool1(trayController, @"isQPEnabled:", (IMP)new_qs_isqp, (IMP *)&orig_qs_isqp);
    hookInstanceVoid0(trayController, @"_showQuicksnapIntroDialog", (IMP)new_qs_show_intro, (IMP *)&orig_qs_show_intro);

    hookInstanceBool1(@"IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)new_qs_isqp, NULL);
    hookInstanceBool1(@"_TtC24IGDirectNotesTrayUISwift37IGDirectNotesTrayRowSectionController", @"isQPEnabled:", (IMP)new_qs_isqp, NULL);

    NSArray<NSString *> *instantsClasses = @[
        @"IGInstantGestureRecognizer",
        @"IGAPIQuickSnapData",
        @"XDTQuickSnapData",
        @"IGAPIQuicksnapRecapMediaInfo",
        @"XDTQuicksnapRecapMediaInfo"
    ];
    hookZeroArgAcrossClasses(instantsClasses, @"isEligibleForPeek", (IMP)new_is_eligible_for_peek, (IMP *)&orig_is_eligible_for_peek);
    hookZeroArgAcrossClasses(instantsClasses, @"isQuicksnapRecap", (IMP)new_is_qs_recap, (IMP *)&orig_is_qs_recap);
    hookZeroArgAcrossClasses(instantsClasses, @"_isQuicksnapRecap", (IMP)new__is_qs_recap, (IMP *)&orig__is_qs_recap);
    hookZeroArgAcrossClasses(instantsClasses, @"hasQuicksnapRecapMedia", (IMP)new_has_qs_recap_media, (IMP *)&orig_has_qs_recap_media);
    hookZeroArgAcrossClasses(instantsClasses, @"isInstantsRecapVideo", (IMP)new_is_instants_recap_video, (IMP *)&orig_is_instants_recap_video);

    NSArray<NSString *> *quickSnapFlowClasses = @[
        @"_TtC18IGInstantsDelegate22IGInstantsDelegateImpl",
        @"_TtC30IGQuickSnapPresentationManager30IGQuickSnapPresentationManager",
        @"_TtC26IGQuickSnapCreationManager26IGQuickSnapCreationManager",
        @"_TtC18IGQuickSnapService18IGQuickSnapService",
        @"_TtC23IGQuickSnapCreationCore33IGQuickSnapCreationViewController",
        @"_TtC36IGQuickSnapNavigationV3ContainerCore46IGQuickSnapNavigationV3ContainerViewController",
        @"_TtC45IGQuickSnapNavigationV3CreationViewController45IGQuickSnapNavigationV3CreationViewController",
        @"_TtC48IGQuickSnapNavigationV3ConsumptionViewController48IGQuickSnapNavigationV3ConsumptionViewController",
        @"_TtC30IGQuickSnapWidgetMerchandising39IGWidgetMerchandisingFlowViewController",
        @"_TtC44IGQuickSnapWidgetMerchandisingPillController44IGQuickSnapWidgetMerchandisingPillController"
    ];
    hookQuickSnapFlowSelectors(quickSnapFlowClasses);

    hookInstanceBool0(@"_TtC18IGQuickSnapService18IGQuickSnapService", @"isHiddenByServer", (IMP)new_is_hidden_by_server, (IMP *)&orig_is_hidden_by_server);
    hookInstanceBool0(@"_TtC18IGQuickSnapService18IGQuickSnapService", @"_isHiddenByServer", (IMP)new__is_hidden_by_server, (IMP *)&orig__is_hidden_by_server);
}
