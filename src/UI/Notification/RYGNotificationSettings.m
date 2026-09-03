#import "RYGNotificationSettings.h"
#import "RYGNotification.h"
#import "RYGNotificationPositionViewController.h"
#import "../../Settings/RYGSymbol.h"
#import "../../Utils.h"

@interface RYGNotificationSettings ()
+ (NSArray *)rygResetSection;
+ (void)rygResetAllNotificationPrefs;
@end

@implementation RYGNotificationSettings

#pragma mark - Menu builders

+ (UIMenu *)rygMenuWithKey:(NSString *)key entries:(NSArray<NSArray *> *)entries {
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
    return [self rygMenuWithKey:@"notif_style" entries:@[
        @[RYGLocalized(@"Minimal"),  @"minimal"],
        @[RYGLocalized(@"Colorful"), @"colorful"],
        @[RYGLocalized(@"Glow"),     @"glow"],
        @[RYGLocalized(@"Island"),   @"island"],
    ]];
}

+ (UIMenu *)defaultSurfaceMenu {
    return [self rygMenuWithKey:@"notif_default_surface" entries:@[
        @[RYGLocalized(@"Custom pill"),     @"pill"],
        @[RYGLocalized(@"IG native toast"), @"ig_native"],
    ]];
}

+ (UIMenu *)durationMenu {
    return [self rygMenuWithKey:@"notif_duration" entries:@[
        @[RYGLocalized(@"Short"),     @"0.5"],
        @[RYGLocalized(@"Normal"),    @"1.0"],
        @[RYGLocalized(@"Long"),      @"2.0"],
        @[RYGLocalized(@"Very long"), @"3.0"],
    ]];
}

+ (UIMenu *)maxVisibleMenu {
    return [self rygMenuWithKey:@"notif_max_visible" entries:@[
        @[@"1", @"1"],
        @[@"2", @"2"],
        @[@"3", @"3"],
    ]];
}

+ (UIMenu *)perActionMenuForActionInfo:(RYGNotificationActionInfo *)info {
    NSString *key = [@"notif_action_" stringByAppendingString:info.identifier];
    NSMutableArray *entries = [NSMutableArray new];
    [entries addObject:@[RYGLocalized(@"Default"),     @"default"]];
    [entries addObject:@[RYGLocalized(@"Custom pill"), @"pill"]];
    if (info.caps & RYGNotificationActionCapsAllowIG) {
        [entries addObject:@[RYGLocalized(@"IG native toast"), @"ig_native"]];
    }
    if (info.caps & RYGNotificationActionCapsAllowOff) {
        [entries addObject:@[RYGLocalized(@"Off"), @"off"]];
    }

    NSMutableArray *children = [[self rygMenuWithKey:key entries:entries].children mutableCopy];
    [children addObject:[self mirrorSubmenuForActionInfo:info]];
    return [UIMenu menuWithChildren:children];
}

// noTitle keeps the cell's accessory button showing the surface value.
+ (UIMenu *)mirrorSubmenuForActionInfo:(RYGNotificationActionInfo *)info {
    NSString *key = [@"notif_mirror_" stringByAppendingString:info.identifier];
    NSMutableArray *items = [NSMutableArray new];
    NSArray<NSArray *> *entries = @[
        @[RYGLocalized(@"On"),  @"on"],
        @[RYGLocalized(@"Off"), @"off"],
    ];
    for (NSArray *pair in entries) {
        [items addObject:[UICommand commandWithTitle:pair[0]
                                                image:nil
                                               action:@selector(menuChanged:)
                                         propertyList:@{ @"defaultsKey": key, @"value": pair[1], @"noTitle": @YES }]];
    }
    return [UIMenu menuWithTitle:RYGLocalized(@"Background mirror")
                           image:[UIImage systemImageNamed:@"bell.badge"]
                      identifier:nil
                         options:0
                        children:items];
}

#pragma mark - Sections

+ (NSArray *)rygPerActionSections {
    NSArray<NSString *> *categories = RYGNotificationCategoriesAll();
    NSMutableArray *sections = [NSMutableArray new];

    for (NSString *category in categories) {
        NSMutableArray *rows = [NSMutableArray new];
        for (RYGNotificationActionInfo *info in RYGNotificationActionsAll()) {
            if (![info.category isEqualToString:category]) continue;
            NSString *subtitle = (info.caps & RYGNotificationActionCapsProgress)
                ? RYGLocalized(@"Progress UI — pill or off only.")
                : @"";
            [rows addObject:[RYGSetting menuCellWithTitle:RYGLocalized(info.displayName)
                                                  subtitle:subtitle
                                                      menu:[self perActionMenuForActionInfo:info]]];
        }
        [sections addObject:@{ @"header": RYGLocalized(category), @"rows": rows }];
    }
    return sections;
}

+ (NSArray *)rygGlobalSections {
    RYGSetting *previewBtn = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Preview pill")
                                                     subtitle:RYGLocalized(@"Tap to cycle: info → success → warning → error")
                                                         icon:nil
                                                       action:^{
        static NSInteger cycle = 0;
        RYGNotificationTone tones[] = {
            RYGNotificationToneInfo, RYGNotificationToneSuccess,
            RYGNotificationToneWarning, RYGNotificationToneError,
        };
        [[RYGNotificationCenter shared] presentPreviewWithTone:tones[cycle++ % 4]];
    }];

    RYGSetting *downloadPreviewBtn = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Preview download pill")
                                                            subtitle:RYGLocalized(@"Tap to cycle between success and failure")
                                                                icon:nil
                                                              action:^{
        static BOOL fail = NO;
        [[RYGNotificationCenter shared] presentPreviewDownloadEndingWithError:fail];
        fail = !fail;
    }];

    RYGSetting *loadingPreviewBtn = [RYGSetting buttonCellWithTitle:RYGLocalized(@"Preview loading pill")
                                                            subtitle:RYGLocalized(@"Tap to cycle between success and failure")
                                                                icon:nil
                                                              action:^{
        static BOOL fail = NO;
        [[RYGNotificationCenter shared] presentPreviewLoadingEndingWithError:fail];
        fail = !fail;
    }];

    return @[
        @{
            @"header": @"",
            @"footer": RYGLocalized(@"Universal in-app notifications. All RyukGram feedback (downloads, copies, errors, success messages) routes through here."),
            @"rows": @[
                [RYGSetting switchCellWithTitle:RYGLocalized(@"Enable notifications")
                                       subtitle:RYGLocalized(@"Master switch. When off, no RyukGram pills or IG-native toasts are emitted.")
                                    defaultsKey:@"notif_master_enabled"],
            ]
        },
        @{
            @"header": RYGLocalized(@"Appearance"),
            @"rows": @[
                [RYGSetting menuCellWithTitle:RYGLocalized(@"Style")
                                      subtitle:RYGLocalized(@"Minimal: flat blur. Colorful: tinted by tone. Glow: colored halo. Island: dynamic-island capsule.")
                                          menu:[self styleMenu]],
                [RYGSetting navigationCellWithTitle:RYGLocalized(@"Position")
                                           subtitle:RYGLocalized(@"Drag the pill to position it")
                                               icon:nil
                                     viewController:[RYGNotificationPositionViewController new]],
                [RYGSetting menuCellWithTitle:RYGLocalized(@"Stack size")
                                      subtitle:RYGLocalized(@"How many pills can show at once before queueing.")
                                          menu:[self maxVisibleMenu]],
                [RYGSetting menuCellWithTitle:RYGLocalized(@"Duration")
                                      subtitle:RYGLocalized(@"Multiplies how long toasts stay on screen.")
                                          menu:[self durationMenu]],
                [RYGSetting switchCellWithTitle:RYGLocalized(@"Haptic feedback")
                                        subtitle:RYGLocalized(@"Vibration on success/error pills.")
                                     defaultsKey:@"notif_haptics"],
            ]
        },
        @{
            @"header": RYGLocalized(@"Preview"),
            @"rows": @[ previewBtn, downloadPreviewBtn, loadingPreviewBtn ]
        },
        @{
            @"header": RYGLocalized(@"Routing"),
            @"footer": RYGLocalized(@"For toast-style actions you can choose between our pill and IG's native bottom toast. Per-action overrides live below."),
            @"rows": @[
                [RYGSetting menuCellWithTitle:RYGLocalized(@"Default surface")
                                      subtitle:RYGLocalized(@"What to use when an action doesn't have its own override.")
                                          menu:[self defaultSurfaceMenu]],
            ]
        },
        @{
            @"header": RYGLocalized(@"System notifications"),
            @"footer": RYGLocalized(@"Uses Instagram's notification permission. Per-action overrides live in each action's menu under Background mirror; actions set to Off never mirror."),
            @"rows": @[
                [RYGSetting switchCellWithTitle:RYGLocalized(@"Mirror to notification centre")
                                       subtitle:RYGLocalized(@"While the app is in the background, toasts are delivered to the iOS notification centre instead so they aren't missed.")
                                    defaultsKey:@"notif_mirror_enabled"],
                [RYGSetting switchCellWithTitle:RYGLocalized(@"Show while app is open")
                                       subtitle:RYGLocalized(@"Also deliver mirrored notifications as system banners while you're using the app, not just in the background.")
                                    defaultsKey:@"notif_mirror_while_open"],
                [RYGSetting switchCellWithTitle:RYGLocalized(@"Clear when app opens")
                                       subtitle:RYGLocalized(@"Remove mirrored notifications from notification centre when you return to the app.")
                                    defaultsKey:@"notif_mirror_clear_on_open"],
            ]
        },
    ];
}

+ (void)rygResetAllNotificationPrefs {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *bundleId = NSBundle.mainBundle.bundleIdentifier ?: @"";
    for (NSString *key in [d persistentDomainForName:bundleId]) {
        if ([key hasPrefix:@"notif_"]) [d removeObjectForKey:key];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:@"RYGSettingsShouldReload" object:nil];
}

+ (NSArray *)rygResetSection {
    RYGSetting *reset = [RYGSetting actionCellWithTitle:RYGLocalized(@"Reset to defaults")
                                                  color:UIColor.systemRedColor
                                                 action:^{
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:RYGLocalized(@"Reset to defaults")
                             message:RYGLocalized(@"Appearance, routing, system notifications and every per-action override return to their defaults.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Reset") style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *_) { [self rygResetAllNotificationPrefs]; }]];
        [RYGUtils presentAlertInOwnWindow:a];
    }];
    return @[ @{ @"header": @"", @"rows": @[ reset ] } ];
}

+ (NSArray *)navSections {
    NSMutableArray *all = [NSMutableArray new];
    [all addObjectsFromArray:[self rygGlobalSections]];
    [all addObjectsFromArray:[self rygPerActionSections]];
    [all addObjectsFromArray:[self rygResetSection]];
    return all;
}

+ (RYGSetting *)notificationsNavCell {
    RYGSetting *cell = [RYGSetting navigationCellWithTitle:RYGLocalized(@"Notifications")
                                                  subtitle:@""
                                                      icon:[RYGSymbol symbolWithIGName:@"alert" fallback:@"bell.badge"]
                                               navSections:[self navSections]];
    cell.localSearch = YES;
    return cell;
}

@end
