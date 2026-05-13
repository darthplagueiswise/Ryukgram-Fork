#import "TweakSettings.h"
#import "SCIExpPersistedQueryViewController.h"
#import "../Features/ExpFlags/SCIPersistedQueryCatalog.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections_pq)(id, SEL);

static BOOL PQRowIsPersistedCatalog(SCISetting *row) {
    if (![row isKindOfClass:SCISetting.class]) return NO;
    if ([row.title isEqualToString:@"Persisted GraphQL Mapping"]) return YES;
    if ([row.title isEqualToString:@"Persisted Query Catalog"]) return YES;
    NSString *vc = row.navViewController ? NSStringFromClass(row.navViewController.class) : @"";
    return [vc isEqualToString:@"SCIExpPersistedQueryViewController"];
}

static SCISetting *PQCatalogRow(void) {
    return [SCISetting navigationCellWithTitle:@"Persisted GraphQL Mapping"
                                      subtitle:@"Imported igios persisted-query map, QuickSnap operations, dogfood operations and client_doc_id lookup."
                                          icon:[SCISymbol symbolWithName:@"doc.text.magnifyingglass"]
                                viewController:[SCIExpPersistedQueryViewController new]];
}

static NSDictionary *PQCatalogSection(void) {
    return @{
        @"header": @"Persisted GraphQL",
        @"footer": @"Loads the persisted query JSON once and indexes operation_name, hashes, client_doc_id and category. This avoids runtime framework scans for GraphQL mapping.",
        @"rows": @[PQCatalogRow()]
    };
}

static NSArray *PQSectionsWithCatalogInserted(NSArray *navSections) {
    NSMutableArray *sections = [navSections isKindOfClass:NSArray.class] ? [navSections mutableCopy] : [NSMutableArray array];

    for (NSDictionary *section in sections) {
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if (PQRowIsPersistedCatalog(row)) return sections;
        }
    }

    NSUInteger diagnosticsIndex = NSNotFound;
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:NSDictionary.class] ? sections[i] : nil;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if ([header localizedCaseInsensitiveContainsString:@"diagnostic"]) {
            diagnosticsIndex = i;
            break;
        }
    }

    if (diagnosticsIndex != NSNotFound) {
        NSDictionary *section = sections[diagnosticsIndex];
        NSMutableDictionary *newSection = [section mutableCopy];
        NSMutableArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? [section[@"rows"] mutableCopy] : [NSMutableArray array];
        [rows addObject:PQCatalogRow()];
        newSection[@"rows"] = rows;
        sections[diagnosticsIndex] = newSection;
    } else {
        [sections addObject:PQCatalogSection()];
    }

    return sections;
}

static NSArray *new_sections_pq(id self, SEL _cmd) {
    NSArray *orig = orig_sections_pq ? orig_sections_pq(self, _cmd) : @[];
    NSMutableArray *sections = [orig isKindOfClass:NSArray.class] ? [orig mutableCopy] : [NSMutableArray array];

    BOOL hasTopLevelCatalog = NO;
    BOOL insertedIntoDeveloper = NO;

    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:NSDictionary.class] ? sections[i] : nil;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        if (!rows.count) continue;

        NSMutableArray *newRows = [rows mutableCopy];
        BOOL changedRows = NO;

        for (NSUInteger r = 0; r < newRows.count; r++) {
            SCISetting *row = [newRows[r] isKindOfClass:SCISetting.class] ? newRows[r] : nil;
            if (!row) continue;

            if (PQRowIsPersistedCatalog(row)) hasTopLevelCatalog = YES;

            if ([row.title isEqualToString:@"Developer Mode"]) {
                row.navSections = PQSectionsWithCatalogInserted(row.navSections ?: @[]);
                newRows[r] = row;
                insertedIntoDeveloper = YES;
                changedRows = YES;
            }
        }

        if (changedRows) {
            NSMutableDictionary *newSection = [section mutableCopy];
            newSection[@"rows"] = newRows;
            sections[i] = newSection;
        }
    }

    if (!insertedIntoDeveloper && !hasTopLevelCatalog) {
        NSUInteger insertIndex = sections.count;
        if (insertIndex > 0) insertIndex -= 1;
        [sections insertObject:PQCatalogSection() atIndex:insertIndex];
    }

    [SCIPersistedQueryCatalog prewarmInBackground];
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;

    Class meta = object_getClass(cls);
    if (!meta) return;

    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;

    MSHookMessageEx(meta, sel, (IMP)new_sections_pq, (IMP *)&orig_sections_pq);
}
