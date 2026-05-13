#import "TweakSettings.h"
#import "SCISetting.h"
#import "SCISymbol.h"
#import "SCIDogfoodingMainLauncher.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*origDNDFSections)(id, SEL) = NULL;

static BOOL DNDFHasTitle(NSArray *sections, NSString *title) {
    for (NSDictionary *section in sections) {
        if (![section isKindOfClass:NSDictionary.class]) continue;
        NSArray *rows = [section[@"rows"] isKindOfClass:NSArray.class] ? section[@"rows"] : nil;
        for (id rowObj in rows) {
            SCISetting *row = [rowObj isKindOfClass:SCISetting.class] ? rowObj : nil;
            if ([row.title isEqualToString:title]) return YES;
        }
    }
    return NO;
}

static NSArray *DNDFPatchedDeveloperSections(NSArray *navSections) {
    if (DNDFHasTitle(navSections, @"Open Direct Notes Dogfood Settings")) return navSections;
    NSMutableArray *sections = [navSections mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger i = 0; i < sections.count; i++) {
        NSDictionary *section = [sections[i] isKindOfClass:NSDictionary.class] ? sections[i] : nil;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : @"";
        if (![header isEqualToString:@"Native Dogfood Entry Points"]) continue;
        NSMutableArray *rows = [[section objectForKey:@"rows"] mutableCopy] ?: [NSMutableArray array];
        [rows addObject:[SCISetting buttonCellWithTitle:@"Open Direct Notes Dogfood Settings"
                                              subtitle:@"Opens the native Direct Notes dogfooding controller."
                                                  icon:[SCISymbol symbolWithName:@"note.text"]
                                                action:^{ RYDogOpenDirectNotesFrom(nil); }]];
        NSMutableDictionary *copy = [section mutableCopy];
        copy[@"rows"] = rows;
        sections[i] = copy;
        break;
    }
    return sections;
}

static NSArray *newDNDFSections(id self, SEL _cmd) {
    NSArray *orig = origDNDFSections ? origDNDFSections(self, _cmd) : @[];
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
            row.navSections = DNDFPatchedDeveloperSections(row.navSections ?: @[]);
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
    MSHookMessageEx(meta, sel, (IMP)newDNDFSections, (IMP *)&origDNDFSections);
}
