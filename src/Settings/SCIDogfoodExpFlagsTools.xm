#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSArray *(*RGDFOrigFilteredRows)(id self, SEL _cmd);
static void (*RGDFOrigDidSelect)(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath);
static BOOL RGDFSwizzled = NO;

static NSString *RGDFPointer(id obj) {
    if (!obj) return @"0x0";
    return [NSString stringWithFormat:@"%p", (__bridge void *)obj];
}

static NSString *RGDFClassName(id obj) {
    return obj ? NSStringFromClass([obj class]) : @"nil";
}

static Class RGDFRuntimeClass(NSString *name) {
    if (!name.length) return Nil;
    Class cls = NSClassFromString(name);
    if (!cls) cls = (Class)objc_getClass(name.UTF8String);
    return cls;
}

static id RGDFSendId0(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    @try {
        id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return send(target, sel);
    } @catch (__unused id e) {
        return nil;
    }
}

static NSString *RGDFStringValue(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:[NSString class]]) return (NSString *)obj;
    if ([obj respondsToSelector:@selector(stringValue)]) {
        @try { return [(id)obj stringValue]; } @catch (__unused id e) { return nil; }
    }
    return nil;
}

static id RGDFObjectIvar(id obj, Ivar ivar) {
    if (!obj || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(obj, ivar); } @catch (__unused id e) { return nil; }
}

static NSString *RGDFUserPk(id obj) {
    if (!obj) return nil;

    NSArray *selectors = @[@"userPk", @"userPK", @"userId", @"userID", @"pk"];
    for (NSString *selName in selectors) {
        NSString *value = RGDFStringValue(RGDFSendId0(obj, selName));
        if (value.length) return value;
    }

    id user = RGDFSendId0(obj, @"user");
    if (!user) {
        Ivar ivar = class_getInstanceVariable([obj class], "_user");
        user = RGDFObjectIvar(obj, ivar);
    }

    for (NSString *selName in selectors) {
        NSString *value = RGDFStringValue(RGDFSendId0(user, selName));
        if (value.length) return value;
    }

    Ivar pkIvar = class_getInstanceVariable([obj class], "_userPK");
    NSString *pk = RGDFStringValue(RGDFObjectIvar(obj, pkIvar));
    return pk.length ? pk : nil;
}

static BOOL RGDFIsUserSession(id obj) {
    return obj && [RGDFClassName(obj) isEqualToString:@"IGUserSession"];
}

static void RGDFAppendFound(NSMutableString *log, NSString *prefix, id obj) {
    if (!log || !obj) return;
    NSString *pk = RGDFUserPk(obj);
    [log appendFormat:@"%@%@ <%@>%@\n", prefix ?: @"", RGDFClassName(obj), RGDFPointer(obj), pk.length ? [NSString stringWithFormat:@" · userPk=%@", pk] : @""];
}

static BOOL RGDFIvarNameLooksUseful(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    return [n containsString:@"usersession"] ||
           [n containsString:@"sessions"] ||
           [n containsString:@"sessionmanager"] ||
           [n containsString:@"activeusersessions"] ||
           [n containsString:@"mainapp"] ||
           [n containsString:@"appcoordinator"] ||
           [n containsString:@"tabbar"] ||
           [n containsString:@"window"] ||
           [n containsString:@"root"] ||
           [n containsString:@"delegate"] ||
           [n containsString:@"context"] ||
           [n containsString:@"launcher"] ||
           [n containsString:@"feed"] ||
           [n containsString:@"story"];
}

static void RGDFQueueObject(NSMutableArray *queue, NSHashTable *seen, id obj) {
    if (!obj) return;
    if (![obj isKindOfClass:[NSObject class]]) return;
    if ([seen containsObject:obj]) return;
    [seen addObject:obj];
    [queue addObject:obj];
}

static UIWindow *RGDFWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *fallback = nil;
    for (UIWindow *window in app.windows) {
        if (!fallback) fallback = window;
        if (window.isKeyWindow) return window;
    }
    return fallback;
}

static UIViewController *RGDFTopViewController(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;
    if ([cur isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)cur;
        return RGDFTopViewController(nav.visibleViewController ?: nav.topViewController);
    }
    if ([cur isKindOfClass:[UITabBarController class]]) {
        return RGDFTopViewController(((UITabBarController *)cur).selectedViewController);
    }
    return cur;
}

static UIViewController *RGDFPresenter(id fallback) {
    UIViewController *vc = RGDFTopViewController(RGDFWindow().rootViewController);
    if (vc) return vc;
    return [fallback isKindOfClass:[UIViewController class]] ? (UIViewController *)fallback : nil;
}

static id RGDFFindUserSession(id seed, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSMutableArray *candidates = [NSMutableArray array];

    [log appendString:@"IGUserSession finder\n"];
    [log appendString:@"mode = root + view-controller tree + known singleton selectors + limited ivar scan\n"];
    [log appendString:@"goal = find real IGUserSession object; IGDeviceSession is not enough\n\n"];

    Class mgrClass = RGDFRuntimeClass(@"IGUserSessionManager");
    if (mgrClass) {
        [log appendString:@"singleton class IGUserSessionManager found\n"];
        NSArray *mgrSelectors = @[@"sharedInstance", @"sharedManager", @"currentSessionManager", @"instance"];
        for (NSString *selName in mgrSelectors) RGDFQueueObject(queue, seen, RGDFSendId0((id)mgrClass, selName));
    }

    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *window = RGDFWindow();
    UIViewController *presenter = RGDFPresenter(seed);
    RGDFQueueObject(queue, seen, seed);
    RGDFQueueObject(queue, seen, presenter);
    RGDFQueueObject(queue, seen, window);
    RGDFQueueObject(queue, seen, window.rootViewController);
    RGDFQueueObject(queue, seen, app.delegate);

    NSArray *selectors = @[
        @"userSession", @"igUserSession", @"currentUserSession", @"activeUserSession",
        @"mainAppViewController", @"rootViewController", @"selectedViewController", @"visibleViewController",
        @"topViewController", @"delegate", @"appCoordinator", @"sessionManager", @"activeUserSessions"
    ];

    NSUInteger cursor = 0;
    NSUInteger budget = 700;
    id firstSession = nil;

    while (cursor < [queue count] && budget > 0) {
        budget--;
        id obj = queue[cursor];
        cursor++;

        if (RGDFIsUserSession(obj)) {
            if (!firstSession) firstSession = obj;
            if (![candidates containsObject:obj]) [candidates addObject:obj];
        }

        for (NSString *selName in selectors) {
            id child = RGDFSendId0(obj, selName);
            if (!child) continue;
            if (RGDFIsUserSession(child)) {
                if (!firstSession) firstSession = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                [log appendFormat:@"%@ <%@>.%@ -> ", RGDFClassName(obj), RGDFPointer(obj), selName];
                RGDFAppendFound(log, @"", child);
            }
            RGDFQueueObject(queue, seen, child);
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
            if (!RGDFIvarNameLooksUseful(name)) continue;
            id child = RGDFObjectIvar(obj, ivars[i]);
            if (!child) continue;
            NSString *pk = RGDFUserPk(child);
            if (RGDFIsUserSession(child)) {
                if (!firstSession) firstSession = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                [log appendFormat:@"%@ <%@> ivar %@ -> ", RGDFClassName(obj), RGDFPointer(obj), name];
                RGDFAppendFound(log, @"", child);
            } else if (pk.length) {
                [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RGDFClassName(obj), RGDFPointer(obj), name, RGDFClassName(child), RGDFPointer(child), pk];
            }
            RGDFQueueObject(queue, seen, child);
        }
        if (ivars) free(ivars);
    }

    [log appendFormat:@"deepScan budgetRemaining=%lu visited=%lu candidates=%lu\n\n", (unsigned long)budget, (unsigned long)[seen allObjects].count, (unsigned long)candidates.count];
    [log appendFormat:@"RESULT: %lu IGUserSession candidate(s)\n", (unsigned long)candidates.count];
    for (NSUInteger i = 0; i < candidates.count; i++) {
        id obj = candidates[i];
        [log appendFormat:@"candidate[%lu] = %@ <%@> · userPk=%@\n", (unsigned long)i, RGDFClassName(obj), RGDFPointer(obj), RGDFUserPk(obj) ?: @"?"];
    }

    [log appendString:@"\nFlex cross-check:\n"];
    [log appendString:@"Good: IGSessionContext with _loggedInContext_userSession = <IGUserSession: 0x...>\n"];
    [log appendString:@"Good: direct IGUserSession object with userPk matching your account.\n"];
    [log appendString:@"Bad: only IGDeviceSession / _loggedOutContext_deviceSession.\n"];
    [log appendString:@"The numeric userPk confirms the account, but the opener needs the live object pointer.\n"];

    return firstSession;
}

static void RGDFShowText(UIViewController *source, NSString *title, NSString *body) {
    UIViewController *presenter = RGDFPresenter(source) ?: source;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = body ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static SEL RGDFClassSelector(Class cls, NSArray *names) {
    if (!cls) return NULL;
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if ([cls respondsToSelector:sel]) return sel;
    }
    return NULL;
}

static NSString *RGDFMethodNames(Class cls, BOOL meta) {
    if (!cls) return @"missing";
    Class target = meta ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (sel) [names addObject:NSStringFromSelector(sel)];
    }
    if (methods) free(methods);
    return names.count ? [names componentsJoinedByString:@", "] : @"none";
}

static void RGDFOpenDirectNotes(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Try Direct Notes dogfooding opener\nmode = best effort opener\n\n"];
    UIViewController *presenter = RGDFPresenter(source);
    Class cls = RGDFRuntimeClass(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
    SEL sel = RGDFClassSelector(cls, @[
        @"notesDogfoodingSettingsOpenOnViewController:userSession:",
        @"openOnViewController:userSession:",
        @"openWithViewController:userSession:",
        @"dogfoodingSettingsOpenOnViewController:userSession:",
        @"directNotesDogfoodingSettingsOpenOnViewController:userSession:"
    ]);

    [log appendFormat:@"directNotesClass = %@\n", cls ? NSStringFromClass(cls) : @"missing"];
    [log appendFormat:@"method = %@\n", sel ? NSStringFromSelector(sel) : @"NO"];
    [log appendFormat:@"viewController = %@ <%@>\n", RGDFClassName(presenter), RGDFPointer(presenter)];

    NSMutableString *sessionLog = [NSMutableString string];
    id session = RGDFFindUserSession(presenter ?: source, sessionLog);
    [log appendFormat:@"selectedUserSession = %@ <%@> · userPk=%@\n", RGDFClassName(session), RGDFPointer(session), RGDFUserPk(session) ?: @"?"];

    if (!presenter || !cls || !sel || !session) {
        [log appendString:@"\nABORT: missing UIViewController, class, method, or userSession.\n\n"];
        [log appendString:sessionLog];
        RGDFShowText(source, @"Direct Notes Dogfood", log);
        return;
    }

    @try {
        void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        send((id)cls, sel, presenter, session);
        NSLog(@"[RyukGram][Dogfood] opened Direct Notes dogfooding with %@", RGDFPointer(session));
    } @catch (id e) {
        [log appendFormat:@"\nEXCEPTION: %@\n", e];
        RGDFShowText(source, @"Direct Notes Dogfood", log);
    }
}

static void RGDFShowFinder(UIViewController *source) {
    NSMutableString *log = [NSMutableString string];
    (void)RGDFFindUserSession(source, log);
    RGDFShowText(source, @"IGUserSession finder", log);
}

static void RGDFShowNativeCheck(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Dogfooding native check\nmode = safe check only; no alloc, no KVC, no method invocation\n\n"];
    NSArray *classes = @[
        @"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs",
        @"IGDogfoodingSettings.IGDogfoodingSettings",
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController",
        @"IGDogfoodingSettingsConfig",
        @"IGDogfooderProd",
        @"IGDogfoodingLogger",
        @"DogfoodingEligibilityQueryBuilder",
        @"IGDogfoodingFirst.DogfoodingFirstCoordinator"
    ];

    for (NSString *name in classes) {
        Class cls = RGDFRuntimeClass(name);
        [log appendFormat:@"%@ = %@", name, cls ? @"found" : @"missing"];
        if (cls) [log appendFormat:@" · runtime=%@ · superclass=%@", NSStringFromClass(cls), NSStringFromClass(class_getSuperclass(cls)) ?: @"nil"];
        [log appendString:@"\n"];
        if (cls) {
            [log appendFormat:@"  + %@\n", RGDFMethodNames(cls, YES)];
            [log appendFormat:@"  - %@\n", RGDFMethodNames(cls, NO)];
        }
    }
    RGDFShowText(source, @"Dogfooding native check", log);
}

static BOOL RGDFIsBrowserTab(id vc) {
    @try {
        NSNumber *tab = [vc valueForKey:@"tab"];
        if ([tab respondsToSelector:@selector(integerValue)]) return [tab integerValue] == 0;
    } @catch (__unused id e) {}
    return NO;
}

static NSArray *RGDFRows(void) {
    return @[
        @"Open Direct Notes Dogfood",
        @"Find IGUserSession",
        @"Dogfooding native check"
    ];
}

static NSArray *RGDFFilteredRows(id self, SEL _cmd) {
    NSArray *orig = RGDFOrigFilteredRows ? RGDFOrigFilteredRows(self, _cmd) : @[];
    if (!RGDFIsBrowserTab(self)) return orig;
    NSMutableArray *rows = [orig mutableCopy] ?: [NSMutableArray array];
    for (NSString *row in RGDFRows()) {
        if (![rows containsObject:row]) [rows addObject:row];
    }
    return rows;
}

static void RGDFDidSelect(id self, SEL _cmd, UITableView *tableView, NSIndexPath *indexPath) {
    NSArray *rows = RGDFFilteredRows(self, NSSelectorFromString(@"filteredRows"));
    NSUInteger rowIndex = (NSUInteger)indexPath.row;
    if (rowIndex < rows.count) {
        id row = rows[rowIndex];
        if ([row isKindOfClass:[NSString class]]) {
            NSString *title = (NSString *)row;
            if ([title isEqualToString:@"Open Direct Notes Dogfood"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFOpenDirectNotes((UIViewController *)self);
                return;
            }
            if ([title isEqualToString:@"Find IGUserSession"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFShowFinder((UIViewController *)self);
                return;
            }
            if ([title isEqualToString:@"Dogfooding native check"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFShowNativeCheck((UIViewController *)self);
                return;
            }
        }
    }

    if (RGDFOrigDidSelect) RGDFOrigDidSelect(self, _cmd, tableView, indexPath);
}

static void RGDFInstallExpFlagsSwizzle(void) {
    if (RGDFSwizzled) return;
    Class cls = RGDFRuntimeClass(@"SCIExpFlagsViewController");
    if (!cls) return;

    Method filtered = class_getInstanceMethod(cls, NSSelectorFromString(@"filteredRows"));
    Method didSelect = class_getInstanceMethod(cls, @selector(tableView:didSelectRowAtIndexPath:));
    if (!filtered || !didSelect) return;

    RGDFOrigFilteredRows = (NSArray *(*)(id, SEL))method_getImplementation(filtered);
    RGDFOrigDidSelect = (void (*)(id, SEL, UITableView *, NSIndexPath *))method_getImplementation(didSelect);
    method_setImplementation(filtered, (IMP)RGDFFilteredRows);
    method_setImplementation(didSelect, (IMP)RGDFDidSelect);
    RGDFSwizzled = YES;
}

__attribute__((constructor))
static void RGDFCtor(void) {
    @autoreleasepool {
        RGDFInstallExpFlagsSwizzle();
        dispatch_async(dispatch_get_main_queue(), ^{
            RGDFInstallExpFlagsSwizzle();
        });
    }
}
