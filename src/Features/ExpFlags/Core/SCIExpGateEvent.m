#import "SCIExpGateEvent.h"

@implementation SCIExpGateObservation
@end

NSString *SCIExpGateKindName(SCIExpGateKind kind) {
    switch (kind) {
        case SCIExpGateKindCBoolBroker: return @"C broker";
        case SCIExpGateKindObjCBoolGetter: return @"ObjC getter";
        case SCIExpGateKindInternalUseCFunction: return @"InternalUse C";
        case SCIExpGateKindStartupConfigGetter: return @"StartupConfigs";
        case SCIExpGateKindUpdatePath: return @"Update path";
        case SCIExpGateKindOverridePath: return @"Override path";
        case SCIExpGateKindDogfoodUI: return @"Dogfood UI";
    }
}

NSString *SCIExpGateRiskName(SCIExpGateRisk risk) {
    switch (risk) {
        case SCIExpGateRiskSafeObserve: return @"observe";
        case SCIExpGateRiskSafeForce: return @"force-safe";
        case SCIExpGateRiskNeedsAllowlist: return @"allowlist";
        case SCIExpGateRiskObserveOnly: return @"observe-only";
        case SCIExpGateRiskCrashLikely: return @"crash-likely";
    }
}

static BOOL SCIContainsAny(NSString *s, NSArray<NSString *> *needles) {
    NSString *n = s.lowercaseString ?: @"";
    for (NSString *needle in needles) {
        if ([n containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

NSString *SCIExpGateCategoryForName(NSString *name, NSString *gateSymbol, NSString *callerDescription) {
    NSString *hay = [@[name ?: @"", gateSymbol ?: @"", callerDescription ?: @""] componentsJoinedByString:@" "];
    if (SCIContainsAny(hay, @[@"employee", @"dogfood", @"dogfooding", @"internal", @"test_user", @"devoptions", @"xav_switcher"])) return @"Dogfood/Internal";
    if (SCIContainsAny(hay, @[@"quicksnap", @"quick_snap", @"instant", @"instants", @"mshquicksnap", @"notestray"])) return @"QuickSnap/Instants";
    if (SCIContainsAny(hay, @[@"directnotes", @"direct_notes", @"friendmap", @"locationnotes", @"notes_tray"])) return @"Direct/Notes";
    if (SCIContainsAny(hay, @[@"prism", @"igdsprism", @"prismmenu"])) return @"Prism/UI";
    if (SCIContainsAny(hay, @[@"tabbar", @"homecoming", @"launcher", @"sundial", @"navigation"])) return @"TabBar/Homecoming";
    if (SCIContainsAny(hay, @[@"feed", @"reels", @"stories", @"storytray", @"explore"])) return @"Feed/Reels/Stories";
    if (SCIContainsAny(hay, @[@"mobileconfig", @"startupconfigs", @"easygating", @"override", @"refresh", @"updateconfigs"])) return @"MobileConfig Infra";
    return @"Unknown";
}

SCIExpGateRisk SCIExpGateRiskForSymbol(NSString *gateSymbol, SCIExpGateKind kind) {
    NSString *s = gateSymbol.lowercaseString ?: @"";
    if (kind == SCIExpGateKindUpdatePath || [s containsString:@"tryupdateconfigs"] || [s containsString:@"forceupdateconfigs"] || [s containsString:@"refresh"]) {
        return SCIExpGateRiskObserveOnly;
    }
    if (kind == SCIExpGateKindOverridePath || [s containsString:@"setconfigoverrides"] || [s containsString:@"setoverride"] || [s containsString:@"clearoverrides"]) {
        return SCIExpGateRiskObserveOnly;
    }
    if ([s containsString:@"dasm"] || [s containsString:@"dvmadapter"]) return SCIExpGateRiskObserveOnly;
    if (kind == SCIExpGateKindObjCBoolGetter || kind == SCIExpGateKindStartupConfigGetter) return SCIExpGateRiskNeedsAllowlist;
    return SCIExpGateRiskSafeObserve;
}
