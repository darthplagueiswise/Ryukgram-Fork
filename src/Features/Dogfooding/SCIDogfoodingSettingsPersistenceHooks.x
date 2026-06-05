// SCIDogfoodingSettingsPersistenceHooks.x
//
// Notes Dogfooding opens natively, but on sideload/rootless builds the native
// dogfood UI may only mutate an in-memory IGDogfoodingSettingsOptions object.
// These hooks do NOT force random MobileConfig IDs. They capture the real
// DogfoodingSettings delegate updates, persist a FLEX-style snapshot, and when
// the item/options expose launcher+parameter+value metadata, mirror it through
// the same IGDogfoodingAssistantLauncherClient path used by native dogfood.

#import "SCIDogfoodObjectRuntime.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static void (*orig_df_toggle)(id, SEL, id, BOOL) = NULL;
static void (*orig_df_selection)(id, SEL, id, id) = NULL;

static void new_df_toggle(id self, SEL _cmd, id cell, BOOL enabled) {
    id item = nil;
    @try {
        // Capture BEFORE calling the Swift delegate implementation. The native handler
        // may reload/dismiss cells immediately; touching them after %orig is what made
        // Direct Notes Dogfooding crash when tapping options.
        if ([cell respondsToSelector:@selector(item)]) item = ((id(*)(id,SEL))objc_msgSend)(cell, @selector(item));
        [SCIDogfoodObjectRuntime noteDogfoodingSettingChangeWithItem:item options:nil toggleValue:@(enabled) source:@"dogfoodingSettingsToggleCell:didToggle:"];
    } @catch (__unused id e) {}
    if (orig_df_toggle) orig_df_toggle(self, _cmd, cell, enabled);
}

static void new_df_selection(id self, SEL _cmd, id selectionVC, id options) {
    id item = nil;
    @try {
        // Same rule as toggles: only capture stable ObjC references before the native
        // Swift delegate mutates the view hierarchy/options model.
        if ([selectionVC respondsToSelector:@selector(item)]) item = ((id(*)(id,SEL))objc_msgSend)(selectionVC, @selector(item));
        [SCIDogfoodObjectRuntime noteDogfoodingSettingChangeWithItem:item options:options toggleValue:nil source:@"dogfoodingSettingsSelectionViewController:updatedOptions:"];
    } @catch (__unused id e) {}
    if (orig_df_selection) orig_df_selection(self, _cmd, selectionVC, options);
}

static void SCIHookDogfoodingSettingsDelegate(Class cls) {
    if (!cls) return;
    SEL toggleSel = @selector(dogfoodingSettingsToggleCell:didToggle:);
    if ([cls instancesRespondToSelector:toggleSel] && !orig_df_toggle) {
        MSHookMessageEx(cls, toggleSel, (IMP)new_df_toggle, (IMP *)&orig_df_toggle);
    }
    SEL selSel = @selector(dogfoodingSettingsSelectionViewController:updatedOptions:);
    if ([cls instancesRespondToSelector:selSel] && !orig_df_selection) {
        MSHookMessageEx(cls, selSel, (IMP)new_df_selection, (IMP *)&orig_df_selection);
    }
}

%ctor {
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIHookDogfoodingSettingsDelegate(NSClassFromString(@"IGDogfoodingSettings.IGDogfoodingSettingsViewController"));
            SCIHookDogfoodingSettingsDelegate(NSClassFromString(@"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SCIHookDogfoodingSettingsDelegate(NSClassFromString(@"IGDogfoodingSettings.IGDogfoodingSettingsViewController"));
                SCIHookDogfoodingSettingsDelegate(NSClassFromString(@"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"));
            });
        });
    }
}
