#import "TweakSettings.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray *(*orig_sections_dev_cleanup_dog)(id, SEL);
static __weak id RYDevDogCachedUserSession = nil;

static NSString *RYDevDogClass(id obj) {
    return obj ? (NSStringFromClass([obj class]) ?: @"?") : @"nil";
}

static NSString *RYDevDogPtr(id obj) {
    return obj ? [NSString stringWithFormat:@"%p", (__bridge void *)obj] : @"0x0";
}

static Class RYDevDogClassNamed(NSString *name) {
    if (!name.length) return Nil;
    Class cls = NSClassFromString(name);
    return cls ?: (Class)objc_getClass(name.UTF8String);
}

static id RYDevDogCall0(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(target, sel);
    } @catch (__unused id e) {
        return nil;
    }
}

static id RYDevDogObjectIvar(id target, Ivar ivar) {
    if (!target || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try {
        return object_getIvar(target, ivar);
    } @catch (__unused id e) {
        return nil;
    }
}

static BOOL RYDevDogLooksLikeUserSession(id obj) {
    if (!obj) return NO;
    NSString *name = RYDevDogClass(obj);
    return [name isEqualToString:@"IGUserSession"] || [name hasSuffix:@"IGUserSession"] || [name hasSuffix:@"UserSession"];
}

static id RYDevDogUserSessionFromObject(id obj) {
    if (!obj) return nil;
    if (RYDevDogLooksLikeUserSession(obj)) return obj;

    for (NSString *sel in @[@"userSession", @"igUserSession", @"currentUserSession", @"activeUserSession", @"mainUserSession", @"loggedInUserSession"]) {
        id value = RYDevDogCall0(obj, sel);
        if (RYDevDogLooksLikeUserSession(value)) return value;
    }

    for (const char *name in (const char *[]){"_userSession", "_igUserSession", "_currentUserSession", "_activeUserSession", "_mainUserSession", "_loggedInContext_userSession"}) {
        Class cls = [obj class];
        while (cls && cls != NSObject.class) {
            Ivar ivar = class_getInstanceVariable(cls, name);
            id value = RYDevDogObjectIvar(obj, ivar);
            if (RYDevDogLooksLikeUserSession(value)) return value;
            cls = class_getSuperclass(cls);
        }
    }

    return nil;
}

static UIViewController *RYDevDogTopViewControllerFrom(UIViewController *vc) {
    UIViewController *cur = vc;
    BOOL changed = YES;
    while (cur && changed) {
        changed = NO;
        if ([cur isKindOfClass:UINavigationController.class]) {
            UIViewController *next = ((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        if ([cur isKindOfClass:UITabBarController.class]) {
            UIViewController *next = ((UITabBarController *)cur).selectedViewController;
            if (next && next != cur) { cur = next; changed = YES; continue; }
        }
        UIViewController *presented = cur.presentedViewController;
        if (presented && presented != cur) { cur = presented; changed = YES; }
    }
    return cur;
}

static UIViewController *RYDevDogRootViewController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) return window.rootViewController;
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.rootViewController) return window.rootViewController;
        }
    }
    return nil;
}

static id RYDevDogFindUserSession(UIViewController *presenter) {
    if (RYDevDogLooksLikeUserSession(RYDevDogCachedUserSession)) return RYDevDogCachedUserSession;

    NSMutableArray *roots = [NSMutableArray array];
    if (presenter) [roots addObject:presenter];
    if (presenter.navigationController) [roots addObject:presenter.navigationController];
    if (presenter.tabBarController) [roots addObject:presenter.tabBarController];
    if (presenter.view.window) [roots addObject:presenter.view.window];
    if (presenter.view.window.rootViewController) [roots addObject:presenter.view.window.rootViewController];
    UIViewController *root = RYDevDogRootViewController();
    if (root) [roots addObject:root];
    UIViewController *top = RYDevDogTopViewControllerFrom(root);
    if (top) [roots addObject:top];
    if (UIApplication.sharedApplication.delegate) [roots addObject:UIApplication.sharedApplication.delegate];

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            [roots addObject:window];
            if (window.rootViewController) [roots addObject:window.rootViewController];
        }
    }

    for (id obj in roots) {
        id session = RYDevDogUserSessionFromObject(obj);
        if (session) {
            RYDevDogCachedUserSession = session;
            return session;
        }
    }
    return nil;
}

static BOOL RYDevDogUsefulIvarName(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"dogfood"] || [n containsString:@"config"] || [n containsString:@"settings"] ||
           [n containsString:@"coordinator"] || [n containsString:@"session"] || [n containsString:@"mainapp"] ||
           [n containsString:@"tabbar"] || [n containsString:@"root"] || [n containsString:@"delegate"] ||
           [n containsString:@"context"];
}

static id RYDevDogFindLiveObjectNamed(UIViewController *presenter, NSString *className, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];

    void (^push)(id) = ^(id obj) {
        if (!obj || ![obj isKindOfClass:NSObject.class]) return;
        NSString *key = RYDevDogPtr(obj);
        if ([seen containsObject:key]) return;
        [seen addObject:key];
        [queue addObject:obj];
    };

    push(presenter);
    push(presenter.navigationController);
    push(presenter.tabBarController);
    push(presenter.view.window);
    push(presenter.view.window.rootViewController);
    push(RYDevDogRootViewController());
    push(UIApplication.sharedApplication.delegate);

    NSArray *selectors = @[@"config", @"settingsConfig", @"dogfoodingConfig", @"dogfoodingSettingsConfig", @"mainAppViewController", @"rootViewController", @"selectedViewController", @"visibleViewController", @"topViewController", @"delegate", @"appCoordinator", @"sessionManager"];
    NSUInteger cursor = 0;
    NSUInteger budget = 900;
    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        if ([RYDevDogClass(obj) isEqualToString:className]) {
            if (log) [log appendFormat:@"FOUND %@ <%@>\n", RYDevDogClass(obj), RYDevDogPtr(obj)];
            return obj;
        }
        for (NSString *sel in selectors) push(RYDevDogCall0(obj, sel));
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        if (ivars) {
            for (unsigned int i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
                if (!RYDevDogUsefulIvarName(name)) continue;
                id child = RYDevDogObjectIvar(obj, ivars[i]);
                if ([RYDevDogClass(child) isEqualToString:className]) {
                    if (log) [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@>\n", RYDevDogClass(obj), RYDevDogPtr(obj), name, RYDevDogClass(child), RYDevDogPtr(child)];
                    free(ivars);
                    return child;
                }
                push(child);
            }
            free(ivars);
        }
    }
    if (log) [log appendFormat:@"No %@ found. visited=%lu\n", className, (unsigned long)seen.count];
    return nil;
}

static void RYDevDogShowAlert(UIViewController *presenter, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = RYDevDogTopViewControllerFrom(presenter ?: RYDevDogRootViewController());
        if (!top) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title ?: @"Dogfooding" message:message ?: @"" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:alert animated:YES completion:nil];
    });
}

static void RYDevDogOpenDirectNotes(void) {
    UIViewController *presenter = RYDevDogTopViewControllerFrom(RYDevDogRootViewController());
    id userSession = RYDevDogFindUserSession(presenter);
    Class notesClass = RYDevDogClassNamed(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
    SEL notesSel = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");

    if (!presenter || !userSession || !notesClass || ![notesClass respondsToSelector:notesSel]) {
        RYDevDogShowAlert(presenter, @"Dogfooding Notes", [NSString stringWithFormat:@"ABORT\npresenter=%@ <%@>\nuserSession=%@ <%@>\nclass=%@\nmethod=%@", RYDevDogClass(presenter), RYDevDogPtr(presenter), RYDevDogClass(userSession), RYDevDogPtr(userSession), notesClass ? NSStringFromClass(notesClass) : @"missing", (notesClass && [notesClass respondsToSelector:notesSel]) ? @"YES" : @"NO"]);
        return;
    }

    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)((id)notesClass, notesSel, presenter, userSession);
    } @catch (id e) {
        RYDevDogShowAlert(presenter, @"Dogfooding Notes", [NSString stringWithFormat:@"EXCEPTION: %@", e]);
    }
}

static void RYDevDogOpenMain(void) {
    UIViewController *presenter = RYDevDogTopViewControllerFrom(RYDevDogRootViewController());
    id userSession = RYDevDogFindUserSession(presenter);
    Class entryClass = RYDevDogClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettings");
    SEL openSel = NSSelectorFromString(@"openWithConfig:onViewController:userSession:");
    NSMutableString *configLog = [NSMutableString string];
    id config = RYDevDogFindLiveObjectNamed(presenter, @"IGDogfoodingSettingsConfig", configLog);

    if (!presenter || !userSession || !entryClass || ![entryClass respondsToSelector:openSel] || !config) {
        RYDevDogShowAlert(presenter, @"Main Dogfood Settings", [NSString stringWithFormat:@"ABORT\npresenter=%@ <%@>\nuserSession=%@ <%@>\nentry=%@ method=%@\nconfig=%@ <%@>\n\nconfig search:\n%@\n\nSem alloc/init fake; o fluxo principal ainda precisa de config nativo vivo.", RYDevDogClass(presenter), RYDevDogPtr(presenter), RYDevDogClass(userSession), RYDevDogPtr(userSession), entryClass ? NSStringFromClass(entryClass) : @"missing", (entryClass && [entryClass respondsToSelector:openSel]) ? @"YES" : @"NO", RYDevDogClass(config), RYDevDogPtr(config), configLog]);
        return;
    }

    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)((id)entryClass, openSel, config, presenter, userSession);
    } @catch (id e) {
        RYDevDogShowAlert(presenter, @"Main Dogfood Settings", [NSString stringWithFormat:@"EXCEPTION: %@", e]);
    }
}

static BOOL RYDevSettingTitleMatches(SCISetting *setting, NSArray<NSString *> *titles) {
    if (![setting isKindOfClass:[SCISetting class]]) return NO;
    NSString *title = setting.title ?: @"";
    for (NSString *needle in titles) {
        if ([title isEqualToString:needle]) return YES;
    }
    return NO;
}

static NSArray *RYDevFilteredRuntimeRows(NSArray *rows) {
    if (![rows isKindOfClass:[NSArray class]]) return rows;
    NSMutableArray *clean = [NSMutableArray array];
    NSArray *legacy = @[@"Patch MCQMEM CQL bool", @"Patch MEM Capability bool", @"Patch MEM DevConfig bool", @"Patch MEM Platform bool", @"Patch MEM Protocol bool"];
    for (id row in rows) {
        SCISetting *setting = [row isKindOfClass:[SCISetting class]] ? row : nil;
        if (setting && RYDevSettingTitleMatches(setting, legacy)) continue;
        [clean addObject:row];
    }
    return clean;
}

static BOOL RYDevSectionHeaderIs(NSDictionary *section, NSString *header) {
    NSString *h = [section[@"header"] isKindOfClass:[NSString class]] ? section[@"header"] : @"";
    return [h isEqualToString:header];
}

static NSDictionary *RYDevDogfoodOpenersSection(void) {
    return @{
        @"header": @"Dogfood native openers",
        @"footer": @"Direct Notes uses its native facade and should open. Main Dogfood attempts the native openWithConfig path and refuses fake config to avoid the crash path.",
        @"rows": @[
            [SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood"
                                   subtitle:@"Calls IGDirectNotesDogfoodingSettings native opener with live IGUserSession"
                                       icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                     action:^{ RYDevDogOpenDirectNotes(); }],
            [SCISetting buttonCellWithTitle:@"Try Main Dogfood Settings"
                                   subtitle:@"Attempts IGDogfoodingSettings.openWithConfig using live config + live IGUserSession"
                                       icon:[SCISymbol symbolWithName:@"pawprint.circle"]
                                     action:^{ RYDevDogOpenMain(); }]
        ]
    };
}

static BOOL RYDevHasSection(NSArray *sections, NSString *header) {
    for (id obj in sections) {
        NSDictionary *section = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        if (section && RYDevSectionHeaderIs(section, header)) return YES;
    }
    return NO;
}

static NSArray *RYDevCleanAndAddDogfoodToNavSections(NSArray *navSections) {
    if (![navSections isKindOfClass:[NSArray class]]) return navSections;
    NSMutableArray *out = [NSMutableArray array];
    BOOL dogAdded = NO;

    for (NSDictionary *section in navSections) {
        if (![section isKindOfClass:[NSDictionary class]]) {
            [out addObject:section];
            continue;
        }

        if (!dogAdded && RYDevSectionHeaderIs(section, @"Flags Browser")) {
            if (!RYDevHasSection(navSections, @"Dogfood native openers")) [out addObject:RYDevDogfoodOpenersSection()];
            dogAdded = YES;
        }

        NSMutableDictionary *newSection = [section mutableCopy];
        if (RYDevSectionHeaderIs(section, @"Runtime MC symbols")) {
            newSection[@"rows"] = RYDevFilteredRuntimeRows(section[@"rows"]);
            newSection[@"footer"] = @"Master Runtime MC true patcher must also be ON. Only symbols confirmed/relevant in 426 are shown here; legacy MEM 411 rows are hidden.";
        }
        [out addObject:newSection];
    }

    if (!dogAdded && !RYDevHasSection(navSections, @"Dogfood native openers")) [out addObject:RYDevDogfoodOpenersSection()];
    return out;
}

static NSArray *RYDevSectionsCleanAndDogfood(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]]) return sections;
    NSMutableArray *outSections = [sections mutableCopy];
    for (NSUInteger s = 0; s < outSections.count; s++) {
        NSDictionary *section = [outSections[s] isKindOfClass:[NSDictionary class]] ? outSections[s] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changed = NO;
        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *setting = [newRows[r] isKindOfClass:[SCISetting class]] ? newRows[r] : nil;
            if (!setting || ![setting.title isEqualToString:@"DEV tests"]) continue;
            NSArray *oldNav = [setting.navSections isKindOfClass:[NSArray class]] ? setting.navSections : @[];
            NSArray *newNav = RYDevCleanAndAddDogfoodToNavSections(oldNav);
            setting.navSections = newNav;
            newRows[r] = setting;
            changed = YES;
        }

        if (changed) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            outSections[s] = newSection;
        }
    }
    return outSections;
}

static NSArray *new_sections_dev_cleanup_dog(id self, SEL _cmd) {
    NSArray *orig = orig_sections_dev_cleanup_dog ? orig_sections_dev_cleanup_dog(self, _cmd) : @[];
    return RYDevSectionsCleanAndDogfood(orig);
}

__attribute__((constructor))
static void RYDevCleanupDogMSHookInit(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_dev_cleanup_dog, (IMP *)&orig_sections_dev_cleanup_dog);
}
