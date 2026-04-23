#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciPrismEnabled(void) {
    return [SCIUtils getBoolPref:@"igt_prism"];
}

static BOOL retYES0(id self, SEL _cmd) { return YES; }

static NSMutableSet<NSString *> *hookedKeys(void) {
    static NSMutableSet<NSString *> *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ set = [NSMutableSet set]; });
    return set;
}

static void hookSelectorEverywhere(NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if (!sel) return;

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;

    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!cls) continue;

        if (class_getInstanceMethod(cls, sel)) {
            NSString *key = [NSString stringWithFormat:@"I:%s:%@", class_getName(cls), selName];
            if (![hookedKeys() containsObject:key]) {
                [hookedKeys() addObject:key];
                MSHookMessageEx(cls, sel, (IMP)retYES0, NULL);
            }
        }

        Class meta = object_getClass(cls);
        if (meta && class_getInstanceMethod(meta, sel)) {
            NSString *key = [NSString stringWithFormat:@"C:%s:%@", class_getName(cls), selName];
            if (![hookedKeys() containsObject:key]) {
                [hookedKeys() addObject:key];
                MSHookMessageEx(meta, sel, (IMP)retYES0, NULL);
            }
        }
    }

    free(classes);
}

%ctor {
    if (!sciPrismEnabled()) return;

    NSArray<NSString *> *selectors = @[
        @"isPrismEnabled",
        @"isRevertedPrismColorEnabled",
        @"isPrismButtonEnabled",
        @"isPrismControlsEnabled",
        @"isPrismIndigoActionCellsEnabled",
        @"isPrismIndigoButtonEnabled",
        @"isPrismToastsEnabled",
        @"isPrismContextMenuRefactorEnabled",
        @"isPrismContextMenuEnabled",
        @"isPrismDefaultTooltipEnabled",
        @"isPrismAlertDialogEnabled",
        @"isPrismIndigoPolishBundleEnabled",
        @"isPrismIndigoButtonM1DirectEnabled",
        @"isPrismMediaButtonsEnabled",
        @"isIGBPrismEnabled",
        @"isPrismAllUserAssetsEnabled",
        @"isPrismFollowRelatedUserAssetsEnabled",
        @"isPrismBottomSheetEnabled",
        @"isPrismCommentsEmptyStateEnabled",
        @"isPrismDividersUpdateEnabled",
        @"isPrismDividersProfileUpdateEnabled",
        @"isPrismDividersNotificationsUpdateEnabled",
        @"isPrismDividersEditReelEnabled",
        @"isPrismDividersCommentsUpdateEnabled",
        @"isPrismDividersShareSheetUpdateEnabled",
        @"isPrismOverflowMenuEnabled",
        @"isPrismOverflowMenuStampWidthIncreased",
        @"badgingPrismEnabled",
        @"_isPrismAvatarRingEnabled",
        @"_isPrismSecondaryNonUserIconsEnabled",
        @"_isPrismDesignEnabled",
        @"usePrismColors"
    ];

    for (NSString *selName in selectors) {
        hookSelectorEverywhere(selName);
    }
}
