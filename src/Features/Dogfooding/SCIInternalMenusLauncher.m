#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

static UIViewController *SCITopVC(void)  { return [SCIDogfoodObjectRuntime topViewController]; }
static id               SCISession(void) { return [SCIDogfoodObjectRuntime activeUserSession]; }
static UINavigationController *SCINavFor(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:UINavigationController.class]) return (UINavigationController *)vc;
    return vc.navigationController;
}
static NSString *SCIPresentVC(UIViewController *vc, NSString *tag) {
    if (!vc || ![vc isKindOfClass:UIViewController.class])
        return [NSString stringWithFormat:@"%@ — nil or non-VC returned", tag];
    UIViewController *top = SCITopVC();
    if (!top) return [NSString stringWithFormat:@"%@ — no topVC", tag];
    UINavigationController *nav = SCINavFor(top);
    if (nav) { [nav pushViewController:vc animated:YES]; return [NSString stringWithFormat:@"pushed %@", tag]; }
    UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:vc];
    wrap.modalPresentationStyle = UIModalPresentationFormSheet;
    [top presentViewController:wrap animated:YES completion:nil];
    return [NSString stringWithFormat:@"presented %@", tag];
}

@implementation SCIInternalMenusLauncher

+ (NSString *)openDogfoodingNotesSettings {
    id session = SCISession();
    if (!session) return @"no live user session (open after login)";
    Class C = NSClassFromString(@"IGDirectNotesDogfoodingSettingsStaticFuncs")
           ?: NSClassFromString(@"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!C) return @"IGDirectNotesDogfoodingSettingsStaticFuncs not found";
    SEL s = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (![C respondsToSelector:s]) return @"selector not found on class";
    UIViewController *top = SCITopVC();
    UIViewController *presenter = SCINavFor(top) ?: top;
    @try {
        ((void(*)(id,SEL,id,id))objc_msgSend)(C, s, presenter, session);
        MLOG("Notes dogfooding settings opened");
        return @"opened Notes dogfooding settings";
    } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
}

+ (NSString *)openDogfoodingSettingsVC {
    @try {
        BOOL ok = [SCIDogfoodObjectRuntime tryOpenNativeDogfoodSettings];
        return ok ? @"opened native Dogfooding Settings"
                  : @"Dogfooding Settings unavailable: missing captured IGDogfoodingSettingsConfig/session; open an authorized native dogfood surface first";
    } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
}

+ (NSString *)openAutofillInternalSettings {
    NSArray *plain = @[
        @"IGAutofillTokenizationInternalSettingsPlugin.IGAutofillTokenizationInternalSettingsViewController",
        @"_TtC44IGAutofillTokenizationInternalSettingsPlugin52IGAutofillTokenizationInternalSettingsViewController",
    ];
    for (NSString *name in plain) {
        Class vcCls = NSClassFromString(name);
        if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class]) continue;
        @try {
            UIViewController *vc = [[vcCls alloc] init];
            NSString *r = SCIPresentVC(vc, @"AutofillInternalSettings");
            if (![r containsString:@"nil"]) { MLOG("%{public}s", r.UTF8String); return r; }
        } @catch (id) {}
    }
    id session = SCISession();
    if (!session) return @"no live session and no sessionless autofill VC found";
    for (NSString *name in plain) {
        Class vcCls = NSClassFromString(name);
        if (!vcCls) continue;
        SEL si = NSSelectorFromString(@"initWithUserSession:");
        if (![vcCls instancesRespondToSelector:si]) continue;
        @try {
            UIViewController *vc = ((id(*)(id,SEL,id))objc_msgSend)([vcCls alloc], si, session);
            NSString *r = SCIPresentVC(vc, @"AutofillInternalSettings+session");
            MLOG("%{public}s", r.UTF8String); return r;
        } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
    }
    return @"AutofillInternalSettings class not found in binary";
}

+ (NSString *)openSearchDebugSettings {
    Class vcCls = NSClassFromString(@"IGSearchDebugSettings.IGSearchDebugSettingsViewController")
               ?: NSClassFromString(@"_TtC21IGSearchDebugSettings35IGSearchDebugSettingsViewController");
    if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class])
        return @"IGSearchDebugSettingsViewController not found in binary";
    @try {
        UIViewController *vc = [[vcCls alloc] init];
        NSString *r = SCIPresentVC(vc, @"SearchDebugSettings");
        MLOG("%{public}s", r.UTF8String); return r;
    } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
}

+ (NSString *)openStoryStoreDebugSettings {
    Class vcCls = NSClassFromString(@"IGStoryStoresDebugSettings.IGStoryStoreDebugSettingsViewController")
               ?: NSClassFromString(@"_TtC26IGStoryStoresDebugSettings39IGStoryStoreDebugSettingsViewController");
    if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class])
        return @"IGStoryStoreDebugSettingsViewController not found in binary";
    @try {
        UIViewController *vc = [[vcCls alloc] init];
        NSString *r = SCIPresentVC(vc, @"StoryStoreDebugSettings");
        MLOG("%{public}s", r.UTF8String); return r;
    } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
}

+ (NSString *)openBestAvailableInternalMenu {
    for (NSString *r in @[
        [self openDogfoodingNotesSettings],
        [self openDogfoodingSettingsVC],
        [self openAutofillInternalSettings],
        [self openSearchDebugSettings],
        [self openInternalURLString:@"instagram://internal_settings"],
    ]) {
        if ([r hasPrefix:@"opened"] || [r hasPrefix:@"pushed"] || [r hasPrefix:@"presented"]) return r;
    }
    return @"All internal menu openers failed — are you logged in? Is any employee gate active?";
}

+ (NSString *)openInternalURLString:(NSString *)urlString {
    id session = SCISession();
    if (!session) return @"no live user session";
    Class C = NSClassFromString(@"IGURLHandler");
    SEL s = NSSelectorFromString(@"openInternalURL:presentationConfig:controller:animated:userSession:annotation:");
    if (!C || ![C respondsToSelector:s]) return @"IGURLHandler.openInternalURL not found";
    UIViewController *top = SCITopVC();
    NSURL *url = [NSURL URLWithString:urlString];
    @try {
        BOOL ok = ((BOOL(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(C, s, url, nil, top, YES, session, nil);
        return ok ? [NSString stringWithFormat:@"opened: %@", urlString]
                  : [NSString stringWithFormat:@"openInternalURL returned NO for: %@", urlString];
    } @catch (id e) { return [NSString stringWithFormat:@"threw: %@", e]; }
}

@end
