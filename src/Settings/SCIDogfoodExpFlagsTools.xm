#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *RYDogPtr(id obj) {
    return obj ? [NSString stringWithFormat:@"%p", (__bridge void *)obj] : @"0x0";
}

static NSString *RYDogClassName(id obj) {
    return obj ? NSStringFromClass([obj class]) : @"nil";
}

static Class RYDogClass(NSString *name) {
    if (!name.length) return Nil;
    Class cls = NSClassFromString(name);
    if (!cls) cls = (Class)objc_getClass(name.UTF8String);
    return cls;
}

static BOOL RYDogResponds(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return NO;
    return [target respondsToSelector:NSSelectorFromString(selectorName)];
}

static id RYDogCall0(id target, NSString *selectorName) {
    if (!RYDogResponds(target, selectorName)) return nil;
    @try {
        id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        return send(target, NSSelectorFromString(selectorName));
    } @catch (__unused id e) {
        return nil;
    }
}

static NSString *RYDogStringValue(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:[NSString class]]) return (NSString *)obj;
    if ([obj respondsToSelector:@selector(stringValue)]) {
        @try { return [(id)obj stringValue]; } @catch (__unused id e) { return nil; }
    }
    return nil;
}

static id RYDogObjectIvar(id obj, Ivar ivar) {
    if (!obj || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(obj, ivar); } @catch (__unused id e) { return nil; }
}

static NSString *RYDogUserPk(id obj) {
    if (!obj) return nil;

    NSArray *selectors = @[@"userPk", @"userPK", @"userId", @"userID", @"pk"];
    for (NSString *selectorName in selectors) {
        NSString *value = RYDogStringValue(RYDogCall0(obj, selectorName));
        if (value.length) return value;
    }

    id user = RYDogCall0(obj, @"user");
    if (!user) user = RYDogObjectIvar(obj, class_getInstanceVariable([obj class], "_user"));

    for (NSString *selectorName in selectors) {
        NSString *value = RYDogStringValue(RYDogCall0(user, selectorName));
        if (value.length) return value;
    }

    NSString *ivarPk = RYDogStringValue(RYDogObjectIvar(obj, class_getInstanceVariable([obj class], "_userPK")));
    return ivarPk.length ? ivarPk : nil;
}

static BOOL RYDogIsUserSession(id obj) {
    return obj && [RYDogClassName(obj) isEqualToString:@"IGUserSession"];
}

static void RYDogAppendObject(NSMutableArray *queue, NSMutableSet *seen, id obj) {
    if (!obj) return;
    if (![obj isKindOfClass:[NSObject class]]) return;
    NSString *key = RYDogPtr(obj);
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [queue addObject:obj];
}

static UIWindow *RYDogKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *fallback = nil;

    NSSet *scenes = app.connectedScenes;
    for (UIScene *scene in scenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (!fallback) fallback = window;
            if (window.isKeyWindow) return window;
        }
    }

    return fallback;
}

static UIViewController *RYDogTopViewController(UIViewController *vc) {
    UIViewController *current = vc;
    while (current.presentedViewController) current = current.presentedViewController;

    if ([current isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)current;
        return RYDogTopViewController(nav.visibleViewController ?: nav.topViewController);
    }

    if ([current isKindOfClass:[UITabBarController class]]) {
        return RYDogTopViewController(((UITabBarController *)current).selectedViewController);
    }

    return current;
}

static UIViewController *RYDogPresenter(id fallback) {
    UIViewController *vc = RYDogTopViewController(RYDogKeyWindow().rootViewController);
    if (vc) return vc;
    return [fallback isKindOfClass:[UIViewController class]] ? (UIViewController *)fallback : nil;
}

static BOOL RYDogUsefulIvarName(NSString *name) {
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

static void RYDogAppendSessionLine(NSMutableString *log, NSString *prefix, id obj) {
    if (!obj) return;
    NSString *pk = RYDogUserPk(obj);
    [log appendFormat:@"%@%@ <%@>%@\n", prefix ?: @"", RYDogClassName(obj), RYDogPtr(obj), pk.length ? [NSString stringWithFormat:@" · userPk=%@", pk] : @""];
}

static id RYDogFindUserSession(id seed, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *candidates = [NSMutableArray array];

    if (log) {
        [log appendString:@"IGUserSession finder\n"];
        [log appendString:@"mode = root + view-controller tree + known singleton selectors + limited ivar scan\n"];
        [log appendString:@"goal = find real IGUserSession object; IGDeviceSession is not enough\n\n"];
    }

    Class managerClass = RYDogClass(@"IGUserSessionManager");
    if (managerClass) {
        if (log) [log appendString:@"singleton class IGUserSessionManager found\n"];
        for (NSString *selectorName in @[@"sharedInstance", @"sharedManager", @"currentSessionManager", @"instance"]) {
            RYDogAppendObject(queue, seen, RYDogCall0((id)managerClass, selectorName));
        }
    }

    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *window = RYDogKeyWindow();
    UIViewController *presenter = RYDogPresenter(seed);
    RYDogAppendObject(queue, seen, seed);
    RYDogAppendObject(queue, seen, presenter);
    RYDogAppendObject(queue, seen, window);
    RYDogAppendObject(queue, seen, window.rootViewController);
    RYDogAppendObject(queue, seen, app.delegate);

    NSArray *selectors = @[
        @"userSession", @"igUserSession", @"currentUserSession", @"activeUserSession",
        @"mainAppViewController", @"rootViewController", @"selectedViewController", @"visibleViewController",
        @"topViewController", @"delegate", @"appCoordinator", @"sessionManager", @"activeUserSessions"
    ];

    NSUInteger cursor = 0;
    NSUInteger budget = 700;
    id firstSession = nil;

    while (cursor < queue.count && budget > 0) {
        budget--;
        id obj = [queue objectAtIndex:cursor++];

        if (RYDogIsUserSession(obj)) {
            if (!firstSession) firstSession = obj;
            if (![candidates containsObject:obj]) [candidates addObject:obj];
        }

        for (NSString *selectorName in selectors) {
            id child = RYDogCall0(obj, selectorName);
            if (!child) continue;

            if (RYDogIsUserSession(child)) {
                if (!firstSession) firstSession = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                if (log) {
                    [log appendFormat:@"%@ <%@>.%@ -> ", RYDogClassName(obj), RYDogPtr(obj), selectorName];
                    RYDogAppendSessionLine(log, @"", child);
                }
            }

            RYDogAppendObject(queue, seen, child);
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            NSString *ivarName = [NSString stringWithUTF8String:ivar_getName(ivar) ?: ""];
            if (!RYDogUsefulIvarName(ivarName)) continue;

            id child = RYDogObjectIvar(obj, ivar);
            if (!child) continue;

            NSString *pk = RYDogUserPk(child);
            if (RYDogIsUserSession(child)) {
                if (!firstSession) firstSession = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                if (log) {
                    [log appendFormat:@"%@ <%@> ivar %@ -> ", RYDogClassName(obj), RYDogPtr(obj), ivarName];
                    RYDogAppendSessionLine(log, @"", child);
                }
            } else if (pk.length && log) {
                [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RYDogClassName(obj), RYDogPtr(obj), ivarName, RYDogClassName(child), RYDogPtr(child), pk];
            }

            RYDogAppendObject(queue, seen, child);
        }
        if (ivars) free(ivars);
    }

    if (log) {
        [log appendFormat:@"deepScan budgetRemaining=%lu visited=%lu candidates=%lu\n\n", (unsigned long)budget, (unsigned long)seen.count, (unsigned long)candidates.count];
        [log appendFormat:@"RESULT: %lu IGUserSession candidate(s)\n", (unsigned long)candidates.count];
        for (NSUInteger i = 0; i < candidates.count; i++) {
            id candidate = [candidates objectAtIndex:i];
            [log appendFormat:@"candidate[%lu] = %@ <%@> · userPk=%@\n", (unsigned long)i, RYDogClassName(candidate), RYDogPtr(candidate), RYDogUserPk(candidate) ?: @"?"];
        }
        [log appendString:@"\nFlex cross-check:\n"];
        [log appendString:@"Good: IGSessionContext with _loggedInContext_userSession = <IGUserSession: 0x...>\n"];
        [log appendString:@"Good: direct IGUserSession object with userPk matching your account.\n"];
        [log appendString:@"Bad: only IGDeviceSession / _loggedOutContext_deviceSession.\n"];
        [log appendString:@"The numeric userPk confirms the account, but the opener needs the live object pointer.\n"];
    }

    return firstSession;
}

static void RYDogPresentText(UIViewController *source, NSString *title, NSString *body) {
    UIViewController *presenter = RYDogPresenter(source) ?: source;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = body ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSString *RYDogClassLine(NSString *label, NSString *className, BOOL viewController) {
    Class cls = RYDogClass(className);
    if (!cls) return [NSString stringWithFormat:@"%@ = missing\n", label];
    BOOL isVC = viewController ? [cls isSubclassOfClass:UIViewController.class] : NO;
    return [NSString stringWithFormat:@"%@ = found · runtime=%@ · superclass=%@%@\n", label, NSStringFromClass(cls), NSStringFromClass(class_getSuperclass(cls)) ?: @"nil", viewController ? [NSString stringWithFormat:@" · UIViewController=%@", isVC ? @"YES" : @"NO"] : @""];
}

static NSString *RYLocalExperimentCheckReport(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"LocalExperiment native check\nmode = safe check only\n\n"];

    Class meta = RYDogClass(@"MetaLocalExperiment");
    Class family = RYDogClass(@"FamilyLocalExperiment");
    Class lid = RYDogClass(@"LIDLocalExperiment");
    Class lidGen = RYDogClass(@"LIDExperimentGenerator");
    Class fdidGen = RYDogClass(@"FDIDExperimentGenerator");
    Class list = RYDogClass(@"MetaLocalExperimentListViewController");

    [s appendString:RYDogClassLine(@"MetaLocalExperiment", @"MetaLocalExperiment", YES)];
    [s appendString:RYDogClassLine(@"FamilyLocalExperiment", @"FamilyLocalExperiment", YES)];
    [s appendFormat:@"Family subclass of Meta = %@\n", (meta && family && [family isSubclassOfClass:meta]) ? @"YES" : @"NO"];
    [s appendString:RYDogClassLine(@"LIDLocalExperiment", @"LIDLocalExperiment", YES)];
    [s appendFormat:@"LIDLocalExperiment subclass of Meta = %@\n\n", (meta && lid && [lid isSubclassOfClass:meta]) ? @"YES" : @"NO"];

    [s appendString:RYDogClassLine(@"LIDExperimentGenerator", @"LIDExperimentGenerator", YES)];
    [s appendFormat:@"-initWithDeviceID:logger: = %@\n", (lidGen && [lidGen instancesRespondToSelector:NSSelectorFromString(@"initWithDeviceID:logger:")]) ? @"YES" : @"NO"];
    [s appendFormat:@"-createLocalExperiment: = %@\n", (lidGen && [lidGen instancesRespondToSelector:NSSelectorFromString(@"createLocalExperiment:")]) ? @"YES" : @"NO"];
    [s appendString:RYDogClassLine(@"FDIDExperimentGenerator", @"FDIDExperimentGenerator", YES)];
    [s appendFormat:@"FDID -initWithDeviceID:logger: = %@\n\n", (fdidGen && [fdidGen instancesRespondToSelector:NSSelectorFromString(@"initWithDeviceID:logger:")]) ? @"YES" : @"NO"];

    [s appendString:RYDogClassLine(@"MetaLocalExperimentListViewController", @"MetaLocalExperimentListViewController", YES)];
    [s appendFormat:@"-initWithExperimentConfigs:experimentGenerator: = %@\n", (list && [list instancesRespondToSelector:NSSelectorFromString(@"initWithExperimentConfigs:experimentGenerator:")]) ? @"YES" : @"NO"];
    return s;
}

static NSString *RYDogfoodingNativeCheckReport(void) {
    NSMutableString *s = [NSMutableString string];
    const unsigned long long anchor = 0x0081008a00000122ULL;
    [s appendString:@"Dogfooding native check\nmode = safe check only; no alloc, no KVC, no method invocation\n"];
    [s appendFormat:@"goldenAnchor = 0x%016llx / %llu\n\n", anchor, anchor];

    Class entry = RYDogClass(@"IGDogfoodingSettings.IGDogfoodingSettings");
    [s appendString:RYDogClassLine(@"entrypoint", @"IGDogfoodingSettings.IGDogfoodingSettings", YES)];
    [s appendFormat:@"+openWithConfig:onViewController:userSession: = %@\n\n", (entry && [entry respondsToSelector:NSSelectorFromString(@"openWithConfig:onViewController:userSession:")]) ? @"YES" : @"NO"];

    Class settingsVC = RYDogClass(@"IGDogfoodingSettings.IGDogfoodingSettingsViewController");
    [s appendString:RYDogClassLine(@"settingsViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsViewController", YES)];
    [s appendFormat:@"-initWithConfig:userSession: = %@\n\n", (settingsVC && [settingsVC instancesRespondToSelector:NSSelectorFromString(@"initWithConfig:userSession:")]) ? @"YES" : @"NO"];

    Class selectionVC = RYDogClass(@"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController");
    [s appendString:RYDogClassLine(@"selectionViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController", YES)];
    [s appendFormat:@"-initWithItem:options: = %@\n\n", (selectionVC && [selectionVC instancesRespondToSelector:NSSelectorFromString(@"initWithItem:options:")]) ? @"YES" : @"NO"];

    [s appendString:RYDogClassLine(@"lockoutViewController", @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController", YES)];
    [s appendString:RYDogClassLine(@"settingsConfig", @"IGDogfoodingSettingsConfig", YES)];
    [s appendString:RYDogClassLine(@"IGDogfooderProd", @"IGDogfooderProd", YES)];
    [s appendString:RYDogClassLine(@"IGDogfoodingLogger", @"IGDogfoodingLogger", YES)];
    [s appendString:RYDogClassLine(@"DogfoodingEligibilityQueryBuilder", @"DogfoodingEligibilityQueryBuilder", YES)];
    [s appendString:@"\nNext: find the callsite for +openWithConfig:onViewController:userSession: in the main Instagram executable. That callsite should reveal the native row/button and the real config/session source.\n"];
    return s;
}

static SEL RYDogDirectNotesSelector(Class cls) {
    if (!cls) return NULL;
    NSArray *selectors = @[
        @"notesDogfoodingSettingsOpenOnViewController:userSession:",
        @"openOnViewController:userSession:",
        @"openWithViewController:userSession:",
        @"dogfoodingSettingsOpenOnViewController:userSession:",
        @"directNotesDogfoodingSettingsOpenOnViewController:userSession:"
    ];
    for (NSString *selectorName in selectors) {
        SEL sel = NSSelectorFromString(selectorName);
        if ([cls respondsToSelector:sel]) return sel;
    }
    return NULL;
}

static void RYDogOpenDirectNotesFrom(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Try Direct Notes dogfooding opener\nmode = best effort opener\n\n"];
    UIViewController *presenter = RYDogPresenter(source);
    Class cls = RYDogClass(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
    SEL sel = RYDogDirectNotesSelector(cls);

    [log appendFormat:@"directNotesClass = %@\n", cls ? NSStringFromClass(cls) : @"missing"];
    [log appendFormat:@"method = %@\n", sel ? @"YES" : @"NO"];
    [log appendFormat:@"viewController = %@ <%@>\n", RYDogClassName(presenter), RYDogPtr(presenter)];

    NSMutableString *sessionLog = [NSMutableString string];
    id userSession = RYDogFindUserSession(presenter ?: source, sessionLog);
    [log appendFormat:@"selectedUserSession = %@ <%@>%@\n", RYDogClassName(userSession), RYDogPtr(userSession), RYDogUserPk(userSession).length ? [NSString stringWithFormat:@" · userPk=%@", RYDogUserPk(userSession)] : @""];

    if (!cls || !sel) {
        [log appendString:@"\nABORT: Direct Notes dogfooding class/method missing.\n"];
        RYDogPresentText(source, @"Dogfooding Notes", log);
        return;
    }

    if (!presenter || !userSession) {
        [log appendString:@"\nABORT: missing UIViewController or IGUserSession.\nRun Browser > Find IGUserSession first.\n\n"];
        [log appendString:sessionLog];
        RYDogPresentText(source, @"Dogfooding Notes", log);
        return;
    }

    @try {
        void (*send)(id, SEL, id, id) = (void (*)(id, SEL, id, id))objc_msgSend;
        send((id)cls, sel, presenter, userSession);
        NSLog(@"[RyukGram][Dogfood] opening Direct Notes native opener presenter=%@ <%p> userSession=%@ <%p>", presenter, presenter, userSession, userSession);
    } @catch (id e) {
        [log appendFormat:@"\nEXCEPTION: %@\n", e];
        RYDogPresentText(source, @"Dogfooding Notes", log);
    }
}

static BOOL RYDogIsBrowserTab(id vc) {
    @try {
        id tab = [vc valueForKey:@"tab"];
        if ([tab respondsToSelector:@selector(integerValue)]) return [tab integerValue] == 0;
    } @catch (__unused id e) {}
    return NO;
}

static NSArray *RYDogRows(void) {
    return @[
        @"Dogfooding native check",
        @"Find IGUserSession",
        @"Try Direct Notes dogfooding opener"
    ];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;
    if (!RYDogIsBrowserTab(self)) return orig;

    NSMutableArray *rows = [orig mutableCopy] ?: [NSMutableArray array];
    for (NSString *row in RYDogRows()) {
        if (![rows containsObject:row]) [rows addObject:row];
    }
    return rows;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = [self filteredRows];
    NSUInteger row = (NSUInteger)indexPath.row;
    if (RYDogIsBrowserTab(self) && row < rows.count) {
        id item = [rows objectAtIndex:row];
        if ([item isKindOfClass:[NSString class]]) {
            NSString *title = (NSString *)item;
            if ([title isEqualToString:@"Dogfooding native check"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                [self ry_presentRuntimeDiagnostics:RYDogfoodingNativeCheckReport()];
                return;
            }
            if ([title isEqualToString:@"Find IGUserSession"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                NSMutableString *log = [NSMutableString string];
                (void)RYDogFindUserSession((UIViewController *)self, log);
                [self ry_presentRuntimeDiagnostics:log];
                return;
            }
            if ([title isEqualToString:@"Try Direct Notes dogfooding opener"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                [self ry_tryOpenDirectNotesDogfooding];
                return;
            }
        }
    }

    %orig(tableView, indexPath);
}

%new
- (void)ry_tryOpenDirectNotesDogfooding {
    RYDogOpenDirectNotesFrom((UIViewController *)self);
}

%new
- (void)ry_presentRuntimeDiagnostics:(NSString *)text {
    RYDogPresentText((UIViewController *)self, @"Runtime diagnostics", text ?: @"");
}

%end

__attribute__((constructor))
static void RYDogToolsCtor(void) {
    @autoreleasepool {
        NSLog(@"[RyukGram][Dogfood] native openers loaded");
    }
}
