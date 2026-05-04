#import "TweakSettings.h"
#import "SCIMobileConfigBrokerViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_mcbr_sections)(id, SEL);

static BOOL SCISectionAlreadyHasMCBroker(NSArray *sections) {
    for (NSDictionary *section in sections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if (!row) continue;
            if ([row.title isEqualToString:@"MobileConfig C Brokers v2"] || [NSStringFromClass([row.navViewController class]) isEqualToString:@"SCIMobileConfigBrokerViewController"]) return YES;
        }
    }
    return NO;
}

static NSArray *new_mcbr_sections(id self, SEL _cmd) {
    NSArray *orig = orig_mcbr_sections ? orig_mcbr_sections(self, _cmd) : @[];
    NSMutableArray *sections = [orig mutableCopy] ?: [NSMutableArray array];
    if (SCISectionAlreadyHasMCBroker(sections)) return sections;

    SCISetting *row = [SCISetting navigationCellWithTitle:@"MobileConfig C Brokers v2"
                                                 subtitle:@"C-function router for IGMobileConfig, EasyGating and MCI. Separate from DexKit ObjC getters."
                                                     icon:[SCISymbol symbolWithName:@"switch.2"]
                                           viewController:[SCIMobileConfigBrokerViewController new]];

    BOOL inserted = NO;
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:NSDictionary.class] ? sections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;
        for (id obj in rows) {
            SCISetting *candidate = [obj isKindOfClass:SCISetting.class] ? obj : nil;
            if ([candidate.title isEqualToString:@"Developer Mode"]) {
                NSMutableArray *newRows = [rows mutableCopy];
                [newRows addObject:row];
                NSMutableDictionary *newSection = [section mutableCopy];
                newSection[@"rows"] = newRows;
                sections[i] = newSection;
                inserted = YES;
                break;
            }
        }
        if (inserted) break;
    }

    if (!inserted) {
        [sections insertObject:@{@"header": @"Developer Tools", @"rows": @[row]} atIndex:sections.count > 0 ? sections.count - 1 : 0];
    }
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    SEL sel = @selector(sections);
    if (!meta || !class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_mcbr_sections, (IMP *)&orig_mcbr_sections);
}
