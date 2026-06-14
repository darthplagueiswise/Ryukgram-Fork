#import "SCINotificationSettings.h"
#import "SCINotification.h"
#import "../../Settings/SCISymbol.h"

@implementation SCINotificationSettings

#pragma mark - Menu builders

+ (UIMenu *)sciMenuWithKey:(NSString *)key entries:(NSArray<NSArray *> *)entries {
    NSMutableArray *items = [NSMutableArray new];
    for (NSArray *pair in entries) {
        [items addObject:[UICommand commandWithTitle:pair[0]
                                                image:nil
                                               action:@selector(menuChanged:)
                                         propertyList:@{ @"defaultsKey": key, @"value": pair[1] }]];
    }
    return [UIMenu menuWithChildren:items];
}

+ (UIMenu *)styleMenu {
    return [self sciMenuWithKey:@"notif_style" entries:@[
        @[SCILocalized(@"Minimal"),  @"minimal"],
        @[SCILocalized(@"Colorful"), @"colorful"],
        @[SCILocalized(@"Glow"),     @"glow"],
        @[SCILocalized(@"Island"),   @"island"],
    ]];
}

+ (UIMenu *)positionMenu {
    return [self sciMenuWithKey:@"notif_position" entries:@[
        @[SCILocalized(@"Top"),    @"top"],
        @[SCILocalized(@"Bottom"), @"bottom"],
    ]];
}

+ (UIMenu *)defaultSurfaceMenu {
    return [self sciMenuWithKey:@"notif_default_surface" entries:@[
        @[SCILocalized(@"Custom pill"),     @"pill"],
        @[SCILocalized(@"IG native toast"), @"ig_native"],
    ]];
}

+ (UIMenu *)durationMenu {
    return [self sciMenuWithKey:@"notif_duration" entries:@[
        @[SCILocalized(@"Short"),     @"0.5"],
        @[SCILocalized(@"Normal"),    @"1.0"],
        @[SCILocalized(@"Long"),      @"2.0"],
        @[SCILocalized(@"Very long"), @"3.0"],
    ]];
}

+ (UIMenu *)maxVisibleMenu {
    return [self sciMenuWithKey:@"notif_max_visible" entries:@[
        @[@"1", @"1"],
        @[@"2", @"2"],
        @[@"3", @"3"],
    ]];
}

+ (UIMenu *)perActionMenuForActionInfo:(SCINotificationActionInfo *)info {
    NSString *key = [@"notif_action_" stringByAppendingString:info.identifier];
    NSMutableArray *entries = [NSMutableArray new];
    [entries addObject:@[SCILocalized(@"Default"),     @"default"]];
    [entries addObject:@[SCILocalized(@"Custom pill"), @"pill"]];
    if (info.caps & SCINotificationActionCapsAllowIG) {
        [entries addObject:@[SCILocalized(@"IG native toast"), @"ig_native"]];
    }
    if (info.caps & SCINotificationActionCapsAllowOff) {
        [entries addObject:@[SCILocalized(@"Off"), @"off"]];
    }

    NSMutableArray *children = [[self sciMenuWithKey:key entries:entries].children mutableCopy];
    [children addObject:[self mirrorSubmenuForActionInfo:info]];
    return [UIMenu menuWithChildren:children];
}

// noTitle keeps the cell's accessory button showing the surface value.
+ (UIMenu *)mirrorSubmenuForActionInfo:(SCINotificationActionInfo *)info {
    NSString *key = [@"notif_mirror_" stringByAppendingString:info.identifier];
    NSMutableArray *items = [NSMutableArray new];
    NSArray<NSArray *> *entries = @[
        @[SCILocalized(@"On"),  @"on"],
        @[SCILocalized(@"Off"), @"off"],
    ];
    for (NSArray *pair in entries) {
        [items addObject:[UICommand commandWithTitle:pair[0]
                                                image:nil
                                               action:@selector(menuChanged:)
                                         propertyList:@{ @"defaultsKey": key, @"value": pair[1], @"noTitle": @YES }]];
    }
    return [UIMenu menuWithTitle:SCILocalized(@"Background mirror")
                           image:[UIImage systemImageNamed:@"bell.badge"]
                      identifier:nil
                         options:0
                        children:items];
}

#pragma mark - Sections

+ (NSArray *)sciPerActionSections {
    NSArray<NSString *> *categories = SCINotificationCategoriesAll();
    NSMutableArray *sections = [NSMutableArray new];

    for (NSString *category in categories) {
        NSMutableArray *rows = [NSMutableArray new];
        for (SCINotificationActionInfo *info in SCINotificationActionsAll()) {
            if (![info.category isEqualToString:category]) continue;
            NSString *subtitle = (info.caps & SCINotificationActionCapsProgress)
                ? SCILocalized(@"Progress UI — pill or off only.")
                : @"";
            [rows addObject:[SCISetting menuCellWithTitle:SCILocalized(info.displayName)
                                                  subtitle:subtitle
                                                      menu:[self perActionMenuForActionInfo:info]]];
        }
        [sections addObject:@{ @"header": SCILocalized(category), @"rows": rows }];
    }
    return sections;
}

+ (NSArray *)sciGlobalSections {
    SCISetting *previewBtn = [SCISetting buttonCellWithTitle:SCILocalized(@"Preview pill")
                                                     subtitle:SCILocalized(@"Tap to cycle: info → success → warning → error")
                                                         icon:nil
                                                       action:^{
        static NSInteger cycle = 0;
        SCINotificationTone tones[] = {
            SCINotificationToneInfo, SCINotificationToneSuccess,
            SCINotificationToneWarning, SCINotificationToneError,
        };
        [[SCINotificationCenter shared] presentPreviewWithTone:tones[cycle++ % 4]];
    }];

    SCISetting *downloadPreviewBtn = [SCISetting buttonCellWithTitle:SCILocalized(@"Preview download pill")
                                                            subtitle:SCILocalized(@"Tap to cycle between success and failure")
                                                                icon:nil
                                                              action:^{
        static BOOL fail = NO;
        [[SCINotificationCenter shared] presentPreviewDownloadEndingWithError:fail];
        fail = !fail;
    }];

    SCISetting *loadingPreviewBtn = [SCISetting buttonCellWithTitle:SCILocalized(@"Preview loading pill")
                                                            subtitle:SCILocalized(@"Tap to cycle between success and failure")
                                                                icon:nil
                                                              action:^{
        static BOOL fail = NO;
        [[SCINotificationCenter shared] presentPreviewLoadingEndingWithError:fail];
        fail = !fail;
    }];

    return @[
        @{
            @"header": @"",
            @"footer": SCILocalized(@"Universal in-app notifications. All RyukGram feedback (downloads, copies, errors, success messages) routes through here."),
            @"rows": @[
                [SCISetting switchCellWithTitle:SCILocalized(@"Enable notifications")
                                       subtitle:SCILocalized(@"Master switch. When off, no RyukGram pills or IG-native toasts are emitted.")
                                    defaultsKey:@"notif_master_enabled"],
            ]
        },
        @{
            @"header": SCILocalized(@"Appearance"),
            @"rows": @[
                [SCISetting menuCellWithTitle:SCILocalized(@"Style")
                                      subtitle:SCILocalized(@"Minimal: flat blur. Colorful: tinted by tone. Glow: colored halo. Island: dynamic-island capsule.")
                                          menu:[self styleMenu]],
                [SCISetting menuCellWithTitle:SCILocalized(@"Position")
                                      subtitle:SCILocalized(@"Top slides down, bottom slides up.")
                                          menu:[self positionMenu]],
                [SCISetting menuCellWithTitle:SCILocalized(@"Stack size")
                                      subtitle:SCILocalized(@"How many pills can show at once before queueing.")
                                          menu:[self maxVisibleMenu]],
                [SCISetting menuCellWithTitle:SCILocalized(@"Duration")
                                      subtitle:SCILocalized(@"Multiplies how long toasts stay on screen.")
                                          menu:[self durationMenu]],
                [SCISetting switchCellWithTitle:SCILocalized(@"Haptic feedback")
                                        subtitle:SCILocalized(@"Vibration on success/error pills.")
                                     defaultsKey:@"notif_haptics"],
                previewBtn,
                downloadPreviewBtn,
                loadingPreviewBtn,
            ]
        },
        @{
            @"header": SCILocalized(@"Routing"),
            @"footer": SCILocalized(@"For toast-style actions you can choose between our pill and IG's native bottom toast. Per-action overrides live below."),
            @"rows": @[
                [SCISetting menuCellWithTitle:SCILocalized(@"Default surface")
                                      subtitle:SCILocalized(@"What to use when an action doesn't have its own override.")
                                          menu:[self defaultSurfaceMenu]],
            ]
        },
        @{
            @"header": SCILocalized(@"System notifications"),
            @"footer": SCILocalized(@"Uses Instagram's notification permission. Per-action overrides live in each action's menu under Background mirror; actions set to Off never mirror."),
            @"rows": @[
                [SCISetting switchCellWithTitle:SCILocalized(@"Mirror to notification centre")
                                       subtitle:SCILocalized(@"While the app is in the background, toasts are delivered to the iOS notification centre instead so they aren't missed.")
                                    defaultsKey:@"notif_mirror_enabled"],
                [SCISetting switchCellWithTitle:SCILocalized(@"Clear when app opens")
                                       subtitle:SCILocalized(@"Remove mirrored notifications from notification centre when you return to the app.")
                                    defaultsKey:@"notif_mirror_clear_on_open"],
            ]
        },
    ];
}

+ (NSArray *)navSections {
    NSMutableArray *all = [NSMutableArray new];
    [all addObjectsFromArray:[self sciGlobalSections]];
    [all addObjectsFromArray:[self sciPerActionSections]];
    return all;
}

+ (SCISetting *)notificationsNavCell {
    return [SCISetting navigationCellWithTitle:SCILocalized(@"Notifications")
                                       subtitle:@""
                                           icon:[SCISymbol symbolWithIGName:@"alert" fallback:@"bell.badge"]
                                    navSections:[self navSections]];
}

@end
