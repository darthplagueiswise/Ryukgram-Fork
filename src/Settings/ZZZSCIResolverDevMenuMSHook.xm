#import "TweakSettings.h"
#import "SCIResolverReportViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_resolver_dev)(id, SEL);

static BOOL SCIResolverSectionAlreadyPresent(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]]) return NO;
    for (id obj in sections) {
        NSDictionary *section = [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
        NSString *header = [section[@"header"] isKindOfClass:[NSString class]] ? section[@"header"] : @"";
        if ([header isEqualToString:@"SCI Resolver"]) return YES;
    }
    return NO;
}

static NSDictionary *SCIResolverDevSection(void) {
    return @{
        @"header": @"SCI Resolver",
        @"footer": @"DexKit-style iOS resolver. View-only scanner: ObjC/Swift-visible classes, selectors, ivars, MobileConfig/EasyGating symbols and candidate ranking. No overrides are applied.",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"Resolver: Dogfood / Developer candidates"
                                       subtitle:@"Find likely Dogfooding, DeveloperOptions, MetaConfig, InternalSettings and Employee UI builders"
                                           icon:[SCISymbol symbolWithName:@"magnifyingglass"]
                                 viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindDogfoodDeveloper title:@"Dogfood / Developer candidates"]],
            [SCISetting navigationCellWithTitle:@"Resolver: MobileConfig symbols"
                                       subtitle:@"Check IG/MCI/METAExtensions/MSGC/EasyGating/MEM symbol availability and runtime class candidates"
                                           icon:[SCISymbol symbolWithName:@"point.3.connected.trianglepath.dotted"]
                                 viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindMobileConfigSymbols title:@"MobileConfig symbols"]],
            [SCISetting navigationCellWithTitle:@"Resolver: Full scan report"
                                       subtitle:@"Full view-only scan report combining Dogfood/Developer and MobileConfig candidates"
                                           icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                 viewController:[[SCIResolverReportViewController alloc] initWithKind:SCIResolverReportKindFull title:@"Full resolver report"]]
        ]
    };
}

static NSArray *SCIResolverNavSectionsByAddingResolver(NSArray *navSections) {
    if (![navSections isKindOfClass:[NSArray class]]) return navSections;
    if (SCIResolverSectionAlreadyPresent(navSections)) return navSections;

    NSMutableArray *mutable = [navSections mutableCopy];
    NSUInteger insertIndex = mutable.count;
    for (NSUInteger i = 0; i < mutable.count; i++) {
        NSDictionary *section = [mutable[i] isKindOfClass:[NSDictionary class]] ? mutable[i] : nil;
        NSString *header = [section[@"header"] isKindOfClass:[NSString class]] ? section[@"header"] : @"";
        if ([header isEqualToString:@"Flags Browser"]) {
            insertIndex = i;
            break;
        }
    }
    [mutable insertObject:SCIResolverDevSection() atIndex:insertIndex];
    return mutable;
}

static NSArray *SCIResolverSectionsByAddingDevResolver(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]]) return sections;

    NSMutableArray *outSections = [sections mutableCopy];
    for (NSUInteger s = 0; s < outSections.count; s++) {
        NSDictionary *section = [outSections[s] isKindOfClass:[NSDictionary class]] ? outSections[s] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changedRows = NO;
        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *setting = [newRows[r] isKindOfClass:[SCISetting class]] ? newRows[r] : nil;
            if (!setting || ![setting.title isEqualToString:@"DEV tests"]) continue;

            NSArray *oldNav = [setting.navSections isKindOfClass:[NSArray class]] ? setting.navSections : @[];
            NSArray *newNav = SCIResolverNavSectionsByAddingResolver(oldNav);
            if (newNav != oldNav) {
                setting.navSections = newNav;
                newRows[r] = setting;
                changedRows = YES;
            }
        }

        if (changedRows) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            outSections[s] = newSection;
        }
    }
    return outSections;
}

static NSArray *new_sections_resolver_dev(id self, SEL _cmd) {
    NSArray *orig = orig_sections_resolver_dev ? orig_sections_resolver_dev(self, _cmd) : @[];
    return SCIResolverSectionsByAddingDevResolver(orig);
}

__attribute__((constructor))
static void SCIResolverDevMenuMSHookInit(void) {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_resolver_dev, (IMP *)&orig_sections_resolver_dev);
}
