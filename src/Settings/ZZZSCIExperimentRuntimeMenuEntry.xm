#import "TweakSettings.h"
#import "SCIExperimentRuntimeBrowserViewController.h"
#import "SCIEnabledExperimentTogglesViewController.h"
#import "../Features/ExpFlags/SCIAutofillInternalDevMode.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_runtime_exp)(id, SEL);

static SCISetting *RYRuntimeExpSwitch(NSString *title, NSString *subtitle, NSString *key, BOOL restart) {
    return [SCISetting switchCellWithTitle:title subtitle:subtitle defaultsKey:key requiresRestart:restart];
}

static SCISetting *RYRuntimeExpButton(NSString *title, NSString *subtitle, NSString *symbol, void (^action)(void)) {
    return [SCISetting buttonCellWithTitle:title subtitle:subtitle icon:[SCISymbol symbolWithName:symbol] action:action];
}

static UIViewController *RYRuntimeExpTopViewController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window) break;
    }
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static void RYRuntimeExpPresentTextAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = RYRuntimeExpTopViewController();
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            UIPasteboard.generalPasteboard.string = message ?: @"";
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static NSDictionary *RYRuntimeExperimentSection(void) {
    return @{
        @"header": @"Runtime ObjC Experiments",
        @"footer": @"Main executable experiment tools. Enabled Experiment Toggles lists no-argument BOOL getters from the Instagram exec whose class/method contains enabled + experiment/feature/launcher/mobileconfig/internal. Default is shown from the original return once the app naturally calls the getter; override is Default / Force YES / Force NO.",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"Enabled Experiment Toggles"
                                       subtitle:@"Main exec only: all enabled/experiment BOOL getters with observed default + override toggle."
                                           icon:[SCISymbol symbolWithName:@"switch.2"]
                                 viewController:[SCIEnabledExperimentTogglesViewController new]],
            [SCISetting navigationCellWithTitle:@"Runtime Experiment Browser"
                                       subtitle:@"Broader runtime browser for Experiment/Enabled/BOOL classes, methods, properties and ivars."
                                           icon:[SCISymbol symbolWithName:@"books.vertical"]
                                 viewController:[SCIExperimentRuntimeBrowserViewController new]],
            RYRuntimeExpSwitch(@"Autofill Debug Footer",
                               @"Writes autofill_internal_settings_debug_footer_enabled = YES when applied.",
                               @"sci_dev_autofill_debug_footer",
                               NO),
            RYRuntimeExpSwitch(@"Force Bloks Experience",
                               @"Writes autofill_internal_settings_force_bloks_experience = 1 when applied.",
                               @"sci_dev_autofill_force_bloks",
                               NO),
            RYRuntimeExpSwitch(@"Bloks Prefetch",
                               @"Writes autofill_internal_settings_bloks_prefetch_enabled = YES when applied.",
                               @"sci_dev_autofill_bloks_prefetch",
                               NO),
            RYRuntimeExpButton(@"Apply Autofill Internal Now",
                               @"Runs the selected Autofill internal defaults writes immediately.",
                               @"bolt.circle",
                               ^{
                                   [SCIAutofillInternalDevMode applyEnabledToggles];
                                   RYRuntimeExpPresentTextAlert(@"Autofill Internal Status", [SCIAutofillInternalDevMode statusText]);
                               }),
            RYRuntimeExpButton(@"Show Autofill Internal Status",
                               @"Safe status: reads backing defaults and selector availability without calling Swift getters.",
                               @"doc.text.magnifyingglass",
                               ^{
                                   RYRuntimeExpPresentTextAlert(@"Autofill Internal Status", [SCIAutofillInternalDevMode statusText]);
                               })
        ]
    };
}

static BOOL RYRuntimeSectionAlreadyPresent(NSArray *navSections) {
    for (NSDictionary *section in navSections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if ([header isEqualToString:@"Runtime ObjC Experiments"]) return YES;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : @[];
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if ([row.title isEqualToString:@"Enabled Experiment Toggles"]) return YES;
        }
    }
    return NO;
}

static NSArray *RYRuntimeAugmentSections(NSArray *sections) {
    NSMutableArray *outSections = [sections mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger i = 0; i < outSections.count; i++) {
        NSDictionary *section = [outSections[i] isKindOfClass:NSDictionary.class] ? outSections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changedRows = NO;

        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *row = [newRows[r] isKindOfClass:SCISetting.class] ? newRows[r] : nil;
            if (!row) continue;
            if (![row.title isEqualToString:@"Developer Mode"]) continue;

            NSArray *navSections = [row.navSections isKindOfClass:NSArray.class] ? row.navSections : @[];
            if (RYRuntimeSectionAlreadyPresent(navSections)) return outSections;

            NSMutableArray *newNavSections = [navSections mutableCopy] ?: [NSMutableArray array];
            [newNavSections insertObject:RYRuntimeExperimentSection() atIndex:0];
            row.navSections = newNavSections;
            newRows[r] = row;
            changedRows = YES;
            break;
        }

        if (changedRows) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            outSections[i] = newSection;
            return outSections;
        }
    }

    return outSections;
}

static NSArray *new_sections_runtime_exp(id self, SEL _cmd) {
    NSArray *sections = orig_sections_runtime_exp ? orig_sections_runtime_exp(self, _cmd) : @[];
    return RYRuntimeAugmentSections(sections);
}

static void RYInstallRuntimeExperimentMenuHook(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_runtime_exp, (IMP *)&orig_sections_runtime_exp);
}

%ctor {
    [SCIAutofillInternalDevMode registerDefaults];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RYInstallRuntimeExperimentMenuHook();
    });
}
