#import "TweakSettings.h"
#import "SCISetting.h"
#import "SCISymbol.h"
#import "SCINumericCatalogViewController.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*origNumericCatalogSections)(id, SEL) = NULL;

static BOOL SCIHasNumericCatalogRow(NSArray *sections) {
    for (NSDictionary *section in sections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        for (id item in rows) {
            SCISetting *row = [item isKindOfClass:SCISetting.class] ? item : nil;
            if ([row.title isEqualToString:@"Numeric Catalog"]) return YES;
        }
    }
    return NO;
}

static NSArray *SCIAddNumericCatalogRow(NSArray *navSections) {
    if (SCIHasNumericCatalogRow(navSections)) return navSections;
    NSMutableArray *sections = [navSections mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:NSDictionary.class] ? sections[i] : nil;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if (![header isEqualToString:@"Diagnostics"]) continue;
        NSMutableArray *rows = [[section objectForKey:@"rows"] mutableCopy] ?: [NSMutableArray array];
        [rows addObject:[SCISetting navigationCellWithTitle:@"Numeric Catalog"
                                                  subtitle:@"Import and browse generated numeric entries by group."
                                                      icon:[SCISymbol symbolWithName:@"number.square"]
                                            viewController:[SCINumericCatalogViewController new]]];
        NSMutableDictionary *copy = [section mutableCopy];
        copy[@"rows"] = rows;
        sections[i] = copy;
        break;
    }
    return sections;
}

static NSArray *newNumericCatalogSections(id self, SEL _cmd) {
    NSArray *orig = origNumericCatalogSections ? origNumericCatalogSections(self, _cmd) : @[];
    NSMutableArray *sections = [orig mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger s = 0; s < sections.count; s++) {
        NSDictionary *section = [sections[s] isKindOfClass:NSDictionary.class] ? sections[s] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;
        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changed = NO;
        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *row = [newRows[r] isKindOfClass:SCISetting.class] ? newRows[r] : nil;
            if (![row.title isEqualToString:@"Developer Mode"]) continue;
            row.navSections = SCIAddNumericCatalogRow(row.navSections ?: @[]);
            newRows[r] = row;
            changed = YES;
        }
        if (changed) {
            NSMutableDictionary *copy = [section mutableCopy];
            copy[@"rows"] = newRows;
            sections[s] = copy;
        }
    }
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    Class meta = cls ? object_getClass(cls) : Nil;
    SEL sel = @selector(sections);
    if (!meta || !class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)newNumericCatalogSections, (IMP *)&origNumericCatalogSections);
}
