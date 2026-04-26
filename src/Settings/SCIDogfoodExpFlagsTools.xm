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
        for (UIWindow *w in ((UIWindowScene *)scene).windows) { if (!fallback) fallback = w; if (w.isKeyWindow) return w; }
    }
    return fallback;
}

static UIViewController *RYDFTopVC(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;
    if ([cur isKindOfClass:UINavigationController.class]) return RYDFTopVC(((UINavigationController *)cur).visibleViewController ?: ((UINavigationController *)cur).topViewController);
    if ([cur isKindOfClass:UITabBarController.class]) return RYDFTopVC(((UITabBarController *)cur).selectedViewController);
    return cur;
}

static UIViewController *RYDFPresenter(id fallback) {
    UIViewController *vc = RYDFTopVC(RYDFKeyWindow().rootViewController);
    return vc ?: ([fallback isKindOfClass:UIViewController.class] ? fallback : nil);
}

static BOOL RYDFUsefulIvar(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"usersession"] || [n containsString:@"sessionmanager"] || [n containsString:@"activeusersessions"] || [n containsString:@"mainapp"] || [n containsString:@"appcoordinator"] || [n containsString:@"tabbar"] || [n containsString:@"window"] || [n containsString:@"root"] || [n containsString:@"delegate"] || [n containsString:@"context"] || [n containsString:@"launcher"] || [n containsString:@"feed"] || [n containsString:@"story"];
}

static void RYDFQueue(NSMutableArray *q, NSMutableSet *seen, id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return;
    NSString *k = RYDFPtr(obj); if ([seen containsObject:k]) return; [seen addObject:k]; [q addObject:obj];
}

static id RYDFFindUserSession(id seed, NSMutableString *log) {
    NSMutableArray *q = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set]; NSMutableArray *candidates = [NSMutableArray array]; id first = nil;
    [log appendString:@"IGUserSession finder\nmode = root + view-controller tree + known singleton selectors + limited ivar scan\ngoal = find real IGUserSession object; IGDeviceSession is not enough\n\n"];
    Class mgr = RYDFClassNamed(@"IGUserSessionManager"); if (mgr) { [log appendString:@"singleton class IGUserSessionManager found\n"]; for (NSString *s in @[@"sharedInstance", @"sharedManager", @"currentSessionManager", @"instance"]) RYDFQueue(q, seen, RYDFCall0((id)mgr, s)); }
    UIWindow *w = RYDFKeyWindow(); UIViewController *p = RYDFPresenter(seed); RYDFQueue(q, seen, seed); RYDFQueue(q, seen, p); RYDFQueue(q, seen, w); RYDFQueue(q, seen, w.rootViewController); RYDFQueue(q, seen, UIApplication.sharedApplication.delegate);
    NSArray *sels = @[@"userSession", @"igUserSession", @"currentUserSession", @"activeUserSession", @"mainAppViewController", @"rootViewController", @"selectedViewController", @"visibleViewController", @"topViewController", @"delegate", @"appCoordinator", @"sessionManager", @"activeUserSessions"];
    NSUInteger cursor = 0, budget = 700;
    while (cursor < q.count && budget-- > 0) {
        id obj = q[cursor++];
        if ([RYDFClass(obj) isEqualToString:@"IGUserSession"]) { if (!first) first = obj; if (![candidates containsObject:obj]) [candidates addObject:obj]; }
        for (NSString *s in sels) {
            id child = RYDFCall0(obj, s); if (!child) continue;
            if ([RYDFClass(child) isEqualToString:@"IGUserSession"]) { if (!first) first = child; if (![candidates containsObject:child]) [candidates addObject:child]; [log appendFormat:@"%@ <%@>.%@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), s, RYDFClass(child), RYDFPtr(child), RYDFUserPk(child) ?: @"?"]; }
            RYDFQueue(q, seen, child);
        }
        unsigned int count = 0; Ivar *ivars = class_copyIvarList([obj class], &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""]; if (!RYDFUsefulIvar(name)) continue;
            id child = RYDFObjectIvar(obj, ivars[i]); if (!child) continue; NSString *pk = RYDFUserPk(child);
            if ([RYDFClass(child) isEqualToString:@"IGUserSession"]) { if (!first) first = child; if (![candidates containsObject:child]) [candidates addObject:child]; [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), name, RYDFClass(child), RYDFPtr(child), pk ?: @"?"]; }
            else if (pk.length) [log appendFormat:@"%@ <%@> ivar %@ -> %@ <%@> · userPk=%@\n", RYDFClass(obj), RYDFPtr(obj), name, RYDFClass(child), RYDFPtr(child), pk];
            RYDFQueue(q, seen, child);
        }
        if (ivars) free(ivars);
    }
    [log appendFormat:@"deepScan budgetRemaining=%lu visited=%lu candidates=%lu\n\nRESULT: %lu IGUserSession candidate(s)\n", (unsigned long)budget, (unsigned long)seen.count, (unsigned long)candidates.count, (unsigned long)candidates.count];
    for (NSUInteger i = 0; i < candidates.count; i++) { id c = candidates[i]; [log appendFormat:@"candidate[%lu] = %@ <%@> · userPk=%@\n", (unsigned long)i, RYDFClass(c), RYDFPtr(c), RYDFUserPk(c) ?: @"?"]; }
    [log appendString:@"\nFlex cross-check:\nGood: IGSessionContext with _loggedInContext_userSession = <IGUserSession: 0x...>\nGood: direct IGUserSession object with userPk matching your account.\nBad: only IGDeviceSession / _loggedOutContext_deviceSession.\nThe numeric userPk confirms the account, but the opener needs the live object pointer.\n"];
    return first;
}

static void RYDFPresent(UIViewController *source, NSString *title, NSString *body) {
    UIViewController *p = RYDFPresenter(source) ?: source; UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ UIPasteboard.generalPasteboard.string = body ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]]; [p presentViewController:a animated:YES completion:nil];
}

static NSString *RYDFLine(NSString *label, NSString *className, BOOL vc) { Class c = RYDFClassNamed(className); if (!c) return [NSString stringWithFormat:@"%@ = missing\n", label]; return [NSString stringWithFormat:@"%@ = found · runtime=%@ · superclass=%@%@\n", label, NSStringFromClass(c), NSStringFromClass(class_getSuperclass(c)) ?: @"nil", vc ? [NSString stringWithFormat:@" · UIViewController=%@", [c isSubclassOfClass:UIViewController.class] ? @"YES" : @"NO"] : @""]; }

static NSString *RYDFDogReport(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"Dogfooding native check\nmode = safe check only; no alloc, no KVC, no method invocation\ngoldenAnchor = 0x0081008a00000122 / 36310864701161762\n\n"];
    Class entry = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettings"); [s appendString:RYDFLine(@"entrypoint", @"IGDogfoodingSettings.IGDogfoodingSettings", YES)]; [s appendFormat:@"+openWithConfig:onViewController:userSession: = %@\n\n", (entry && [entry respondsToSelector:NSSelectorFromString(@"openWithConfig:onViewController:userSession:")]) ? @"YES" : @"NO"];
    Class settings = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettingsViewController"); [s appendString:RYDFLine(@"settingsViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsViewController", YES)]; [s appendFormat:@"-initWithConfig:userSession: = %@\n\n", (settings && [settings instancesRespondToSelector:NSSelectorFromString(@"initWithConfig:userSession:")]) ? @"YES" : @"NO"];
    Class selection = RYDFClassNamed(@"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController"); [s appendString:RYDFLine(@"selectionViewController", @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController", YES)]; [s appendFormat:@"-initWithItem:options: = %@\n\n", (selection && [selection instancesRespondToSelector:NSSelectorFromString(@"initWithItem:options:")]) ? @"YES" : @"NO"];
    [s appendString:RYDFLine(@"lockoutViewController", @"IGDogfoodingFirst.DogfoodingProductionLockoutViewController", YES)]; [s appendString:RYDFLine(@"settingsConfig", @"IGDogfoodingSettingsConfig", YES)]; [s appendString:RYDFLine(@"IGDogfooderProd", @"IGDogfooderProd", YES)]; [s appendString:RYDFLine(@"IGDogfoodingLogger", @"IGDogfoodingLogger", YES)]; [s appendString:RYDFLine(@"DogfoodingEligibilityQueryBuilder", @"DogfoodingEligibilityQueryBuilder", YES)]; [s appendString:@"\nNext: find the callsite for +openWithConfig:onViewController:userSession: in the main Instagram executable. That callsite should reveal the native row/button and the real config/session source.\n"]; return s;
}

static SEL RYDFDNSel(Class c) { for (NSString *name in @[@"notesDogfoodingSettingsOpenOnViewController:userSession:", @"openOnViewController:userSession:", @"openWithViewController:userSession:", @"dogfoodingSettingsOpenOnViewController:userSession:", @"directNotesDogfoodingSettingsOpenOnViewController:userSession:"]) { SEL sel = NSSelectorFromString(name); if ([c respondsToSelector:sel]) return sel; } return NULL; }

static void RYDFOpenDN(UIViewController *source) {
    NSMutableString *log = [NSMutableString stringWithString:@"Try Direct Notes dogfooding opener\nmode = best effort opener\n\n"]; UIViewController *p = RYDFPresenter(source); Class c = RYDFClassNamed(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsStaticFuncs"); SEL sel = RYDFDNSel(c);
    [log appendFormat:@"directNotesClass = %@\nmethod = %@\nviewController = %@ <%@>\n", c ? NSStringFromClass(c) : @"missing", sel ? @"YES" : @"NO", RYDFClass(p), RYDFPtr(p)]; NSMutableString *sessionLog = [NSMutableString string]; id us = RYDFFindUserSession(p ?: source, sessionLog); [log appendFormat:@"selectedUserSession = %@ <%@>%@\n", RYDFClass(us), RYDFPtr(us), RYDFUserPk(us).length ? [NSString stringWithFormat:@" · userPk=%@", RYDFUserPk(us)] : @""];
    if (!c || !sel) { [log appendString:@"\nABORT: Direct Notes dogfooding class/method missing.\n"]; RYDFPresent(source, @"Dogfooding Notes", log); return; } if (!p || !us) { [log appendString:@"\nABORT: missing UIViewController or IGUserSession.\nRun Browser > Find IGUserSession first.\n\n"]; [log appendString:sessionLog]; RYDFPresent(source, @"Dogfooding Notes", log); return; }
    @try { ((void (*)(id, SEL, id, id))objc_msgSend)((id)c, sel, p, us); } @catch (id e) { [log appendFormat:@"\nEXCEPTION: %@\n", e]; RYDFPresent(source, @"Dogfooding Notes", log); }
}

static BOOL RYDFBrowserTab(id vc) { @try { id tab = [vc valueForKey:@"tab"]; if ([tab respondsToSelector:@selector(integerValue)]) return [tab integerValue] == 0; } @catch (__unused id e) {} return NO; }
static NSArray *RYDFRows(void) { return @[@"Dogfooding native check", @"Find IGUserSession", @"Try Direct Notes dogfooding opener"]; }

%hook SCIExpFlagsViewController
- (NSArray *)filteredRows { NSArray *orig = %orig; if (!RYDFBrowserTab(self)) return orig; NSMutableArray *rows = [orig mutableCopy] ?: [NSMutableArray array]; for (NSString *r in RYDFRows()) if (![rows containsObject:r]) [rows addObject:r]; return rows; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { NSArray *rows = [self filteredRows]; NSUInteger row = (NSUInteger)indexPath.row; if (RYDFBrowserTab(self) && row < rows.count) { id item = rows[row]; if ([item isKindOfClass:NSString.class]) { NSString *title = item; if ([title isEqualToString:@"Dogfooding native check"]) { [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYDFPresent((UIViewController *)self, @"Runtime diagnostics", RYDFDogReport()); return; } if ([title isEqualToString:@"Find IGUserSession"]) { [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSMutableString *log = [NSMutableString string]; (void)RYDFFindUserSession((UIViewController *)self, log); RYDFPresent((UIViewController *)self, @"Runtime diagnostics", log); return; } if ([title isEqualToString:@"Try Direct Notes dogfooding opener"]) { [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYDFOpenDN((UIViewController *)self); return; } } } %orig(tableView, indexPath); }
%end
