#import "SCIResolverScanner.h"
#import "SCIResolverSpecifierEntry.h"
#import "../Features/ExpFlags/SCIMachODexKitResolver.h"
#import <objc/runtime.h>

typedef NSString *(*SCIReportIMP)(id, SEL);
typedef NSArray<SCIResolverSpecifierEntry *> *(*SCIEntriesIMP)(id, SEL);

static SCIReportIMP orig_runMobileConfigSymbolReport = NULL;
static SCIReportIMP orig_runFullResolverReport = NULL;
static SCIEntriesIMP orig_allKnownSpecifierEntries = NULL;

static NSString *SCIMachoDexReportBlock(void) {
    SCIMachODexKitResolver *resolver = [SCIMachODexKitResolver sharedResolver];
    NSArray<NSString *> *lines = [resolver reportLines];
    NSDictionary<NSNumber *, NSString *> *names = [resolver allKnownSpecifierNames];

    NSMutableString *out = [NSMutableString stringWithString:
        @"MachoDex dynamic resolver\n"
         "mode = runtime symbol discovery + export trie + LC_SYMTAB + callsite string xref\n\n"];

    [out appendFormat:@"knownSpecifierNames=%lu reportLines=%lu\n\n",
     (unsigned long)names.count,
     (unsigned long)lines.count];

    if (names.count) {
        [out appendString:@"Known MobileConfig specifiers\n\n"];

        NSArray<NSNumber *> *keys = [[names allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            unsigned long long av = a.unsignedLongLongValue;
            unsigned long long bv = b.unsignedLongLongValue;
            if (av < bv) return NSOrderedAscending;
            if (av > bv) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        for (NSNumber *key in keys) {
            [out appendFormat:@"0x%016llx · %@\n",
             key.unsignedLongLongValue,
             names[key]];
        }

        [out appendString:@"\n"];
    }

    if (lines.count) {
        [out appendString:@"Resolver log\n\n"];
        for (NSString *line in lines) {
            [out appendFormat:@"%@\n", line];
        }
    }

    return out;
}

static NSString *hook_runMobileConfigSymbolReport(id self, SEL _cmd) {
    NSString *base = orig_runMobileConfigSymbolReport ? orig_runMobileConfigSymbolReport(self, _cmd) : @"";
    NSString *machoDex = SCIMachoDexReportBlock();

    return [NSString stringWithFormat:@"%@\n\n==============================\n\n%@",
            base ?: @"",
            machoDex ?: @""];
}

static NSString *hook_runFullResolverReport(id self, SEL _cmd) {
    NSString *base = orig_runFullResolverReport ? orig_runFullResolverReport(self, _cmd) : @"";
    NSString *machoDex = SCIMachoDexReportBlock();

    return [NSString stringWithFormat:@"%@\n\n==============================\n\n%@",
            base ?: @"",
            machoDex ?: @""];
}

static NSArray<SCIResolverSpecifierEntry *> *hook_allKnownSpecifierEntries(id self, SEL _cmd) {
    NSArray<SCIResolverSpecifierEntry *> *base = orig_allKnownSpecifierEntries ? orig_allKnownSpecifierEntries(self, _cmd) : @[];
    NSMutableDictionary<NSNumber *, SCIResolverSpecifierEntry *> *merged = [NSMutableDictionary dictionary];

    for (SCIResolverSpecifierEntry *entry in base) {
        if (!entry) continue;
        merged[@(entry.specifier)] = entry;
    }

    NSDictionary<NSNumber *, NSString *> *names = [[SCIMachODexKitResolver sharedResolver] allKnownSpecifierNames];

    [names enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSString *name, BOOL *stop) {
        SCIResolverSpecifierEntry *existing = merged[key];

        if (existing) {
            BOOL weak = !existing.name.length ||
                        [existing.name.lowercaseString containsString:@"unknown"] ||
                        [existing.name.lowercaseString containsString:@"callsite"] ||
                        [existing.name.lowercaseString hasPrefix:@"spec_0x"];

            if (weak && name.length) {
                existing.name = name;
                existing.source = [NSString stringWithFormat:@"%@ + MachoDex", existing.source ?: @"resolver"];
            }

            return;
        }

        SCIResolverSpecifierEntry *entry = [SCIResolverSpecifierEntry new];
        entry.specifier = key.unsignedLongLongValue;
        entry.name = name.length ? name : [NSString stringWithFormat:@"unknown 0x%016llx", key.unsignedLongLongValue];
        entry.source = @"MachoDex dynamic symbol";
        entry.suggestedValue = YES;

        merged[key] = entry;
    }];

    return [merged.allValues sortedArrayUsingComparator:^NSComparisonResult(SCIResolverSpecifierEntry *a, SCIResolverSpecifierEntry *b) {
        return [a.name compare:b.name options:NSCaseInsensitiveSearch];
    }];
}

static void SCIHookClassMethod(Class cls, SEL sel, IMP replacement, IMP *originalOut) {
    Method method = class_getClassMethod(cls, sel);
    if (!method) return;

    IMP old = method_setImplementation(method, replacement);
    if (originalOut) *originalOut = old;
}

__attribute__((constructor)) static void SCIInstallMachoDexScannerBridge(void) {
    Class cls = NSClassFromString(@"SCIResolverScanner");
    if (!cls) return;

    SCIHookClassMethod(cls,
                       @selector(runMobileConfigSymbolReport),
                       (IMP)hook_runMobileConfigSymbolReport,
                       (IMP *)&orig_runMobileConfigSymbolReport);

    SCIHookClassMethod(cls,
                       @selector(runFullResolverReport),
                       (IMP)hook_runFullResolverReport,
                       (IMP *)&orig_runFullResolverReport);

    SCIHookClassMethod(cls,
                       @selector(allKnownSpecifierEntries),
                       (IMP)hook_allKnownSpecifierEntries,
                       (IMP *)&orig_allKnownSpecifierEntries);

    NSLog(@"[RyukGram][MachoDex] SCIResolverScanner bridge installed");
}
