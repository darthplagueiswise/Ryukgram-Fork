#import "SCIExpFlagsViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL RYExpBrowserTab(id self) {
    @try {
        UISegmentedControl *seg = [self valueForKey:@"seg"];
        return [seg isKindOfClass:[UISegmentedControl class]] && seg.selectedSegmentIndex == 0;
    } @catch (__unused id e) { return NO; }
}

static NSString *RYClassInfo(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) return [NSString stringWithFormat:@"%@ = missing", name];
    Class superCls = class_getSuperclass(cls);
    return [NSString stringWithFormat:@"%@ = found · superclass=%@ · UIViewController=%@",
            name,
            superCls ? NSStringFromClass(superCls) : @"nil",
            [cls isSubclassOfClass:[UIViewController class]] ? @"YES" : @"NO"];
}

static void RYAppendMethodNames(NSMutableArray<NSString *> *lines, Class cls, NSUInteger limit) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (sel) [names addObject:NSStringFromSelector(sel)];
    }
    if (methods) free(methods);
    [names sortUsingSelector:@selector(compare:)];
    NSUInteger n = MIN(limit, names.count);
    for (NSUInteger i = 0; i < n; i++) [lines addObject:[@"  - " stringByAppendingString:names[i]]];
    if (names.count > n) [lines addObject:[NSString stringWithFormat:@"  ... %lu more", (unsigned long)(names.count - n)]];
}

static NSString *RYExperimentRuntimeReport(void) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    Class family = NSClassFromString(@"FamilyLocalExperiment");
    Class meta = NSClassFromString(@"MetaLocalExperiment");
    Class lid = NSClassFromString(@"LIDExperimentGenerator");
    Class dog = NSClassFromString(@"IGDogfoodingSettingsViewController");
    [lines addObject:RYClassInfo(@"MetaLocalExperiment")];
    [lines addObject:RYClassInfo(@"FamilyLocalExperiment")];
    [lines addObject:[NSString stringWithFormat:@"Family subclass of Meta = %@", (family && meta && [family isSubclassOfClass:meta]) ? @"YES" : @"NO"]];
    [lines addObject:RYClassInfo(@"LIDLocalExperiment")];
    [lines addObject:RYClassInfo(@"LIDExperimentGenerator")];
    [lines addObject:RYClassInfo(@"FDIDExperimentGenerator")];
    [lines addObject:RYClassInfo(@"MetaLocalExperimentListViewController")];
    [lines addObject:RYClassInfo(@"MetaLocalExperimentDetailViewController")];
    [lines addObject:RYClassInfo(@"IGDogfoodingSettingsViewController")];
    [lines addObject:RYClassInfo(@"IGDogfoodingSettingsSelectionViewController")];
    [lines addObject:RYClassInfo(@"DogfoodingProductionLockoutViewController")];
    [lines addObject:[NSString stringWithFormat:@"LID initWithDeviceID:logger: = %@", (lid && [lid instancesRespondToSelector:NSSelectorFromString(@"initWithDeviceID:logger:")]) ? @"YES" : @"NO"]];
    [lines addObject:[NSString stringWithFormat:@"LID createLocalExperiment: = %@", (lid && [lid instancesRespondToSelector:NSSelectorFromString(@"createLocalExperiment:")]) ? @"YES" : @"NO"]];
    [lines addObject:@"\nLIDExperimentGenerator methods:"];
    RYAppendMethodNames(lines, lid, 50);
    [lines addObject:@"\nIGDogfoodingSettingsViewController methods:"];
    RYAppendMethodNames(lines, dog, 80);
    return [lines componentsJoinedByString:@"\n"];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;
    if (RYExpBrowserTab(self)) return @[@"Open native LocalExperiment list", @"Runtime diagnostics", @"Add MetaLocal override"];
    return orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (RYExpBrowserTab(self)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (indexPath.row == 0) ((void (*)(id, SEL))objc_msgSend)(self, @selector(openNativeBrowser));
        else if (indexPath.row == 1) ((void (*)(id, SEL, NSString *))objc_msgSend)(self, @selector(ry_presentRuntimeDiagnostics:), RYExperimentRuntimeReport());
        else ((void (*)(id, SEL))objc_msgSend)(self, @selector(promptAddByName));
        return;
    }
    %orig;
}

- (id)nativeBrowserGenerator {
    Class c = NSClassFromString(@"LIDExperimentGenerator");
    if (!c) c = objc_getClass("LIDExperimentGenerator");
    if (!c) return %orig;
    SEL s = NSSelectorFromString(@"initWithDeviceID:logger:");
    if (![c instancesRespondToSelector:s]) return %orig;
    @try { return ((id (*)(id, SEL, id, id))objc_msgSend)([c alloc], s, nil, nil); }
    @catch (__unused id e) { return %orig; }
}

%new
- (void)ry_presentRuntimeDiagnostics:(NSString *)body {
    UIViewController *vc = [UIViewController new];
    vc.title = @"Runtime diagnostics";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *text = [[UITextView alloc] initWithFrame:CGRectZero];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.editable = NO;
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
    vc.navigationItem.rightBarButtonItem.primaryAction = [UIAction actionWithTitle:@"Copy" image:nil identifier:nil handler:^(__unused UIAction *action) { [UIPasteboard generalPasteboard].string = body ?: @""; }];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

%end
