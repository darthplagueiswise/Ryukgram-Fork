#import "SCIInternalMenusLauncher.h"
#import "SCIDogfoodObjectRuntime.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>

#define MLOG(fmt,...) os_log(OS_LOG_DEFAULT,"[SCIGate] Menus " fmt,##__VA_ARGS__)

// ───────────────────────────────────────────────────────────────────────────
// Binary-validated entrypoints (Instagram 433, exec arm64):
//
//  +[IGDirectNotesDogfoodingSettingsStaticFuncs
//      notesDogfoodingSettingsOpenOnViewController:userSession:]   v32@0:8@16@24
//      → class method. No alloc. SAFE.
//
//  -[IGAutofillTokenizationInternalSettingsViewController initWithStyle:]  @24@0:8q16
//      → designated init takes a UITableViewStyle (NSInteger). SAFE w/o session.
//      (There is NO plain -init; calling [[cls alloc] init] CRASHES.)
//
//  -[IGSearchDebugSettingsViewController initWithAnalyticsModule:listRedesignEnabled:]   @28@0:8@16B24
//  -[IGStoryStoreDebugSettingsViewController initWithAnalyticsModule:listRedesignEnabled:] @28@0:8@16B24
//      → designated init takes (IGAnalyticsModule*, BOOL). These are Swift VCs:
//      passing nil for a non-optional Swift parameter traps → CRASH. We must
//      supply a real analyticsModule, obtained from +[IGAnalyticsModule moduleForName:].
//
//  +[IGAnalyticsModule moduleForName:]   @24@0:8@16   → factory, validated (24 xrefs).
// ───────────────────────────────────────────────────────────────────────────

static UIViewController *SCITopVC(void)  { return [SCIDogfoodObjectRuntime topViewController]; }
static id               SCISession(void) { return [SCIDogfoodObjectRuntime activeUserSession]; }

static UINavigationController *SCINavFor(UIViewController *vc) {
    if (!vc) return nil;
    if ([vc isKindOfClass:UINavigationController.class]) return (UINavigationController *)vc;
    return vc.navigationController;
}

// Build a real IGAnalyticsModule so Swift inits don't trap on a nil parameter.
static id SCIAnalyticsModule(void) {
    Class C = NSClassFromString(@"IGAnalyticsModule");
    if (!C) return nil;
    SEL s = NSSelectorFromString(@"moduleForName:");
    if (![C respondsToSelector:s]) return nil;
    @try {
        return ((id(*)(id,SEL,id))objc_msgSend)(C, s, @"dogfood_settings");
    } @catch (id) { return nil; }
}

static NSString *SCIPresentVC(UIViewController *vc, NSString *tag) {
    if (!vc || ![vc isKindOfClass:UIViewController.class])
        return [NSString stringWithFormat:@"%@ — init returned nil/non-VC", tag];
    UIViewController *top = SCITopVC();
    if (!top) return [NSString stringWithFormat:@"%@ — no topVC", tag];
    UINavigationController *nav = SCINavFor(top);
    if (nav) { [nav pushViewController:vc animated:YES]; return [NSString stringWithFormat:@"pushed %@", tag]; }
    UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:vc];
    wrap.modalPresentationStyle = UIModalPresentationFormSheet;
    [top presentViewController:wrap animated:YES completion:nil];
    return [NSString stringWithFormat:@"presented %@", tag];
}

// Resolve a class by ObjC name OR Swift mangled name.
static Class SCIClass(NSString *objcName, NSString *mangled) {
    Class c = NSClassFromString(objcName);
    if (c) return c;
    return mangled ? NSClassFromString(mangled) : nil;
}

@implementation SCIInternalMenusLauncher

// ── 1. Notes dogfooding (class method, no alloc — safe) ────────────────────

+ (NSString *)openDogfoodingNotesSettings {
    id session = SCISession();
    if (!session) return @"no live user session (open after login)";
    Class C = SCIClass(@"IGDirectNotesDogfoodingSettingsStaticFuncs",
                       @"_TtC31IGDirectNotesDogfoodingSettings42IGDirectNotesDogfoodingSettingsStaticFuncs");
    if (!C) return @"IGDirectNotesDogfoodingSettingsStaticFuncs not found";
    SEL s = NSSelectorFromString(@"notesDogfoodingSettingsOpenOnViewController:userSession:");
    if (![C respondsToSelector:s]) return @"notesDogfoodingSettingsOpen... selector missing";
    UIViewController *top = SCITopVC();
    UIViewController *presenter = SCINavFor(top) ?: top;
    if (!presenter) return @"no presenter VC";
    @try {
        ((void(*)(id,SEL,id,id))objc_msgSend)(C, s, presenter, session);
        MLOG("Notes dogfooding opened");
        return @"opened Notes dogfooding settings";
    } @catch (id e) { return [NSString stringWithFormat:@"Notes threw: %@", e]; }
}

// ── 2. Dogfooding Settings VC (needs captured config; runtime handles it) ──

+ (NSString *)openDogfoodingSettingsVC {
    @try {
        BOOL ok = [SCIDogfoodObjectRuntime tryOpenNativeDogfoodSettings];
        return ok ? @"opened native Dogfooding Settings"
                  : @"Dogfooding Settings VC needs a captured IGDogfoodingSettingsConfig "
                    "(open an authorized native dogfood surface first)";
    } @catch (id e) { return [NSString stringWithFormat:@"DogfoodVC threw: %@", e]; }
}

// ── 3. Autofill internal settings — initWithStyle: (NSInteger), no session ─

+ (NSString *)openAutofillInternalSettings {
    Class vcCls = SCIClass(@"IGAutofillTokenizationInternalSettingsViewController",
                           @"_TtC44IGAutofillTokenizationInternalSettingsPlugin52IGAutofillTokenizationInternalSettingsViewController");
    if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class])
        return @"AutofillInternalSettingsViewController not found";
    SEL si = NSSelectorFromString(@"initWithStyle:");
    if (![vcCls instancesRespondToSelector:si])
        return @"Autofill VC has no initWithStyle:";
    @try {
        // UITableViewStyleInsetGrouped = 2 (validated init: @24@0:8q16)
        UIViewController *vc = ((id(*)(id,SEL,NSInteger))objc_msgSend)([vcCls alloc], si, (NSInteger)2);
        NSString *r = SCIPresentVC(vc, @"AutofillInternalSettings");
        MLOG("Autofill: %{public}s", r.UTF8String);
        return r;
    } @catch (id e) { return [NSString stringWithFormat:@"Autofill threw: %@", e]; }
}

// ── 4. Search debug settings — initWithAnalyticsModule:listRedesignEnabled: ─

+ (NSString *)openSearchDebugSettings {
    Class vcCls = SCIClass(@"IGSearchDebugSettingsViewController",
                           @"_TtC21IGSearchDebugSettings35IGSearchDebugSettingsViewController");
    if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class])
        return @"IGSearchDebugSettingsViewController not found";
    SEL si = NSSelectorFromString(@"initWithAnalyticsModule:listRedesignEnabled:");
    if (![vcCls instancesRespondToSelector:si])
        return @"Search VC has no initWithAnalyticsModule:listRedesignEnabled:";
    id am = SCIAnalyticsModule();
    if (!am) return @"could not build IGAnalyticsModule (Swift init needs it; would crash with nil)";
    @try {
        UIViewController *vc = ((id(*)(id,SEL,id,BOOL))objc_msgSend)([vcCls alloc], si, am, NO);
        NSString *r = SCIPresentVC(vc, @"SearchDebugSettings");
        MLOG("SearchDebug: %{public}s", r.UTF8String);
        return r;
    } @catch (id e) { return [NSString stringWithFormat:@"SearchDebug threw: %@", e]; }
}

// ── 5. Story store debug settings — same init shape ────────────────────────

+ (NSString *)openStoryStoreDebugSettings {
    Class vcCls = SCIClass(@"IGStoryStoreDebugSettingsViewController",
                           @"_TtC26IGStoryStoresDebugSettings39IGStoryStoreDebugSettingsViewController");
    if (!vcCls || ![vcCls isSubclassOfClass:UIViewController.class])
        return @"IGStoryStoreDebugSettingsViewController not found";
    SEL si = NSSelectorFromString(@"initWithAnalyticsModule:listRedesignEnabled:");
    if (![vcCls instancesRespondToSelector:si])
        return @"StoryStore VC has no initWithAnalyticsModule:listRedesignEnabled:";
    id am = SCIAnalyticsModule();
    if (!am) return @"could not build IGAnalyticsModule (Swift init needs it; would crash with nil)";
    @try {
        UIViewController *vc = ((id(*)(id,SEL,id,BOOL))objc_msgSend)([vcCls alloc], si, am, NO);
        NSString *r = SCIPresentVC(vc, @"StoryStoreDebugSettings");
        MLOG("StoryStore: %{public}s", r.UTF8String);
        return r;
    } @catch (id e) { return [NSString stringWithFormat:@"StoryStore threw: %@", e]; }
}

// ── 6. Cascade ─────────────────────────────────────────────────────────────

+ (NSString *)openBestAvailableInternalMenu {
    for (NSString *r in @[
        [self openDogfoodingNotesSettings],
        [self openAutofillInternalSettings],
        [self openSearchDebugSettings],
        [self openStoryStoreDebugSettings],
        [self openDogfoodingSettingsVC],
        [self openInternalURLString:@"instagram://internal_settings"],
    ]) {
        if ([r hasPrefix:@"opened"] || [r hasPrefix:@"pushed"] || [r hasPrefix:@"presented"]) return r;
    }
    return @"All internal menu openers failed — are you logged in?";
}

// ── 7. URL handler fallback ────────────────────────────────────────────────

+ (NSString *)openInternalURLString:(NSString *)urlString {
    id session = SCISession();
    if (!session) return @"no live user session";
    Class C = NSClassFromString(@"IGURLHandler");
    SEL s = NSSelectorFromString(@"openInternalURL:presentationConfig:controller:animated:userSession:annotation:");
    if (!C || ![C respondsToSelector:s]) return @"IGURLHandler.openInternalURL not found";
    UIViewController *top = SCITopVC();
    if (!top) return @"no topVC";
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return @"bad URL";
    @try {
        BOOL ok = ((BOOL(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(C, s, url, nil, top, YES, session, nil);
        return ok ? [NSString stringWithFormat:@"opened: %@", urlString]
                  : [NSString stringWithFormat:@"openInternalURL returned NO for: %@", urlString];
    } @catch (id e) { return [NSString stringWithFormat:@"IGURLHandler threw: %@", e]; }
}

@end
