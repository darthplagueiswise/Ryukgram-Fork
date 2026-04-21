#import "TweakSettings.h"
#import <objc/runtime.h>
#import <substrate.h>

static NSArray *(*orig_sections)(id, SEL);

static NSDictionary *sciQuickSnapSection(void) {
    return @{
        @"header": @"",
        @"rows": @[
            [SCISetting navigationCellWithTitle:@"QuickSnap"
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithName:@"bolt.circle"]
                                    navSections:@[@{
                                        @"header": @"Experimental QuickSnap",
                                        @"footer": @"Toggle QuickSnap experiment hooks and notes tray eligibility gates.",
                                        @"rows": @[
                                            [SCISetting switchCellWithTitle:@"Enable QuickSnap"
                                                                   subtitle:@"Forces QuickSnap experiments and notes-tray eligibility"
                                                                defaultsKey:@"igt_quicksnap"
                                                             requiresRestart:YES]
                                        ]
                                    }]]
        ]
    };
}

static NSArray *new_sections(id self, SEL _cmd) {
    NSArray *orig = orig_sections ? orig_sections(self, _cmd) : @[];
    NSMutableArray *sections = [orig mutableCopy] ?: [NSMutableArray array];

    for (NSDictionary *section in sections) {
        NSArray *rows = [section isKindOfClass:[NSDictionary class]] ? section[@"rows"] : nil;
        for (id row in rows) {
            @try {
                NSString *title = [row valueForKey:@"title"];
                if ([title isKindOfClass:[NSString class]] && [title isEqualToString:@"QuickSnap"]) {
                    return sections;
                }
            } @catch (__unused id e) {}
        }
    }

    NSUInteger insertIndex = sections.count;
    if (insertIndex > 0) insertIndex -= 1;
    [sections insertObject:sciQuickSnapSection() atIndex:insertIndex];
    return sections;
}

%ctor {
    Class cls = NSClassFromString(@"SCITweakSettings");
    if (!cls) return;
    Class meta = object_getClass(cls);
    if (!meta) return;
    SEL sel = @selector(sections);
    if (!class_getInstanceMethod(meta, sel)) return;
    MSHookMessageEx(meta, sel, (IMP)new_sections, (IMP *)&orig_sections);
}
