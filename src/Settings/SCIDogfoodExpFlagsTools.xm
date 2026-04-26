#import "SCIExpFlagsViewController.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *RYDFPtr(id obj) { return obj ? [NSString stringWithFormat:@"%p", (__bridge void *)obj] : @"0x0"; }
static NSString *RYDFClass(id obj) { return obj ? NSStringFromClass([obj class]) : @"nil"; }
static Class RYDFClassNamed(NSString *name) { Class c = NSClassFromString(name); return c ?: (Class)objc_getClass(name.UTF8String); }

static id RYDFCall0(id target, NSString *selectorName) {
    if (!target) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(target, sel); } @catch (__unused id e) { return nil; }
}

static NSArray *RYDFCallFilteredRows(id target) {
    SEL sel = NSSelectorFromString(@"filteredRows");
    if (!target || ![target respondsToSelector:sel]) return @[];
    @try { return ((NSArray *(*)(id, SEL))objc_msgSend)(target, sel) ?: @[]; } @catch (__unused id e) { return @[]; }
}

static NSString *RYDFStringValue(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:NSString.class]) return obj;
    if ([obj respondsToSelector:@selector(stringValue)]) {
        @try { return [obj stringValue]; } @catch (__unused id e) { return nil; }
    }
    return nil;
}

static id RYDFObjectIvar(id obj, Ivar ivar) {
    if (!obj || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(obj, ivar); } @catch (__unused id e) { return nil; }
}

static NSString *RYDFUserPk(id obj) {
    NSArray *sels = @[@"userPk", @"userPK", @"userId", @"userID", @"pk"];
    for (NSString *s in sels) { NSString *v = RYDFStringValue(RYDFCall0(obj, s)); if (v.length) return v; }
    id user = RYDFCall0(obj, @"user") ?: RYDFObjectIvar(obj, class_getInstanceVariable([obj class], "_user"));
    for (NSString *s in sels) { NSString *v = RYDFStringValue(RYDFCall0(user, s)); if (v.length) return v; }
    NSString *v = RYDFStringValue(RYDFObjectIvar(obj, class_getInstanceVariable([obj class], "_userPK")));
    return v.length ? v : nil;
}

static UIWindow *RYDFKeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!fallback) fallback = w;
            if (w.isKeyWindow) return w;
        }
    }
    return fallback;
}

static UIViewController *RYDFTopVC(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;
    if ([cur isKindOfClass:UINavigationController.class]) {
        UINavigationController *nav = (UINavigationController *)cur;
        return RYDFTopVC(nav.visibleViewController ?: nav.topViewController);
    }
    if ([cur isKindOfClass:UITabBarController.class]) return RYDFTopVC(((UITabBarController *)cur).selectedViewController);
    return cur;
}

static UIViewController *RYDFPresenter(id fallback) {
    UIViewController *vc = RYDFTopVC(RYDFKeyWindow().rootViewController);
    return vc ?: ([fallback isKindOfClass:UIViewController.class] ? (UIViewController *)fallback : nil);
}

static BOOL RYDFUsefulIvar(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"usersession"] || [n containsString:@"sessionmanager"] ||
           [n containsString:@"activeusersessions"] || [n containsString:@"mainapp"] ||
           [n containsString:@"appcoordinator"] || [n containsString:@"tabbar"] ||
           [n containsString:@"window"] || [n containsString:@"root"] ||
           [n containsString:@"delegate"] || [n containsString:@"context"] ||
           [n containsString:@"launcher"] || [n containsString:@"feed"] || [n containsString:@"story"];
}

static void RYDFQueue(NSMutableArray *queue, NSMutableSet *seen, id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return;
    NSString *key = RYDFPtr(obj);
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [queue addObject:obj];
}

static id RYDFFindUserSession(id seed, NSMutableString *log) {
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *candidates = [NSMutableArray array];
    id first = nil;

    [log appendString:@"IGUserSession finder\n"];
    [log appendString:@"mode = root + view-controller tree + known singleton selectors + limited ivar scan\n"];
    [log appendString:@"goal = find real IGUserSession object; IGDeviceSession is not enough\n\n"];

    Class manager = RYDFClassNamed(@"IGUserSessionManager");
    if (manager) {
        [log appendString:@"singleton class IGUserSessionManager found\n"];
        for (NSString *sel in @[@"sharedInstance", @"sharedManager", @"currentSessionManager", @"instance"]) RYDFQueue(queue, seen, RYDFCall0((id)manager, sel));
    }

    UIWindow *window = RYDFKeyWindow();
    UIViewController *presenter = RYDFPresenter(seed);
    RYDFQueue(queue, seen, seed);
    RYDFQueue(queue, seen, presenter);
    RYDFQueue(queue, seen, window);
    RYDFQueue(queue, seen, window.rootViewController);
    RYDFQueue(queue, seen, UIApplication.sharedApplication.delegate);

    NSArray *selectors = @[@"userSession", @"igUserSession", @"currentUserSession", @"activeUserSession", @"mainAppViewController", @"rootViewController", @"selectedViewController", @"visibleViewController", @"topViewController", @"delegate", @"appCoordinator", @"sessionManager", @"activeUserSessions"];
    NSUInteger cursor = 0;
    NSUInteger budget = 700;

    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        if ([RYDFClass(obj) isEqualToString:@"IGUserSession"]) {
            if (!first) first = obj;
            if (![candidates containsObject:obj]) [candidates addObject:obj];
        }

        for (NSString *sel in selectors) {
            id child = RYDFCall0(obj, sel);
            if (!child) continue;
            if ([RYDFClass(child) isEqualToString:@"IGUserSession"]) {
                if (!first) first = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                [log appendFormat:@"%@ <%@>.%@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), sel, RYDFClass(child), RYDFPtr(child), RYDFUserPk(child) ?: @"?"];
            }
            RYDFQueue(queue, seen, child);
        }

        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
            if (!RYDFUsefulIvar(name)) continue;
            id child = RYDFObjectIvar(obj, ivars[i]);
            if (!child) continue;
            NSString *pk = RYDFUserPk(child);
            if ([RYDFClass(child) isEqualToString:@"IGUserSession"]) {
                if (!first) first = child;
                if (![candidates containsObject:child]) [candidates addObject:child];
                [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), name, RYDFClass(child), RYDFPtr(child), pk ?: @"?"];
            } else if (pk.length) {
                [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), name, RYDFClass(child), RYDFPtr(child), pk];
            }
            RYDFQueue(queue, seen, child);
        }
        if (ivars) free(ivars);
    }

    [log appendFormat:@"deepScan budgetRemaining=%lu visited=%lu candidates=%lu\n\nRESULT: %lu IGUserSession candidate(s)\n", (unsigned long)budget, (unsigned long)seen.count, (unsigned long)candidates.count, (unsigned long)candidates.count];
    for (NSUInteger i = 0; i < candidates.count; i++) {
        id c = candidates[i];
        [log appendFormat:@"candidate[%lu] = %@ <%@> · userPk=%@\n", (unsigned long)i, RYDFClass(c), RYDFPtr(c), RYDFUserPk(c) ?: @"?"];
    }
    [log appendString:@"\nFlex cross-check:\nGood: IGSessionContext with _loggedInContext_userSession = <IGUserSession: 0x...>\nGood: direct IGUserSession object with userPk matching your account.\nBad: only IGDeviceSession / _loggedOutContext_deviceSession.\nThe numeric userPk confirms the account, but the opener needs the live object pointer.\n"];
    return first;
}

static void RYDFPresent(UIViewController *source, NSString *title, NSString *body) {
    UIViewController *presenter = RYDFPresenter(source) ?: source;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = body ?: @"";
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSString *RYDFClassLine(NSString *label, NSString *className, BOOL viewController) {
    Class cls = RYDFClassNamed(className);
    if (!cls) return [NSString stringWithFormat:@"%@ = missing\n", label];
    return [NSString stringWithFormat:@"%@ = found · runtime=%@ · superclass=%@%@\n", label, NSStringFromClass(cls), NSStringFromClass(class_getSuperclass(cls)) ?: @"nil", viewController ? [NSString stringWithFormat:@" · UIViewController=%@", [cls isSubclassOfClass:UIViewController.class] ? @"YES" : @"NO"] : @""];
}

static NSString *RYDFDogfoodingReport(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"Dogfooding native check\nmode = safe check only; no alloc, no KVC, no method invocation\ngoldenAnchor = 0x0081008a00000122 / 36310864701161762\n\n"];
    Class entry = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettings");
    [s appendString:RYDFClassLine(@"entrypoint", @"IGDogfoodingSettings.IGDogfoodingSettings", YES)];
    [s appendFormat:@"+openWithConfig:onViewController:userSession: = %@\n\n", (entry && [entry respondsToSelector:NSSelectorFromString(@"openWithConfig:onViewController:userSession:")]) ? @"YES" : @"NO"];
    Class settings = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettingsViewController");
    [s appendString:RYDFClassLine(@"settingsViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsViewController", YES)];
    [s appendFormat:@"-initWithConfig:userSession: = %@\n\n", (settings && [settings instancesRespondToSelector:NSSelectorFromString(@"initWithConfig:userSession:")]) ? @"YES" : @"NO"];
    Class selection = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController");
    [s appendString:RYDFClassLine(@"selectionViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController", YES)];
    [s appendFormat:@"-initWithItem:options: = %@\n\n", (selection && [selection instancesRespondToSelector:NSSelectorFromString(@"initWithItem:options:")]) ? @"YES" : @"NO"];
    [s appendString:RYDFClassLine(@"lockoutViewController", @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController", YES)];
    [s appendString:RYDFClassLine(@"settingsConfig", @"IGDogfoodingSettingsConfig", YES)];
    [s appendString:RYDFClassLine(@"IGDogfooderProd", @"IGDogfooderProd", YES)];
    [s appendString:RYDFClassLine(@"IGDogfoodingLogger", @"IGDogfoodingLogger", YES)];
    [s appendString:RYDFClassLine(@"DogfoodingEligibilityQueryBuilder", @"DogfoodingEligibilityQueryBuilder", YES)];
    [s appendString:@"\nNext: find the callsite for +openWithConfig:onViewController:userSession: in the main Instagram executable. That callsite should reveal the native row/button and the real config/session source.\n"];
    return s;
}

static SEL RYDFDirectNotesSelector(Class cls) {
    if (!cls) return NULL;
    for (NSString *name in @[@"notesDogfoodingSettingsOpenOnViewController:userSession:", @"openOnViewController:userSession:", @"openWithViewController:userSession:", @"dogfoodingSettingsOpenOnViewController:userSession:", @"directNotesDogfoodingSettingsOpenOnViewController:userSession:"]) {
        SEL sel = NSSelectorFromString(name);
        if ([cls respondsToSelector:sel]) return sel;
    }
    return NULL;
}

static void RYDFOpenDirectNotes(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Try Direct Notes dogfooding opener\nmode = best effort opener\n\n"];
    UIViewController *presenter = RYDFPresenter(source);
    Class cls = RYDFClassNamed(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs");
    SEL sel = RYDFDirectNotesSelector(cls);
    [log appendFormat:@"directNotesClass = %@\nmethod = %@\nviewController = %@ <%@>\n", cls ? NSStringFromClass(cls) : @"missing", sel ? @"YES" : @"NO", RYDFClass(presenter), RYDFPtr(presenter)];
    NSMutableString *sessionLog = [NSMutableString string];
    id userSession = RYDFFindUserSession(presenter ?: source, sessionLog);
    [log appendFormat:@"selectedUserSession = %@ <%@>%@\n", RYDFClass(userSession), RYDFPtr(userSession), RYDFUserPk(userSession).length ? [NSString stringWithFormat:@" · userPk=%@", RYDFUserPk(userSession)] : @""];
    if (!cls || !sel) { [log appendString:@"\nABORT: Direct Notes dogfooding class/method missing.\n"]; RYDFPresent(source, @"Dogfooding Notes", log); return; }
    if (!presenter || !userSession) { [log appendString:@"\nABORT: missing UIViewController or IGUserSession.\nRun Browser > Find IGUserSession first.\n\n"]; [log appendString:sessionLog]; RYDFPresent(source, @"Dogfooding Notes", log); return; }
    @try {
        ((void (*)(id, SEL, id, id))objc_msgSend)((id)cls, sel, presenter, userSession);
    } @catch (id e) {
        [log appendFormat:@"\nEXCEPTION: %@\n", e];
        RYDFPresent(source, @"Dogfooding Notes", log);
    }
}

static BOOL RYDFIsBrowserTab(id vc) {
    @try {
        id tab = [vc valueForKey:@"tab"];
        if ([tab respondsToSelector:@selector(integerValue)]) return [tab integerValue] == 0;
    } @catch (__unused id e) {}
    return NO;
}

static NSArray *RYDFRows(void) {
    return @[@"Dogfooding native check", @"Find IGUserSession", @"Try Direct Notes dogfooding opener"];
}

%hook SCIExpFlagsViewController

- (NSArray *)filteredRows {
    NSArray *orig = %orig;
    if (!RYDFIsBrowserTab(self)) return orig;
    NSMutableArray *rows = [orig mutableCopy] ?: [NSMutableArray array];
    for (NSString *row in RYDFRows()) if (![rows containsObject:row]) [rows addObject:row];
    return rows;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = RYDFCallFilteredRows(self);
    NSUInteger row = (NSUInteger)indexPath.row;
    if (RYDFIsBrowserTab(self) && row < rows.count) {
        id item = rows[row];
        if ([item isKindOfClass:NSString.class]) {
            NSString *title = item;
            if ([title isEqualToString:@"Dogfooding native check"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RYDFPresent((UIViewController *)self, @"Runtime diagnostics", RYDFDogfoodingReport());
                return;
            }
            if ([title isEqualToString:@"Find IGUserSession"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                NSMutableString *log = [NSMutableString string];
                (void)RYDFFindUserSession((UIViewController *)self, log);
                RYDFPresent((UIViewController *)self, @"Runtime diagnostics", log);
                return;
            }
            if ([title isEqualToString:@"Try Direct Notes dogfooding opener"]) {
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                RYDFOpenDirectNotes((UIViewController *)self);
                return;
            }
        }
    }
    %orig(tableView, indexPath);
}

%end
