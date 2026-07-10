#import "SCILockGroups.h"
#import "../Localization/SCILocalization.h"

NSString *const SCILockPrefsDidChangeNotification = @"SCILockPrefsDidChange";

NSString *const SCILockGroupApp             = @"app";
NSString *const SCILockGroupSettings        = @"settings";
NSString *const SCILockGroupGallery         = @"gallery";
NSString *const SCILockGroupKeepDeleted     = @"keep_deleted";
NSString *const SCILockGroupProfileAnalyzer = @"profile_analyzer";
NSString *const SCILockGroupMessagesTab     = @"messages_tab";
NSString *const SCILockGroupChats           = @"chats";
NSString *const SCILockGroupHiddenReveal    = @"hidden_reveal";

@interface SCILockGroupInfo ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *displayName;
@property (nonatomic, readwrite, copy) NSString *displayDescription;
@property (nonatomic, readwrite, copy) NSString *iconSymbol;
@property (nonatomic, readwrite) BOOL defaultIndependentSession;
@end

@implementation SCILockGroupInfo
+ (instancetype)id:(NSString *)i name:(NSString *)n desc:(NSString *)d icon:(NSString *)s indep:(BOOL)indep {
    SCILockGroupInfo *g = [self new];
    g.identifier = i; g.displayName = n; g.displayDescription = d;
    g.iconSymbol = s; g.defaultIndependentSession = indep;
    return g;
}
@end

NSArray<SCILockGroupInfo *> *SCILockAllGroups(void) {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            [SCILockGroupInfo id:SCILockGroupApp
                            name:SCILocalized(@"Instagram")
                            desc:SCILocalized(@"Prompt before Instagram opens")
                            icon:@"ig_icon_app_instagram_outline_24"
                           indep:YES],
            [SCILockGroupInfo id:SCILockGroupSettings
                            name:SCILocalized(@"Tweak settings")
                            desc:SCILocalized(@"Prompt before tweak settings open")
                            icon:@"ig_icon_settings_outline_24"
                           indep:NO],
            [SCILockGroupInfo id:SCILockGroupGallery
                            name:SCILocalized(@"Gallery")
                            desc:SCILocalized(@"Prompt before the gallery opens")
                            icon:@"ig_icon_photo_gallery_outline_24"
                           indep:NO],
            [SCILockGroupInfo id:SCILockGroupKeepDeleted
                            name:SCILocalized(@"Deleted messages log")
                            desc:SCILocalized(@"Prompt before the deleted-messages log opens")
                            icon:@"tray.fill"
                           indep:NO],
            [SCILockGroupInfo id:SCILockGroupProfileAnalyzer
                            name:SCILocalized(@"Profile Analyzer")
                            desc:SCILocalized(@"Prompt before Profile Analyzer opens")
                            icon:@"green_screen"
                           indep:NO],
            [SCILockGroupInfo id:SCILockGroupMessagesTab
                            name:SCILocalized(@"DM inbox")
                            desc:SCILocalized(@"Prompt on every entry to the DM inbox, including launch-to-messages")
                            icon:@"ig_icon_direct_prism_outline_24"
                           indep:YES],
            [SCILockGroupInfo id:SCILockGroupChats
                            name:SCILocalized(@"Per-chat locks")
                            desc:SCILocalized(@"Long-press a chat to lock it individually")
                            icon:@"ig_icon_direct_off_prism_outline_24"
                           indep:YES],
            [SCILockGroupInfo id:SCILockGroupHiddenReveal
                            name:SCILocalized(@"Reveal hidden chats")
                            desc:SCILocalized(@"Prompt before holding the inbox name reveals hidden chats")
                            icon:@"eye.slash"
                           indep:YES],
        ];
    });
    return all;
}

SCILockGroupInfo *SCILockGroupInfoFor(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary new];
        for (SCILockGroupInfo *g in SCILockAllGroups()) m[g.identifier] = g;
        map = [m copy];
    });
    return map[identifier];
}

NSString *SCILockPrefEnabled(NSString *gid)             { return [NSString stringWithFormat:@"lock_%@_enabled", gid]; }
NSString *SCILockPrefRelockOnBackground(NSString *gid)  { return [NSString stringWithFormat:@"lock_%@_relock_background", gid]; }
NSString *SCILockPrefIdleTimeout(NSString *gid)         { return [NSString stringWithFormat:@"lock_%@_idle_timeout", gid]; }
NSString *SCILockPrefIndependentSession(NSString *gid)  { return [NSString stringWithFormat:@"lock_%@_independent_session", gid]; }
NSString *SCILockPrefRelockOnDismiss(NSString *gid)     { return [NSString stringWithFormat:@"lock_%@_relock_on_dismiss", gid]; }
