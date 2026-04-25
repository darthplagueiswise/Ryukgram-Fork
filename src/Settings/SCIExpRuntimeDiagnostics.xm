#import "SCIExpFlagsViewController.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static const unsigned long long RYDogGoldenAnchor = 0x0081008a00000122ULL; // 36310864701161762

static BOOL RYExpBrowserTab(id self) {
    @try {
        UISegmentedControl *seg = [self valueForKey:@"seg"];
        return [seg isKindOfClass:[UISegmentedControl class]] && seg.selectedSegmentIndex == 0;
    } @catch (__unused id e) {
        return NO;
    }
}

static Class RYResolvedClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (cls) return cls;

        cls = objc_getClass([name UTF8String]);
        if (cls) return cls;
    }

    return Nil;
}

static NSString *RYResolvedClassName(NSArray<NSString *> *names) {
    Class cls = RYResolvedClass(names);
    if (!cls) return @"missing";

    const char *cname = class_getName(cls);
    if (!cname) return NSStringFromClass(cls);

    return [NSString stringWithUTF8String:cname] ?: NSStringFromClass(cls);
}

static NSString *RYClassInfoForAliases(NSString *displayName, NSArray<NSString *> *aliases) {
    Class cls = RYResolvedClass(aliases);

    if (!cls) {
        return [NSString stringWithFormat:@"%@ = missing", displayName];
    }

    Class superCls = class_getSuperclass(cls);
    NSString *runtimeName = NSStringFromClass(cls);

    return [NSString stringWithFormat:@"%@ = found · runtime=%@ · superclass=%@ · UIViewController=%@",
            displayName,
            runtimeName ?: @"?",
            superCls ? NSStringFromClass(superCls) : @"nil",
            [cls isSubclassOfClass:[UIViewController class]] ? @"YES" : @"NO"];
}

static NSString *RYClassInfo(NSString *name) {
    return RYClassInfoForAliases(name, @[ name ]);
}

static void RYAppendMethodNames(NSMutableArray<NSString *> *lines, Class cls, BOOL meta, NSUInteger limit) {
    if (!cls) return;

    Class target = meta ? object_getClass(cls) : cls;

    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];

    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);

        if (sel) {
            NSString *line = [NSString stringWithFormat:@"%@ %@ types=%s",
                              meta ? @"+" : @"-",
                              NSStringFromSelector(sel),
                              types ?: "?"];
            [names addObject:line];
        }
    }

    if (methods) free(methods);

    [names sortUsingSelector:@selector(compare:)];

    NSUInteger n = MIN(limit, names.count);
    for (NSUInteger i = 0; i < n; i++) {
        [lines addObject:[@"  " stringByAppendingString:names[i]]];
    }

    if (names.count > n) {
        [lines addObject:[NSString stringWithFormat:@"  ... %lu more",
                          (unsigned long)(names.count - n)]];
    }
}

static NSArray<NSString *> *RYRuntimeClassesMatchingTokens(NSArray<NSString *> *tokens, BOOL viewControllersOnly) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSMutableArray<NSString *> *results = [NSMutableArray array];

    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        const char *cname = class_getName(cls);
        if (!cname) continue;

        NSString *name = [NSString stringWithUTF8String:cname];
        if (!name.length) continue;

        if (viewControllersOnly && ![cls isSubclassOfClass:[UIViewController class]]) {
            continue;
        }

        for (NSString *token in tokens) {
            if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [results addObject:name];
                break;
            }
        }
    }

    if (classes) free(classes);

    [results sortUsingSelector:@selector(compare:)];
    return results;
}

static id RYValueForKeyIfPossible(id obj, NSString *key) {
    if (!obj || !key.length) return nil;

    @try {
        id value = [obj valueForKey:key];
        if (value && value != [NSNull null]) return value;
    } @catch (__unused id e) {
    }

    return nil;
}

static id RYFindObjectByKeys(id root, NSArray<NSString *> *keys) {
    if (!root) return nil;

    for (NSString *key in keys) {
        id value = RYValueForKeyIfPossible(root, key);
        if (value) return value;
    }

    return nil;
}

static id RYFindUserSessionFromViewController(UIViewController *vc) {
    NSArray<NSString *> *sessionKeys = @[
        @"userSession",
        @"_userSession",
        @"currentUserSession",
        @"_currentUserSession",
        @"session",
        @"_session",
        @"igUserSession",
        @"_igUserSession"
    ];

    id direct = RYFindObjectByKeys(vc, sessionKeys);
    if (direct) return direct;

    UIViewController *cur = vc;
    while (cur) {
        id found = RYFindObjectByKeys(cur, sessionKeys);
        if (found) return found;

        id navFound = RYFindObjectByKeys(cur.navigationController, sessionKeys);
        if (navFound) return navFound;

        id tabFound = RYFindObjectByKeys(cur.tabBarController, sessionKeys);
        if (tabFound) return tabFound;

        cur = cur.parentViewController ?: cur.presentingViewController;
    }

    id delegate = UIApplication.sharedApplication.delegate;
    id delegateFound = RYFindObjectByKeys(delegate, sessionKeys);
    if (delegateFound) return delegateFound;

    NSArray<NSString *> *managerKeys = @[
        @"userSessionManager",
        @"_userSessionManager",
        @"sessionManager",
        @"_sessionManager",
        @"currentSessionManager",
        @"_currentSessionManager"
    ];

    id manager = RYFindObjectByKeys(delegate, managerKeys);
    id managerSession = RYFindObjectByKeys(manager, sessionKeys);
    if (managerSession) return managerSession;

    return nil;
}

static id RYCallClassMethod0(Class cls, SEL sel) {
    if (!cls || !sel) return nil;
    if (!class_getClassMethod(cls, sel)) return nil;

    @try {
        return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
    } @catch (__unused id e) {
        return nil;
    }
}

static id RYBuildDogfoodingConfig(void) {
    Class configClass = RYResolvedClass(@[
        @"IGDogfoodingSettingsConfig",
        @"IGDogfoodingSettings.IGDogfoodingSettingsConfig",
        @"_TtC20IGDogfoodingSettings25IGDogfoodingSettingsConfig"
    ]);

    if (!configClass) return nil;

    NSArray<NSString *> *factorySelectors = @[
        @"defaultConfig",
        @"config",
        @"sharedConfig",
        @"currentConfig",
        @"dogfoodingSettingsConfig"
    ];

    for (NSString *selName in factorySelectors) {
        id value = RYCallClassMethod0(configClass, NSSelectorFromString(selName));
        if (value) return value;
    }

    @try {
        if ([configClass instancesRespondToSelector:@selector(init)]) {
            return [[configClass alloc] init];
        }
    } @catch (__unused id e) {
        return nil;
    }

    return nil;
}

static NSString *RYDogfoodingOpenabilityReport(UIViewController *presenter) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    Class entry = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);

    Class vc = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController"
    ]);

    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");

    id config = RYBuildDogfoodingConfig();
    id userSession = RYFindUserSessionFromViewController(presenter);

    [lines addObject:@"Dogfooding openability"];
    [lines addObject:[NSString stringWithFormat:@"goldenAnchor = 0x%016llx / %llu",
                      RYDogGoldenAnchor,
                      RYDogGoldenAnchor]];

    [lines addObject:[NSString stringWithFormat:@"entryClass = %@",
                      entry ? NSStringFromClass(entry) : @"missing"]];

    [lines addObject:[NSString stringWithFormat:@"+openWithConfig:onViewController:userSession: = %@",
                      (entry && class_getClassMethod(entry, openSel)) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"viewControllerClass = %@",
                      vc ? NSStringFromClass(vc) : @"missing"]];

    [lines addObject:[NSString stringWithFormat:@"-initWithConfig:userSession: = %@",
                      (vc && [vc instancesRespondToSelector:initSel]) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"config = %@ <%@>",
                      config ? @"available" : @"nil",
                      config ? NSStringFromClass([config class]) : @"?"]];

    [lines addObject:[NSString stringWithFormat:@"userSession = %@ <%@>",
                      userSession ? @"available" : @"nil",
                      userSession ? NSStringFromClass([userSession class]) : @"?"]];

    return [lines componentsJoinedByString:@"\n"];
}

static NSString *RYExperimentRuntimeReport(void) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    Class family = NSClassFromString(@"FamilyLocalExperiment");
    Class meta = NSClassFromString(@"MetaLocalExperiment");
    Class lid = NSClassFromString(@"LIDExperimentGenerator");
    Class fdid = NSClassFromString(@"FDIDExperimentGenerator");

    Class dogEntry = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);

    Class dogVC = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController"
    ]);

    Class dogSelectionVC = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"_TtC20IGDogfoodingSettings43IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingSettingsSelectionViewController"
    ]);

    Class dogLockoutVC = RYResolvedClass(@[
        @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController",
        @"_TtC17IGDogfoodingFirst41DogfoodingProductionLockoutViewController",
        @"DogfoodingProductionLockoutViewController"
    ]);

    [lines addObject:@"LocalExperiment runtime diagnostics"];
    [lines addObject:@""];

    [lines addObject:RYClassInfo(@"MetaLocalExperiment")];
    [lines addObject:RYClassInfo(@"FamilyLocalExperiment")];

    [lines addObject:[NSString stringWithFormat:@"Family subclass of Meta = %@",
                      (family && meta && [family isSubclassOfClass:meta]) ? @"YES" : @"NO"]];

    [lines addObject:RYClassInfo(@"LIDLocalExperiment")];
    [lines addObject:RYClassInfo(@"LIDExperimentGenerator")];
    [lines addObject:RYClassInfo(@"FDIDExperimentGenerator")];

    [lines addObject:RYClassInfo(@"MetaLocalExperimentListViewController")];
    [lines addObject:RYClassInfo(@"MetaLocalExperimentDetailViewController")];

    [lines addObject:@""];

    [lines addObject:RYClassInfoForAliases(@"IGDogfoodingSettings entrypoint", @[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ])];

    [lines addObject:RYClassInfoForAliases(@"IGDogfoodingSettingsViewController", @[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController"
    ])];

    [lines addObject:RYClassInfoForAliases(@"IGDogfoodingSettingsSelectionViewController", @[
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"_TtC20IGDogfoodingSettings43IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingSettingsSelectionViewController"
    ])];

    [lines addObject:RYClassInfoForAliases(@"DogfoodingProductionLockoutViewController", @[
        @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController",
        @"_TtC17IGDogfoodingFirst41DogfoodingProductionLockoutViewController",
        @"DogfoodingProductionLockoutViewController"
    ])];

    [lines addObject:RYClassInfoForAliases(@"IGDogfoodingSettingsConfig", @[
        @"IGDogfoodingSettingsConfig",
        @"IGDogfoodingSettings.IGDogfoodingSettingsConfig",
        @"_TtC20IGDogfoodingSettings25IGDogfoodingSettingsConfig"
    ])];

    [lines addObject:RYClassInfoForAliases(@"IGDogfooderProd", @[
        @"IGDogfooderProd"
    ])];

    [lines addObject:RYClassInfoForAliases(@"IGDogfoodingLogger", @[
        @"IGDogfoodingLogger"
    ])];

    [lines addObject:@""];

    [lines addObject:[NSString stringWithFormat:@"goldenAnchor = 0x%016llx / %llu",
                      RYDogGoldenAnchor,
                      RYDogGoldenAnchor]];

    [lines addObject:[NSString stringWithFormat:@"LID initWithDeviceID:logger: = %@",
                      (lid && [lid instancesRespondToSelector:NSSelectorFromString(@"initWithDeviceID:logger:")]) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"LID createLocalExperiment: = %@",
                      (lid && [lid instancesRespondToSelector:NSSelectorFromString(@"createLocalExperiment:")]) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"FDID initWithDeviceID:logger: = %@",
                      (fdid && [fdid instancesRespondToSelector:NSSelectorFromString(@"initWithDeviceID:logger:")]) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"Dogfooding +openWithConfig:onViewController:userSession: = %@",
                      (dogEntry && class_getClassMethod(dogEntry, NSSelectorFromString(@"openWithConfig:onViewController:userSession:"))) ? @"YES" : @"NO"]];

    [lines addObject:[NSString stringWithFormat:@"Dogfooding VC -initWithConfig:userSession: = %@",
                      (dogVC && [dogVC instancesRespondToSelector:NSSelectorFromString(@"initWithConfig:userSession:")]) ? @"YES" : @"NO"]];

    [lines addObject:@""];

    [lines addObject:@"LIDExperimentGenerator methods:"];
    RYAppendMethodNames(lines, lid, NO, 80);

    [lines addObject:@""];

    [lines addObject:@"FDIDExperimentGenerator methods:"];
    RYAppendMethodNames(lines, fdid, NO, 80);

    [lines addObject:@""];

    [lines addObject:@"IGDogfoodingSettings entrypoint class methods:"];
    RYAppendMethodNames(lines, dogEntry, YES, 80);

    [lines addObject:@""];

    [lines addObject:@"IGDogfoodingSettingsViewController methods:"];
    RYAppendMethodNames(lines, dogVC, NO, 160);

    [lines addObject:@""];

    [lines addObject:@"IGDogfoodingSettingsSelectionViewController methods:"];
    RYAppendMethodNames(lines, dogSelectionVC, NO, 120);

    [lines addObject:@""];

    [lines addObject:@"DogfoodingProductionLockoutViewController methods:"];
    RYAppendMethodNames(lines, dogLockoutVC, NO, 80);

    NSArray<NSString *> *controllers = RYRuntimeClassesMatchingTokens(@[
        @"Experiment",
        @"Dogfood",
        @"Dogfooding",
        @"Employee",
        @"Internal",
        @"Developer",
        @"MobileConfig"
    ], YES);

    [lines addObject:@""];

    [lines addObject:[NSString stringWithFormat:@"Runtime ViewControllers matching Experiment/Dogfood/Employee/Internal/Developer/MobileConfig = %lu",
                      (unsigned long)controllers.count]];

    NSUInteger vcLimit = MIN((NSUInteger)180, controllers.count);
    for (NSUInteger i = 0; i < vcLimit; i++) {
        [lines addObject:[@"  + " stringByAppendingString:controllers[i]]];
    }

    if (controllers.count > vcLimit) {
        [lines addObject:[NSString stringWithFormat:@"  ... %lu more",
                          (unsigned long)(controllers.count - vcLimit)]];
    }

    NSArray<NSString *> *classes = RYRuntimeClassesMatchingTokens(@[
        @"Dogfood",
        @"Dogfooding",
        @"Employee",
        @"Internal",
        @"Developer"
    ], NO);

    [lines addObject:@""];

    [lines addObject:[NSString stringWithFormat:@"Runtime classes matching Dogfood/Employee/Internal/Developer = %lu",
                      (unsigned long)classes.count]];

    NSUInteger classLimit = MIN((NSUInteger)220, classes.count);
    for (NSUInteger i = 0; i < classLimit; i++) {
        [lines addObject:[@"  + " stringByAppendingString:classes[i]]];
    }

    if (classes.count > classLimit) {
        [lines addObject:[NSString stringWithFormat:@"  ... %lu more",
                          (unsigned long)(classes.count - classLimit)]];
    }

    return [lines componentsJoinedByString:@"\n"];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;

    if (RYExpBrowserTab(self)) {
        return @[
            @"Open native LocalExperiment list",
            @"Runtime diagnostics",
            @"Try native dogfooding settings",
            @"Add MetaLocal override"
        ];
    }

    return orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (RYExpBrowserTab(self)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        if (indexPath.row == 0) {
            ((void (*)(id, SEL))objc_msgSend)(self, @selector(openNativeBrowser));
        } else if (indexPath.row == 1) {
            ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                          @selector(ry_presentRuntimeDiagnostics:),
                                                          RYExperimentRuntimeReport());
        } else if (indexPath.row == 2) {
            ((void (*)(id, SEL))objc_msgSend)(self,
                                              @selector(ry_probeNativeDogfoodingSettings));
        } else {
            ((void (*)(id, SEL))objc_msgSend)(self,
                                              @selector(promptAddByName));
        }

        return;
    }

    %orig;
}

- (id)nativeBrowserGenerator {
    Class c = NSClassFromString(@"LIDExperimentGenerator");

    if (!c) {
        c = objc_getClass("LIDExperimentGenerator");
    }

    if (!c) {
        return %orig;
    }

    SEL s = NSSelectorFromString(@"initWithDeviceID:logger:");

    if (![c instancesRespondToSelector:s]) {
        return %orig;
    }

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

    vc.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Copy"
                                         style:UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];

    vc.navigationItem.rightBarButtonItem.primaryAction =
        [UIAction actionWithTitle:@"Copy"
                            image:nil
                       identifier:nil
                          handler:^(__unused UIAction *action) {
        [UIPasteboard generalPasteboard].string = body ?: @"";
    }];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;

    [self presentViewController:nav animated:YES completion:nil];
}

%new
- (void)ry_probeNativeDogfoodingSettings {
    UIViewController *presenter = (UIViewController *)self;

    Class entry = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"_TtC20IGDogfoodingSettings20IGDogfoodingSettings"
    ]);

    Class vcClass = RYResolvedClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController"
    ]);

    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    SEL initSel = NSSelectorFromString(@"initWithConfig:userSession:");

    id config = RYBuildDogfoodingConfig();
    id userSession = RYFindUserSessionFromViewController(presenter);

    if (!entry && !vcClass) {
        NSString *body = [NSString stringWithFormat:
            @"Dogfooding Settings classes are missing in this runtime.\n\n%@",
            RYExperimentRuntimeReport()
        ];

        ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                      @selector(ry_presentRuntimeDiagnostics:),
                                                      body);
        return;
    }

    if (!config || !userSession) {
        NSString *body = [NSString stringWithFormat:
            @"Dogfooding Settings exists, but required args are missing.\n\n%@\n\n%@",
            RYDogfoodingOpenabilityReport(presenter),
            RYExperimentRuntimeReport()
        ];

        ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                      @selector(ry_presentRuntimeDiagnostics:),
                                                      body);
        return;
    }

    if (entry && class_getClassMethod(entry, openSel)) {
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(entry,
                                                          openSel,
                                                          config,
                                                          presenter,
                                                          userSession);
            return;
        } @catch (id e) {
            NSString *body = [NSString stringWithFormat:
                @"+openWithConfig:onViewController:userSession: raised exception:\n%@\n\n%@\n\n%@",
                e,
                RYDogfoodingOpenabilityReport(presenter),
                RYExperimentRuntimeReport()
            ];

            ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                          @selector(ry_presentRuntimeDiagnostics:),
                                                          body);
            return;
        }
    }

    if (vcClass && [vcClass instancesRespondToSelector:initSel]) {
        UIViewController *vc = nil;

        @try {
            vc = ((id (*)(id, SEL, id, id))objc_msgSend)([vcClass alloc],
                                                         initSel,
                                                         config,
                                                         userSession);
        } @catch (id e) {
            NSString *body = [NSString stringWithFormat:
                @"-initWithConfig:userSession: raised exception:\n%@\n\n%@\n\n%@",
                e,
                RYDogfoodingOpenabilityReport(presenter),
                RYExperimentRuntimeReport()
            ];

            ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                          @selector(ry_presentRuntimeDiagnostics:),
                                                          body);
            return;
        }

        if (vc) {
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
            return;
        }
    }

    NSString *body = [NSString stringWithFormat:
        @"Dogfooding Settings classes exist, but no usable open/init selector was available.\n\n%@\n\n%@",
        RYDogfoodingOpenabilityReport(presenter),
        RYExperimentRuntimeReport()
    ];

    ((void (*)(id, SEL, NSString *))objc_msgSend)(self,
                                                  @selector(ry_presentRuntimeDiagnostics:),
                                                  body);
}

%end
