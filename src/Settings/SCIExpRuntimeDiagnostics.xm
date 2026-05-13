#import "SCIExpFlagsViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const unsigned long long RYDogGoldenAnchor = 0x0081008a00000122ULL;

static BOOL RYExpBrowserTab(id self) {
    if (!self || ![self respondsToSelector:@selector(seg)]) return NO;
    @try {
        UISegmentedControl *seg = ((id (*)(id, SEL))objc_msgSend)(self, @selector(seg));
        return [seg isKindOfClass:[UISegmentedControl class]] && seg.selectedSegmentIndex == 0;
    } @catch (__unused id e) {
        return NO;
    }
}

static Class RYResolvedClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!name.length) continue;
        Class cls = NSClassFromString(name);
        if (cls) return cls;
        cls = objc_getClass(name.UTF8String);
        if (cls) return cls;
    }
    return Nil;
}

static NSString *RYBool(BOOL value) { return value ? @"YES" : @"NO"; }

static NSString *RYName(Class cls) {
    if (!cls) return @"missing";
    const char *n = class_getName(cls);
    return n ? ([NSString stringWithUTF8String:n] ?: NSStringFromClass(cls)) : (NSStringFromClass(cls) ?: @"?");
}

static NSString *RYClassLine(NSString *title, NSArray<NSString *> *aliases) {
    Class cls = RYResolvedClass(aliases);
    if (!cls) return [NSString stringWithFormat:@"%@ = missing", title];
    Class superCls = class_getSuperclass(cls);
    return [NSString stringWithFormat:@"%@ = found · runtime=%@ · superclass=%@ · UIViewController=%@",
            title, RYName(cls), superCls ? RYName(superCls) : @"nil", RYBool([cls isSubclassOfClass:[UIViewController class]])];
}

static NSString *RYMethodLine(NSString *title, Class cls, SEL sel, BOOL isClassMethod) {
    BOOL ok = NO;
    if (cls && sel) ok = isClassMethod ? class_getClassMethod(cls, sel) != NULL : class_getInstanceMethod(cls, sel) != NULL;
    return [NSString stringWithFormat:@"%@ = %@", title, RYBool(ok)];
}

static NSString *RYDogfoodingNativeCheckReport(void) {
    NSArray *entryAliases = @[@"IGDogfoodingSettings.IGDogfoodingSettings", @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"];
    NSArray *vcAliases = @[@"IGDogfoodingSettings.IGDogfoodingSettingsViewController", @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController", @"IGDogfoodingSettingsViewController"];
    NSArray *selectionAliases = @[@"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController", @"_TtC20IGDogfoodingSettings43IGDogfoodingSettingsSelectionViewController", @"IGDogfoodingSettingsSelectionViewController"];
    NSArray *lockoutAliases = @[@"IGDogfoodingFirst.DogfoodingProductionLockoutViewController", @"_TtC17IGDogfoodingFirst41DogfoodingProductionLockoutViewController", @"DogfoodingProductionLockoutViewController"];
    NSArray *configAliases = @[@"IGDogfoodingSettingsConfig", @"IGDogfoodingSettings.IGDogfoodingSettingsConfig", @"_TtC20IGDogfoodingSettings25IGDogfoodingSettingsConfig"];

    Class entry = RYResolvedClass(entryAliases);
    Class vc = RYResolvedClass(vcAliases);
    Class selectionVC = RYResolvedClass(selectionAliases);

    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:@"Dogfooding native check"];
    [lines addObject:@"mode = safe check only; no alloc, no KVC, no method invocation"];
    [lines addObject:[NSString stringWithFormat:@"goldenAnchor = 0x%016llx / %llu", RYDogGoldenAnchor, RYDogGoldenAnchor]];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"entrypoint", entryAliases)];
    [lines addObject:RYMethodLine(@"+openWithConfig:onViewController:userSession:", entry, NSSelectorFromString(@"openWithConfig:onViewController:userSession:"), YES)];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"settingsViewController", vcAliases)];
    [lines addObject:RYMethodLine(@"-initWithConfig:userSession:", vc, NSSelectorFromString(@"initWithConfig:userSession:"), NO)];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"selectionViewController", selectionAliases)];
    [lines addObject:RYMethodLine(@"-initWithItem:options:", selectionVC, NSSelectorFromString(@"initWithItem:options:"), NO)];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"lockoutViewController", lockoutAliases)];
    [lines addObject:RYClassLine(@"settingsConfig", configAliases)];
    [lines addObject:RYClassLine(@"IGDogfooderProd", @[@"IGDogfooderProd"] )];
    [lines addObject:RYClassLine(@"IGDogfoodingLogger", @[@"IGDogfoodingLogger"] )];
    [lines addObject:RYClassLine(@"DogfoodingEligibilityQueryBuilder", @[@"DogfoodingEligibilityQueryBuilder"] )];
    [lines addObject:@""];
    [lines addObject:@"Next: find the callsite for +openWithConfig:onViewController:userSession: in the main Instagram executable. That callsite should reveal the native row/button and the real config/session source."];
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *RYLocalExperimentCheckReport(void) {
    Class meta = RYResolvedClass(@[@"MetaLocalExperiment"]);
    Class family = RYResolvedClass(@[@"FamilyLocalExperiment"]);
    Class lidLocal = RYResolvedClass(@[@"LIDLocalExperiment"]);
    Class lidGenerator = RYResolvedClass(@[@"LIDExperimentGenerator"]);
    Class fdidGenerator = RYResolvedClass(@[@"FDIDExperimentGenerator"]);
    Class listVC = RYResolvedClass(@[@"MetaLocalExperimentListViewController"]);

    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:@"LocalExperiment native check"];
    [lines addObject:@"mode = safe check only"];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"MetaLocalExperiment", @[@"MetaLocalExperiment"] )];
    [lines addObject:RYClassLine(@"FamilyLocalExperiment", @[@"FamilyLocalExperiment"] )];
    [lines addObject:[NSString stringWithFormat:@"Family subclass of Meta = %@", RYBool(meta && family && [family isSubclassOfClass:meta])]];
    [lines addObject:RYClassLine(@"LIDLocalExperiment", @[@"LIDLocalExperiment"] )];
    [lines addObject:[NSString stringWithFormat:@"LIDLocalExperiment subclass of Meta = %@", RYBool(meta && lidLocal && [lidLocal isSubclassOfClass:meta])]];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"LIDExperimentGenerator", @[@"LIDExperimentGenerator"] )];
    [lines addObject:RYMethodLine(@"-initWithDeviceID:logger:", lidGenerator, NSSelectorFromString(@"initWithDeviceID:logger:"), NO)];
    [lines addObject:RYMethodLine(@"-createLocalExperiment:", lidGenerator, NSSelectorFromString(@"createLocalExperiment:"), NO)];
    [lines addObject:RYClassLine(@"FDIDExperimentGenerator", @[@"FDIDExperimentGenerator"] )];
    [lines addObject:RYMethodLine(@"FDID -initWithDeviceID:logger:", fdidGenerator, NSSelectorFromString(@"initWithDeviceID:logger:"), NO)];
    [lines addObject:@""];
    [lines addObject:RYClassLine(@"MetaLocalExperimentListViewController", @[@"MetaLocalExperimentListViewController"] )];
    [lines addObject:RYMethodLine(@"-initWithExperimentConfigs:experimentGenerator:", listVC, NSSelectorFromString(@"initWithExperimentConfigs:experimentGenerator:"), NO)];
    return [lines componentsJoinedByString:@"\n"];
}

static NSString *RYCombinedSafeDiagnostics(void) {
    return [NSString stringWithFormat:@"%@\n\n%@", RYLocalExperimentCheckReport(), RYDogfoodingNativeCheckReport()];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;
    if (RYExpBrowserTab(self)) {
        return @[@"Open native LocalExperiment list", @"Safe runtime diagnostics", @"Dogfooding native check", @"Add MetaLocal override"];
    }
    return orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (RYExpBrowserTab(self)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (indexPath.row == 0) {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(openNativeBrowser));
        } else if (indexPath.row == 1) {
            ((void (*)(id, SEL, NSString *))objc_msgSend)(self, @selector(ry_presentRuntimeDiagnostics:), RYCombinedSafeDiagnostics());
        } else if (indexPath.row == 2) {
            ((void (*)(id, SEL, NSString *))objc_msgSend)(self, @selector(ry_presentRuntimeDiagnostics:), RYDogfoodingNativeCheckReport());
        } else {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(promptAddByName));
        }
        return;
    }
    %orig;
}

- (id)nativeBrowserGenerator {
    Class c = RYResolvedClass(@[@"LIDExperimentGenerator"]);
    if (!c) return %orig;
    SEL s = NSSelectorFromString(@"initWithDeviceID:logger:");
    if (![c instancesRespondToSelector:s]) return %orig;
    @try {
        return ((id (*)(id, SEL, id, id))objc_msgSend)([c alloc], s, nil, nil);
    } @catch (__unused id e) {
        return %orig;
    }
}

%new
- (void)ry_presentRuntimeDiagnostics:(NSString *)body {
    UIViewController *vc = [UIViewController new];
    vc.title = @"Runtime diagnostics";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.editable = NO;
    text.alwaysBounceVertical = YES;
    text.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    text.text = body ?: @"";
    [vc.view addSubview:text];

    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.topAnchor],
        [text.leadingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.leadingAnchor constant:8],
        [text.trailingAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.trailingAnchor constant:-8],
        [text.bottomAnchor constraintEqualToAnchor:vc.view.safeAreaLayoutGuide.bottomAnchor]
    ]];

    vc.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:nil action:nil];
    vc.navigationItem.rightBarButtonItem.primaryAction = [UIAction actionWithTitle:@"Copy" image:nil identifier:nil handler:^(__unused UIAction *action) {
        [UIPasteboard generalPasteboard].string = body ?: @"";
    }];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

%end
