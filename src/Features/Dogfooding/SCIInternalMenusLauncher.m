#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define MLOG(fmt, ...) os_log(OS_LOG_DEFAULT, "[SCIGate] Menus " fmt, ##__VA_ARGS__)

@implementation SCIInternalMenusLauncher

+ (UIViewController *)topVC { return [SCIDogfoodObjectRuntime topViewController]; }
+ (id)session { return [SCIDogfoodObjectRuntime activeUserSession]; }

+ (UINavigationController *)navFor:(UIViewController *)vc {
    if ([vc isKindOfClass:UINavigationController.class]) return (UINavigationController *)vc;
    return vc.navigationController;
}

// +[IGDirectNotesDogfoodingSettingsStaticFuncs notesDogfoodingSettingsOpenOnViewController:userSession:]
+ (NSString *)openDogfoodingNotesSettings {
    id session = [self session]; UIViewController *top = [self topVC];
    if (!session) return @"no live user session yet (open after login)";
    if (!top) return @"no top view controller";
    Class C = NSClassFromString(@"IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!C) C = NSClassFromString(@"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
    SEL s = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (C && [C respondsToSelector:s]) {
        @try { ((void(*)(id,SEL,id,id))objc_msgSend)(C, s, top, session); MLOG("notes dogfooding opened"); return @"opened Notes dogfooding settings"; }
        @catch (id e) { return [NSString stringWithFormat:@"notes opener threw: %@", e]; }
    }
    return @"IGDirectNotesDogfoodingSettingsStaticFuncs not found";
}

// alloc IGDogfoodingSettingsViewController via initWithAnalyticsModule: and present.
// NOTE: Swift initializer; if it requires a non-nil module it may trap (uncatchable). Best-effort.
+ (NSString *)openDogfoodingSettingsVC {
    id session = [self session]; UIViewController *top = [self topVC];
    if (!top) return @"no top view controller";
    Class VC = NSClassFromString(@"IGDogfoodingSettingsViewController");
    if (!VC) VC = NSClassFromString(@"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController");
    if (!VC) return @"IGDogfoodingSettingsViewController not found";
    SEL iwc = NSSelectorFromString(@"initWithConfig:userSession:");
    SEL iam = NSSelectorFromString(@"initWithAnalyticsModule:");
    id vc = nil;
    @try {
        id obj = [VC alloc];
        if ([obj respondsToSelector:iam]) vc = ((id(*)(id,SEL,id))objc_msgSend)(obj, iam, nil);
        else if ([obj respondsToSelector:iwc]) vc = ((id(*)(id,SEL,id,id))objc_msgSend)(obj, iwc, nil, session);
    } @catch (id e) { return [NSString stringWithFormat:@"init threw: %@", e]; }
    if (![vc isKindOfClass:UIViewController.class]) return @"could not construct VC (needs internal config)";
    @try {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        [top presentViewController:nav animated:YES completion:nil];
        MLOG("dogfooding settings VC presented"); return @"presented IGDogfoodingSettingsViewController";
    } @catch (id e) { return [NSString stringWithFormat:@"present threw: %@", e]; }
}

// +[IGURLHandler openInternalURL:presentationConfig:controller:animated:userSession:annotation:]
+ (NSString *)openInternalURLString:(NSString *)urlString {
    id session = [self session]; UIViewController *top = [self topVC];
    if (!session) return @"no live user session yet";
    Class C = NSClassFromString(@"IGURLHandler");
    SEL s = NSSelectorFromString(@"openInternalURL:presentationConfig:controller:animated:userSession:annotation:");
    if (!C || ![C respondsToSelector:s]) return @"IGURLHandler.openInternalURL not found";
    NSURL *url = [NSURL URLWithString:urlString];
    @try {
        BOOL ok = ((BOOL(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(C, s, url, nil, top, YES, session, nil);
        return ok ? [NSString stringWithFormat:@"opened internal URL: %@", urlString] : @"openInternalURL returned NO";
    } @catch (id e) { return [NSString stringWithFormat:@"openInternalURL threw: %@", e]; }
}
@end
