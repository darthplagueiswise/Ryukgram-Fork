#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *RGDFClassName(id obj) {
    if (!obj) return @"nil";
    return NSStringFromClass(object_getClass(obj));
}

static NSString *RGDFInstanceClassName(id obj) {
    if (!obj) return @"nil";
    return NSStringFromClass([obj class]);
}

static BOOL RGDFLooksLikeUserSession(id obj) {
    if (!obj) return NO;
    NSString *name = RGDFInstanceClassName(obj);
    return [name isEqualToString:@"IGUserSession"];
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

static NSString *RGDFStringFromObject(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:[NSString class]]) return obj;
    if ([obj respondsToSelector:@selector(stringValue)]) {
        @try { return [obj stringValue]; } @catch (__unused id e) { return nil; }
    }
    return nil;
}

static NSString *RGDFUserPkForSession(id session) {
    if (!session) return nil;

    NSArray<NSString *> *directSelectors = @[@"userPk", @"userPK", @"userID", @"userId", @"pk"];
    for (NSString *selName in directSelectors) {
        NSString *s = RGDFStringFromObject(RGDFSendId0(session, selName));
        if (s.length) return s;
    }

    id user = RGDFSendId0(session, @"user");
    if (!user) {
        Ivar iv = class_getInstanceVariable([session class], "_user");
        if (iv) {
            @try { user = object_getIvar(session, iv); } @catch (__unused id e) { user = nil; }
        }
    }

    for (NSString *selName in directSelectors) {
        NSString *s = RGDFStringFromObject(RGDFSendId0(user, selName));
        if (s.length) return s;
    }

    return nil;
}

static void RGDFAddObject(NSMutableArray *queue, NSHashTable *seen, id obj) {
    if (!obj) return;
    if (![obj isKindOfClass:[NSObject class]]) return;
    if ([seen containsObject:obj]) return;
    [seen addObject:obj];
    [queue addObject:obj];
}

static UIWindow *RGDFAnyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *fallback = nil;

    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (!fallback) fallback = window;
            if (window.isKeyWindow) return window;
        }
    }

    return fallback;
}

static UIViewController *RGDFTopViewControllerFrom(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;

    if ([cur isKindOfClass:[UINavigationController class]]) {
        return RGDFTopViewControllerFrom(((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController);
    }
    if ([cur isKindOfClass:[UITabBarController class]]) {
        return RGDFTopViewControllerFrom(((UITabBarController *)cur).selectedViewController);
    }
    return cur;
}

static UIViewController *RGDFPresenterFor(id fallback) {
    UIWindow *window = RGDFAnyWindow();
    UIViewController *vc = RGDFTopViewControllerFrom(window.rootViewController);
    if (vc) return vc;
    return [fallback isKindOfClass:[UIViewController class]] ? fallback : nil;
}

static id RGDFObjectIvar(id obj, Ivar iv) {
    if (!obj || !iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static BOOL RGDFShouldFollowIvarName(NSString *name) {
    if (!name.length) return NO;
    NSString *n = name.lowercaseString;
    return [n containsString:@"usersession"] ||
           [n containsString:@"sessionmanager"] ||
           [n containsString:@"activeusersessions"] ||
           [n containsString:@"appcoordinator"] ||
           [n containsString:@"mainapp"] ||
           [n containsString:@"tabbar"] ||
           [n containsString:@"root"] ||
           [n containsString:@"window"] ||
           [n containsString:@"delegate"] ||
           [n containsString:@"context"];
}

static id RGDFFindIGUserSessionNear(id seed, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];

    UIApplication *app = UIApplication.sharedApplication;
    RGDFAddObject(queue, seen, seed);
    RGDFAddObject(queue, seen, RGDFPresenterFor(seed));
    RGDFAddObject(queue, seen, RGDFAnyWindow());
    RGDFAddObject(queue, seen, app.delegate);

    UIWindow *window = RGDFAnyWindow();
    RGDFAddObject(queue, seen, window.rootViewController);

    NSUInteger cursor = 0;
    NSUInteger budget = 450;
    NSArray<NSString *> *selectors = @[
        @"userSession",
        @"igUserSession",
        @"currentUserSession",
        @"activeUserSession",
        @"session",
        @"mainAppViewController",
        @"rootViewController",
        @"selectedViewController",
        @"visibleViewController",
        @"topViewController",
        @"delegate"
    ];

    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        if (RGDFLooksLikeUserSession(obj)) {
            if (log) [log appendFormat:@"FOUND %@ <%p> userPk=%@\n", RGDFInstanceClassName(obj), obj, RGDFUserPkForSession(obj) ?: @"?"];
            return obj;
        }

        for (NSString *selName in selectors) {
            id child = RGDFSendId0(obj, selName);
            if (RGDFLooksLikeUserSession(child)) {
                if (log) [log appendFormat:@"%@.%@ -> %@ <%p> userPk=%@\n", RGDFInstanceClassName(obj), selName, RGDFInstanceClassName(child), child, RGDFUserPkForSession(child) ?: @"?"];
                return child;
            }
            RGDFAddObject(queue, seen, child);
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
            if (!RGDFShouldFollowIvarName(ivarName)) continue;
            id child = RGDFObjectIvar(obj, ivars[i]);
            if (RGDFLooksLikeUserSession(child)) {
                if (log) [log appendFormat:@"%@ ivar %@ -> %@ <%p> userPk=%@\n", RGDFInstanceClassName(obj), ivarName, RGDFInstanceClassName(child), child, RGDFUserPkForSession(child) ?: @"?"];
                if (ivars) free(ivars);
                return child;
            }
            RGDFAddObject(queue, seen, child);
        }
        if (ivars) free(ivars);
    }

    if (log) [log appendFormat:@"No IGUserSession found. visited=%lu\n", (unsigned long)seen.count];
    return nil;
}

static NSString *RGDFMethodListForClass(Class cls, BOOL meta) {
    if (!cls) return @"missing";
    Class target = meta ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        if (sel) [names addObject:NSStringFromSelector(sel)];
    }
    if (methods) free(methods);
    return names.count ? [names componentsJoinedByString:@", "] : @"none";
}

static void RGDFShowText(UIViewController *vc, NSString *title, NSString *text) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = text ?: @"";
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}

static Class RGDFClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) cls = objc_getClass(name.UTF8String);
    return cls;
}

static SEL RGDFClassSelector(Class cls, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        SEL sel = NSSelectorFromString(name);
        if (sel && [cls respondsToSelector:sel]) return sel;
    }
    return NULL;
}

static void RGDFOpenDirectNotesDogfood(UIViewController *source) {
    UIViewController *presenter = RGDFPresenterFor(source);
    NSMutableString *log = [NSMutableString stringWithString:@"Direct Notes dogfooding opener\n\n"];

    Class cls = RGDFClass(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
    [log appendFormat:@"class = %@\n", cls ? @"found" : @"missing"];

    NSArray<NSString *> *selectors = @[
        @"notesDogfoodingSettingsOpenOnViewController:userSession:",
        @"openOnViewController:userSession:",
        @"openWithViewController:userSession:",
        @"dogfoodingSettingsOpenOnViewController:userSession:",
        @"directNotesDogfoodingSettingsOpenOnViewController:userSession:"
    ];
    SEL sel = RGDFClassSelector(cls, selectors);
    [log appendFormat:@"method = %@\n", sel ? NSStringFromSelector(sel) : @"missing"];
    [log appendFormat:@"presenter = %@ <%p>\n", RGDFInstanceClassName(presenter), presenter];

    id session = RGDFFindIGUserSessionNear(presenter ?: source, log);
    [log appendFormat:@"userSession = %@ <%p> userPk=%@\n", RGDFInstanceClassName(session), session, RGDFUserPkForSession(session) ?: @"?"];

    if (!presenter || !cls || !sel || !session) {
        [log appendString:@"\nABORT: missing presenter, class, method, or userSession.\n"];
        RGDFShowText(source, @"Direct Notes Dogfood", log);
        return;
    }

    @try {
        void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        send(cls, sel, presenter, session);
        [log appendString:@"\nCALL OK: native Direct Notes dogfooding opener invoked.\n"];
        NSLog(@"[RyukGram][Dogfood] %@", log);
    } @catch (id e) {
        [log appendFormat:@"\nEXCEPTION: %@\n", e];
        RGDFShowText(source, @"Direct Notes Dogfood", log);
    }
}

static void RGDFShowSessionFinder(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"IGUserSession finder\n\n"];
    id session = RGDFFindIGUserSessionNear(RGDFPresenterFor(source) ?: source, log);
    if (session) {
        [log appendFormat:@"\nRESULT = %@ <%p>\nuserPk = %@\n", RGDFInstanceClassName(session), session, RGDFUserPkForSession(session) ?: @"?"];
    }
    RGDFShowText(source, @"IGUserSession", log);
}

static void RGDFShowDogfoodClassScan(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Dogfooding native check\nmode = safe class/method scan only; no alloc, no KVC, no hook\n\n"];

    NSArray<NSString *> *classes = @[
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
        Class cls = RGDFClass(name);
        [log appendFormat:@"%@ = %@", name, cls ? @"found" : @"missing"];
        if (cls) [log appendFormat:@" · superclass=%@", NSStringFromClass(class_getSuperclass(cls)) ?: @"nil"];
        [log appendString:@"\n"];
        if (cls) {
            [log appendFormat:@"  + %@\n", RGDFMethodListForClass(cls, YES)];
            [log appendFormat:@"  - %@\n", RGDFMethodListForClass(cls, NO)];
        }
    }

    RGDFShowText(source, @"Dogfood scan", log);
}

static BOOL RGDFIsExpFlagsBrowserTab(id vc) {
    @try {
        NSNumber *tab = [vc valueForKey:@"tab"];
        if ([tab respondsToSelector:@selector(integerValue)]) return tab.integerValue == 0;
    } @catch (__unused id e) {}

    @try {
        UISegmentedControl *seg = [vc valueForKey:@"seg"];
        if ([seg isKindOfClass:[UISegmentedControl class]]) return seg.selectedSegmentIndex == 0;
    } @catch (__unused id e) {}

    return NO;
}

static NSArray<NSString *> *RGDFDogfoodRows(void) {
    return @[
        @"Open Direct Notes Dogfood",
        @"Find IGUserSession",
        @"Dogfooding native check"
    ];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;
    if (!RGDFIsExpFlagsBrowserTab(self)) return orig;

    NSMutableArray *rows = [orig mutableCopy] ?: [NSMutableArray array];
    for (NSString *row in RGDFDogfoodRows()) {
        if (![rows containsObject:row]) [rows addObject:row];
    }
    return rows;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = nil;
    @try { rows = [self filteredRows]; } @catch (__unused id e) { rows = nil; }

    if (indexPath.row < rows.count) {
        id row = rows[(NSUInteger)indexPath.row];
        if ([row isKindOfClass:[NSString class]]) {
            NSString *title = (NSString *)row;
            if ([title isEqualToString:@"Open Direct Notes Dogfood"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFOpenDirectNotesDogfood((UIViewController *)self);
                return;
            }
            if ([title isEqualToString:@"Find IGUserSession"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFShowSessionFinder((UIViewController *)self);
                return;
            }
            if ([title isEqualToString:@"Dogfooding native check"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RGDFShowDogfoodClassScan((UIViewController *)self);
                return;
            }
        }
    }

    %orig(tableView, indexPath);
}

%end
