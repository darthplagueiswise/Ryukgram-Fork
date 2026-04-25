#import "TweakSettings.h"
#import "SCIMobileConfigSymbolObserverViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_mc_symbol_menu)(id, SEL);

static BOOL SCISectionRowsContainTitle(NSArray *rows, NSString *title) {
    for (id rowObj in rows) {
        if (![rowObj isKindOfClass:[SCISetting class]]) continue;
        SCISetting *row = (SCISetting *)rowObj;
        if ([row.title isEqualToString:title]) return YES;
    }
    return NO;
}

static SCISetting *SCIMCSymbolObserverRow(void) {
    return [SCISetting navigationCellWithTitle:@"MobileConfig symbol observer"
                                      subtitle:@"Filtered view-only tabs for MCI, METAExtensions, MCQMEM, and MEM boolean calls"
                                          icon:[SCISymbol symbolWithName:@"eye"]
                                viewController:[SCIMobileConfigSymbolObserverViewController new]];
}

static NSArray *new_sections_mc_symbol_menu(id self, SEL _cmd) {
    NSArray *orig = orig_sections_mc_symbol_menu ? orig_sections_mc_symbol_menu(self, _cmd) : @[];
    NSMutableArray *sections = [orig mutableCopy] ?: [NSMutableArray array];

    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:[NSDictionary class]] ? sections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:[NSArray class]] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changedTopSection = NO;

        for (NSUInteger r = 0; r < newRows.count; r++) {
            id rowObj = newRows[r];
            if (![rowObj isKindOfClass:[SCISetting class]]) continue;
            SCISetting *row = (SCISetting *)rowObj;
            if (![row.title isEqualToString:@"Experimental"]) continue;

            NSArray *navSections = [row.navSections isKindOfClass:[NSArray class]] ? row.navSections : @[];
            NSMutableArray *newNavSections = [navSections mutableCopy] ?: [NSMutableArray array];
            BOOL inserted = NO;

            for (NSUInteger s = 0; s < newNavSections.count; s++) {
                NSDictionary *navSection = [newNavSections[s] isKindOfClass:[NSDictionary class]] ? newNavSections[s] : nil;
                NSString *header = [navSection[@"header"] isKindOfClass:[NSString class]] ? navSection[@"header"] : @"";
                if (![header isEqualToString:@"Flags browser"]) continue;

                NSArray *navRows = [navSection[@"rows"] isKindOfClass:[NSArray class]] ? navSection[@"rows"] : @[];
                if (SCISectionRowsContainTitle(navRows, @"MobileConfig symbol observer")) return sections;

                NSMutableArray *newNavRows = [navRows mutableCopy] ?: [NSMutableArray array];
                [newNavRows addObject:SCIMCSymbolObserverRow()];

                NSMutableDictionary *newNavSection = [navSection mutableCopy];
                newNavSection[@"rows"] = newNavRows;
                newNavSections[s] = newNavSection;
                inserted = YES;
                break;
            }

            if (!inserted) {
                [newNavSections addObject:@{
                    @"header": @"MobileConfig observers",
                    @"footer": @"View-only filtered tabs for the extra MobileConfig C boolean observers.",
                    @"rows": @[ SCIMCSymbolObserverRow() ]
                }];
            }

            row.navSections = newNavSections;
            newRows[r] = row;
            changedTopSection = YES;
            break;
        }

        if (changedTopSection) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            sections[i] = newSection;
            break;
        }
    }

    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections_mc_symbol_menu, (IMP *)&orig_sections_mc_symbol_menu);
}
