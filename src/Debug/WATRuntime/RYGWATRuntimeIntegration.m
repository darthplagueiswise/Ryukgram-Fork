#import "../../Settings/Sections/RYGSettingsSections.h"
#import "RYGWATRuntimeBrowserViewController.h"
#import <objc/runtime.h>

static IMP gRYGWATOriginalDebugNavCell = NULL;

static RYGSetting *RYGWATDebugNavCell(id self, SEL _cmd) {
    RYGSetting *setting = gRYGWATOriginalDebugNavCell
        ? ((RYGSetting *(*)(id, SEL))gRYGWATOriginalDebugNavCell)(self, _cmd)
        : nil;
    if (!setting) return setting;

    RYGSetting *runtimeCell = [RYGSetting buttonCellWithTitle:@"Runtime Browser · WAT Port"
                                                    subtitle:@"Live app-owned Mach-O catalog with ABI-validated typed overrides"
                                                        icon:[RYGSymbol symbolWithName:@"scope"]
                                                      action:^(void) {
        UIViewController *top = rygTopVC();
        if (!top) return;
        RYGWATRuntimeBrowserViewController *browser = [RYGWATRuntimeBrowserViewController new];
        UINavigationController *nav = top.navigationController;
        if (nav) {
            [nav pushViewController:browser animated:YES];
        } else {
            UINavigationController *wrapper = [[UINavigationController alloc] initWithRootViewController:browser];
            [top presentViewController:wrapper animated:YES completion:nil];
        }
    }];

    NSDictionary *runtimeSection = @{
        @"header": @"Runtime",
        @"footer": @"Lazy WAT port. Runtime discovery starts only after this browser is opened; persisted selector overrides are installed only by explicit user actions.",
        @"rows": @[ runtimeCell ]
    };

    NSMutableArray *sections = [setting.navSections mutableCopy] ?: [NSMutableArray array];
    BOOL alreadyInserted = NO;
    NSUInteger insertionIndex = sections.count;
    for (NSUInteger index = 0; index < sections.count; index++) {
        NSDictionary *section = [sections[index] isKindOfClass:NSDictionary.class] ? sections[index] : nil;
        NSString *header = [section[@"header"] isKindOfClass:NSString.class] ? section[@"header"] : nil;
        if ([header isEqualToString:@"Runtime"]) { alreadyInserted = YES; break; }
        if ([header isEqualToString:@"FLEX"]) { insertionIndex = index; break; }
    }
    if (!alreadyInserted) [sections insertObject:runtimeSection atIndex:insertionIndex];
    setting.navSections = sections;
    return setting;
}

@implementation RYGTweakSettings (RYGWATRuntimeIntegration)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method method = class_getClassMethod(self, @selector(debugNavCell));
        if (!method) return;
        gRYGWATOriginalDebugNavCell = method_setImplementation(method, (IMP)RYGWATDebugNavCell);
    });
}

@end
