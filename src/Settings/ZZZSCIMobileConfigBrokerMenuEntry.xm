#import "TweakSettings.h"
#import "SCIMobileConfigBrokerViewController.h"
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_mcb_sections)(id, SEL);

static BOOL MCBRowExists(NSArray *sections) {
    for (NSDictionary *section in sections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        for (id obj in rows) {
            SCISetting *row = [obj isKindOfClass:SCISetting.class] ? obj : nil;
            if ([row.title isEqualToString:@"MC Brokers v2"] || [row.title isEqualToString:@"MobileConfig Brokers v2"]) return YES;
            NSString *vc = row.navViewController ? NSStringFromClass(row.navViewController.class) : @"";
            if ([vc isEqualToString:@"SCIMobileConfigBrokerViewController"]) return YES;
        }
    }
    return NO;
}

static SCISetting *MCBRow(void) {
    return [SCISetting navigationCellWithTitle:@"MC Brokers v2"
                                      subtitle:@"C broker router for FBSharedFramework MobileConfig/EasyGating: mcbr:<id> overrides, mcob:<id> observed."
                                          icon:[SCISymbol symbolWithName:@"switch.2"]
                                viewController:[SCIMobileConfigBrokerViewController new]];
}

static NSArray *MCBAppendToDeveloperMode(NSArray *sections) {
    if (MCBRowExists(sections)) return sections;
    NSMutableArray *out = [sections mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger s = 0; s < out.count; s++) {
        NSDictionary *section = [out[s] isKindOfClass:NSDictionary.class] ? out[s] : nil;
        NSMutableArray *rows = [[section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : @[] mutableCopy];
        BOOL changedRows = NO;
        for (NSUInteger r = 0; r < rows.count; r++) {
            SCISetting *row = [rows[r] isKindOfClass:SCISetting.class] ? rows[r] : nil;
            if (![row.title isEqualToString:@"Developer Mode"]) continue;
            NSMutableArray *nav = [[row.navSections isKindOfClass:NSArray.class] ? row.navSections : @[] mutableCopy];
            [nav addObject:@{
                @"header": @"MobileConfig / EasyGating C Brokers",
                @"footer": @"Separated from DexKit ObjC getter scanner. Installs real-body C hooks only for saved overrides or explicit pass-through observer toggles.",
                @"rows": @[MCBRow()]
            }];
            row.navSections = nav;
            rows[r] = row;
            changedRows = YES;
            break;
        }
        if (changedRows) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = rows;
            out[s] = newSection;
            return out;
        }
    }

    // Fallback if the simplified Developer Mode section was not installed yet.
    [out addObject:@{
        @"header": @"Developer Tools",
        @"rows": @[MCBRow()]
    }];
    return out;
}

static NSArray *new_mcb_sections(id self, SEL _cmd) {
    NSArray *orig = orig_mcb_sections ? orig_mcb_sections(self, _cmd) : @[];
    return MCBAppendToDeveloperMode(orig);
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    Class meta = cls ? object_getClass(cls) : Nil;
    SEL sel = @selector(sections);
    if (!meta || !class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_mcb_sections, (IMP *)&orig_mcb_sections);
}
