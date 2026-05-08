#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "SCIMobileConfigBrokerStore.h"

static NSString * const kSGPending = @"sci.startupguard.pending";
static NSString * const kSGSignature = @"sci.startupguard.signature";
static NSString * const kSGStartedAt = @"sci.startupguard.started_at";
static NSString * const kSGCount = @"sci.startupguard.count";
static NSString * const kSGReport = @"sci.startupguard.last_report";
static NSString * const kSGReportID = @"sci.startupguard.last_report_id";
static NSString * const kSGShownID = @"sci.startupguard.shown_report_id";
static NSString * const kSGDisabled = @"sci.startupguard.last_disabled";
static NSString * const kSGLog = @"sci.startupguard.event_log";

static const NSInteger kSGTrip = 3;
static const NSTimeInterval kSGStableDelay = 20.0;
static const NSTimeInterval kSGWindow = 300.0;
static BOOL gSGWriting = NO;

static NSUserDefaults *SGDefaults(void) { return [NSUserDefaults standardUserDefaults]; }

static NSArray<NSString *> *SGPrefKeys(void) {
    static NSArray<NSString *> *a = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        a = @[
            @"sci_exp_mc_hooks_enabled",
            @"liquid_glass_buttons",
            @"liquid_glass_surfaces",
            @"teen_app_icons",
            @"igt_homecoming",
            @"igt_quicksnap",
            @"igt_directnotes_friendmap",
            @"igt_directnotes_audio_reply",
            @"igt_directnotes_avatar_reply",
            @"igt_directnotes_gifs_reply",
            @"igt_directnotes_photo_reply",
            @"igt_prism",
            @"igt_reels_first",
            @"igt_friends_feed",
            @"igt_tab_swiping",
            @"igt_audio_ramping",
            @"igt_feed_culling",
            @"igt_feed_dedup",
            @"igt_pull_to_carrera",
            @"igt_screenshot_block",
            @"igt_employee",
            @"igt_internal"
        ];
    });
    return a;
}

static NSString *SGNow(void) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss 'UTC'";
    return [f stringFromDate:[NSDate date]] ?: @"";
}

static NSArray<NSString *> *SGActiveItems(void) {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    @try {
        [SCIMobileConfigBrokerStore registerDefaultsAndMigrate];
        for (NSString *k in [SCIMobileConfigBrokerStore activeOverrideKeys]) if (k.length) [set addObject:k];
        for (NSString *bid in [SCIMobileConfigBrokerStore enabledHookBrokerIDs]) if (bid.length) [set addObject:[@"hook:" stringByAppendingString:bid]];
    } @catch (id e) { NSLog(@"[RyukGram][StartupGuard] broker scan exception: %@", e); }
    NSUserDefaults *ud = SGDefaults();
    for (NSString *key in SGPrefKeys()) {
        @try { if ([ud boolForKey:key]) [set addObject:[@"pref:" stringByAppendingString:key]]; } @catch (__unused id e) {}
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *SGSignature(NSArray<NSString *> *items) { return items.count ? [items componentsJoinedByString:@"|"] : @""; }

static NSString *SGLabel(NSString *item) {
    if ([item hasPrefix:@"mcbr:"]) {
        NSDictionary *m = nil;
        @try { m = [SCIMobileConfigBrokerStore resolvedMetadataForOverrideKey:item]; } @catch (__unused id e) {}
        NSString *name = @"";
        for (NSString *k in @[@"resolvedName", @"name", @"title", @"label", @"stableID", @"alias"]) {
            id v = m[k];
            if ([v isKindOfClass:NSString.class] && [v length]) { name = v; break; }
        }
        NSString *state = @"";
        @try { state = [SCIMobileConfigBrokerStore overrideLabelForOverrideKey:item] ?: @""; } @catch (__unused id e) {}
        NSMutableString *label = [NSMutableString stringWithString:item ?: @"?"];
        if (name.length) [label appendFormat:@" · %@", name];
        if (state.length) [label appendFormat:@" · %@", state];
        return label;
    }
    return item ?: @"?";
}

static NSArray<NSString *> *SGLabels(NSArray<NSString *> *items) { NSMutableArray *out = [NSMutableArray array]; for (NSString *item in items) [out addObject:SGLabel(item)]; return out; }

static void SGLog(NSString *event, NSString *sig, NSArray<NSString *> *items) {
    NSUserDefaults *ud = SGDefaults();
    NSMutableArray *log = [[ud arrayForKey:kSGLog] mutableCopy] ?: [NSMutableArray array];
    [log addObject:@{@"time": SGNow(), @"event": event ?: @"?", @"signature": sig ?: @"", @"items": items ?: @[]}];
    while (log.count > 30) [log removeObjectAtIndex:0];
    [ud setObject:log forKey:kSGLog];
}

static void SGDisable(NSArray<NSString *> *items) {
    NSUserDefaults *ud = SGDefaults();
    for (NSString *item in items) {
        @try {
            if ([item hasPrefix:@"mcbr:"]) [SCIMobileConfigBrokerStore setOverrideValue:nil forKey:item];
            else if ([item hasPrefix:@"hook:"]) { NSString *bid = [item substringFromIndex:5]; if (bid.length) [SCIMobileConfigBrokerStore setBrokerHookEnabled:NO brokerID:bid]; }
            else if ([item hasPrefix:@"pref:"]) { NSString *key = [item substringFromIndex:5]; if (key.length) [ud setBool:NO forKey:key]; }
        } @catch (id e) { NSLog(@"[RyukGram][StartupGuard] disable exception %@: %@", item, e); }
    }
    [ud synchronize];
}

static void SGTrip(NSArray<NSString *> *items, NSString *sig, NSInteger count) {
    NSArray *labels = SGLabels(items);
    NSMutableString *r = [NSMutableString stringWithFormat:@"StartupGuard desativou overrides após %ld launches quebrados seguidos.\n\n", (long)count];
    [r appendFormat:@"Data: %@\nAssinatura: %@\n\n", SGNow(), sig ?: @""];
    [r appendString:@"Itens desativados:\n"];
    for (NSString *label in labels) [r appendFormat:@"• %@\n", label];
    [r appendString:@"\nDebug: sci.startupguard.last_report / sci.startupguard.event_log / sci.startupguard.last_disabled"];
    SGDisable(items);
    NSUserDefaults *ud = SGDefaults();
    [ud setObject:r forKey:kSGReport];
    [ud setObject:labels forKey:kSGDisabled];
    [ud setObject:([NSUUID UUID].UUIDString ?: SGNow()) forKey:kSGReportID];
    SGLog(@"trip-disable", sig, items);
    [ud synchronize];
    NSLog(@"[RyukGram][StartupGuard] tripped count=%ld items=%@", (long)count, labels);
}

static void SGArm(NSString *event) {
    if (gSGWriting) return;
    NSArray *items = SGActiveItems();
    NSString *sig = SGSignature(items);
    NSUserDefaults *ud = SGDefaults();
    NSString *old = [ud stringForKey:kSGSignature] ?: @"";
    gSGWriting = YES;
    if (!sig.length) {
        [ud setBool:NO forKey:kSGPending]; [ud setInteger:0 forKey:kSGCount]; [ud removeObjectForKey:kSGSignature]; [ud removeObjectForKey:kSGStartedAt];
    } else {
        if (![old isEqualToString:sig]) [ud setInteger:0 forKey:kSGCount];
        [ud setBool:YES forKey:kSGPending]; [ud setObject:sig forKey:kSGSignature]; [ud setDouble:NSDate.date.timeIntervalSince1970 forKey:kSGStartedAt];
    }
    SGLog(event ?: @"arm", sig, items);
    [ud synchronize];
    gSGWriting = NO;
}

static void SGEvaluateLaunch(void) {
    NSArray *items = SGActiveItems();
    NSString *sig = SGSignature(items);
    NSUserDefaults *ud = SGDefaults();
    BOOL pending = [ud boolForKey:kSGPending];
    NSString *oldSig = [ud stringForKey:kSGSignature] ?: @"";
    NSTimeInterval age = NSDate.date.timeIntervalSince1970 - [ud doubleForKey:kSGStartedAt];
    NSInteger count = 0;
    if (sig.length && pending && [oldSig isEqualToString:sig] && age >= 0 && age <= kSGWindow) count = [ud integerForKey:kSGCount] + 1;
    if (sig.length && count >= kSGTrip) { SGTrip(items, sig, count); items = SGActiveItems(); sig = SGSignature(items); count = 0; }
    gSGWriting = YES;
    if (!sig.length) {
        [ud setBool:NO forKey:kSGPending]; [ud setInteger:0 forKey:kSGCount]; [ud removeObjectForKey:kSGSignature]; [ud removeObjectForKey:kSGStartedAt];
    } else {
        [ud setBool:YES forKey:kSGPending]; [ud setObject:sig forKey:kSGSignature]; [ud setDouble:NSDate.date.timeIntervalSince1970 forKey:kSGStartedAt]; [ud setInteger:count forKey:kSGCount];
    }
    SGLog(@"launch-evaluate", sig, items);
    [ud synchronize];
    gSGWriting = NO;
}

static void SGStable(NSString *why) {
    NSUserDefaults *ud = SGDefaults();
    if (![ud boolForKey:kSGPending]) return;
    NSString *sig = [ud stringForKey:kSGSignature] ?: @"";
    gSGWriting = YES;
    [ud setBool:NO forKey:kSGPending];
    [ud setInteger:0 forKey:kSGCount];
    SGLog(why ?: @"stable", sig, SGActiveItems());
    [ud synchronize];
    gSGWriting = NO;
}

static UIViewController *SGTop(UIViewController *vc) {
    UIViewController *cur = vc;
    while (cur.presentedViewController) cur = cur.presentedViewController;
    if ([cur isKindOfClass:UINavigationController.class]) return SGTop(((UINavigationController *)cur).visibleViewController);
    if ([cur isKindOfClass:UITabBarController.class]) return SGTop(((UITabBarController *)cur).selectedViewController);
    return cur;
}

static UIViewController *SGRoot(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow && w.rootViewController) return w.rootViewController;
    }
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.rootViewController) return w.rootViewController;
    }
    return nil;
}

static void SGShowReport(void) {
    NSUserDefaults *ud = SGDefaults();
    NSString *rid = [ud stringForKey:kSGReportID] ?: @"";
    NSString *shown = [ud stringForKey:kSGShownID] ?: @"";
    NSString *report = [ud stringForKey:kSGReport] ?: @"";
    if (!rid.length || !report.length || [rid isEqualToString:shown]) return;
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIViewController *top = SGTop(SGRoot());
    if (!top || top.presentedViewController) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"RyukGram StartupGuard" message:report preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [ud setObject:rid forKey:kSGShownID]; [ud synchronize]; }]];
    [top presentViewController:a animated:YES completion:nil];
}

__attribute__((constructor))
static void SCIStartupGuardInit(void) {
    @autoreleasepool {
        SGEvaluateLaunch();
        dispatch_async(dispatch_get_main_queue(), ^{
            NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
            [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { SGStable(@"background-stable"); }];
            [nc addObserverForName:SCIMCBrokerStoreDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { if (!gSGWriting) SGArm(@"broker-change"); }];
            [nc addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) { if (gSGWriting) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGArm(@"defaults-change"); }); }];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowReport(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSGStableDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGStable(@"timer-stable"); });
        });
        NSLog(@"[RyukGram][StartupGuard] loaded trip=%ld stable=%.0fs", (long)kSGTrip, kSGStableDelay);
    }
}
