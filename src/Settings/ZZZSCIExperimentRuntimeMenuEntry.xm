#import "TweakSettings.h"
#import "SCIExperimentRuntimeBrowserViewController.h"
#import "SCIEnabledExperimentTogglesViewController.h"
#import "SCIExpPersistedQueryViewController.h"
#import "../Features/ExpFlags/SCIAutofillInternalDevMode.h"
#import "../Features/ExpFlags/SCIPersistedQueryCatalog.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_runtime_exp)(id, SEL);

static UIViewController *RYUnifiedTopViewController(void) {
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

static void RYUnifiedPresentTextAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = RYUnifiedTopViewController();
        if (!vc) return;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act) {
            UIPasteboard.generalPasteboard.string = message ?: @"";
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    });
}

static SCISetting *RYUnifiedButton(NSString *title, NSString *subtitle, NSString *symbol, void (^action)(void)) {
    return [SCISetting buttonCellWithTitle:title subtitle:subtitle icon:[SCISymbol symbolWithName:symbol] action:action];
}

static NSDictionary *RYUnifiedDeveloperSection(void) {
    SCIEnabledExperimentTogglesViewController *mainVC = [SCIEnabledExperimentTogglesViewController new];
    mainVC.title = @"SCI DexKit";

    return @{
        @"header": @"SCI DexKit",
        @"footer": @"Unified developer/runtime surface. Primary path: grouped getter probes with observed system ON/OFF. Persisted GraphQL catalog is exposed here because QuickSnap/Instants and Dogfood also depend on server-side operation surfaces, not only local BOOL getters.",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"SCI DexKit"
                                       subtitle:@"Grouped providers, native-looking ON/OFF switches, observed defaults and override routing."
                                           icon:[SCISymbol symbolWithName:@"square.stack.3d.up"]
                                 viewController:mainVC],
            [SCISetting navigationCellWithTitle:@"Persisted GraphQL Mapping"
                                       subtitle:@"QuickSnap/Instants, Dogfood, Homecoming and client_doc_id operation catalog from schema JSON."
                                           icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                 viewController:[SCIExpPersistedQueryViewController new]],
            RYUnifiedButton(@"Persisted GraphQL Diagnostic",
                            @"Shows loaded schema source plus priority QuickSnap and Dogfood operation matches.",
                            @"list.bullet.clipboard",
                            ^{
                                [[SCIPersistedQueryCatalog sharedCatalog] reload];
                                RYUnifiedPresentTextAlert(@"Persisted GraphQL", [[SCIPersistedQueryCatalog sharedCatalog] diagnosticReport]);
                            }),
            [SCISetting navigationCellWithTitle:@"Runtime Browser"
                                       subtitle:@"Low-level classes/properties/ivars fallback."
                                           icon:[SCISymbol symbolWithName:@"books.vertical"]
                                 viewController:[SCIExperimentRuntimeBrowserViewController new]],
            RYUnifiedButton(@"Apply Autofill Defaults",
                            @"Writes Autofill backing defaults; getter overrides are managed inside SCI DexKit under Autofill/Internal.",
                            @"bolt.circle",
                            ^{
                                [SCIAutofillInternalDevMode applyEnabledToggles];
                                RYUnifiedPresentTextAlert(@"Autofill", [SCIAutofillInternalDevMode statusText]);
                            }),
            RYUnifiedButton(@"Autofill Status",
                            @"Safe status: backing defaults + selector availability; no direct Swift getter calls.",
                            @"doc.text.magnifyingglass",
                            ^{
                                RYUnifiedPresentTextAlert(@"Autofill", [SCIAutofillInternalDevMode statusText]);
                            })
        ]
    };
}

static BOOL RYUnifiedSectionAlreadyPresent(NSArray *navSections) {
    for (NSDictionary *section in navSections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if ([header isEqualToString:@"SCI DexKit"]) return YES;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : @[];
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if ([row.title isEqualToString:@"SCI DexKit"]) return YES;
        }
    }
    return NO;
}

static NSArray *RYUnifiedAugmentSections(NSArray *sections) {
    NSMutableArray *outSections = [sections mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger i = 0; i < outSections.count; i++) {
        NSDictionary *section = [outSections[i] isKindOfClass:NSDictionary.class] ? outSections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *row = [newRows[r] isKindOfClass:SCISetting.class] ? newRows[r] : nil;
            if (!row || ![row.title isEqualToString:@"Developer Mode"]) continue;

            NSArray *navSections = [row.navSections isKindOfClass:NSArray.class] ? row.navSections : @[];
            if (RYUnifiedSectionAlreadyPresent(navSections)) return outSections;

            NSMutableArray *newNavSections = [navSections mutableCopy] ?: [NSMutableArray array];
            [newNavSections insertObject:RYUnifiedDeveloperSection() atIndex:0];
            row.navSections = newNavSections;
            newRows[r] = row;

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
    return RYUnifiedAugmentSections(sections);
}

static void RYInstallUnifiedDeveloperMenuHook(void) {
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
    [SCIPersistedQueryCatalog prewarmInBackground];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RYInstallUnifiedDeveloperMenuHook();
    });
}
