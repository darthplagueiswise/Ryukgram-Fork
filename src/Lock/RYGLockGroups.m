#import "RYGLockGroups.h"
#import "../Localization/RYGLocalization.h"
#import "../UI/RYGFeatureIcons.h"

NSString *const RYGLockPrefsDidChangeNotification = @"RYGLockPrefsDidChange";

NSString *const RYGLockGroupApp             = @"app";
NSString *const RYGLockGroupSettings        = @"settings";
NSString *const RYGLockGroupGallery         = @"gallery";
NSString *const RYGLockGroupKeepDeleted     = @"keep_deleted";
NSString *const RYGLockGroupProfileAnalyzer = @"profile_analyzer";
NSString *const RYGLockGroupCallRecordings  = @"call_recordings";
NSString *const RYGLockGroupActivityLog     = @"activity_log";
NSString *const RYGLockGroupMessagesTab     = @"messages_tab";
NSString *const RYGLockGroupChats           = @"chats";
NSString *const RYGLockGroupHiddenReveal    = @"hidden_reveal";

@interface RYGLockGroupInfo ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *displayName;
@property (nonatomic, readwrite, copy) NSString *displayDescription;
@property (nonatomic, readwrite, copy) NSString *iconSymbol;
@property (nonatomic, readwrite) BOOL defaultIndependentSession;
@end

@implementation RYGLockGroupInfo
+ (instancetype)id:(NSString *)i name:(NSString *)n desc:(NSString *)d icon:(NSString *)s indep:(BOOL)indep {
    RYGLockGroupInfo *g = [self new];
    g.identifier = i; g.displayName = n; g.displayDescription = d;
    g.iconSymbol = s; g.defaultIndependentSession = indep;
    return g;
}
@end

NSArray<RYGLockGroupInfo *> *RYGLockAllGroups(void) {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            [RYGLockGroupInfo id:RYGLockGroupApp
                            name:RYGLocalized(@"Instagram")
                            desc:RYGLocalized(@"Prompt before Instagram opens")
                            icon:@"ig_icon_app_instagram_outline_24"
                           indep:YES],
            [RYGLockGroupInfo id:RYGLockGroupSettings
                            name:RYGLocalized(@"Tweak settings")
                            desc:RYGLocalized(@"Prompt before tweak settings open")
                            icon:@"ig_icon_settings_outline_24"
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupGallery
                            name:RYGLocalized(@"Gallery")
                            desc:RYGLocalized(@"Prompt before the gallery opens")
                            icon:[RYGFeatureIcons gallery].igName
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupKeepDeleted
                            name:RYGLocalized(@"Deleted messages log")
                            desc:RYGLocalized(@"Prompt before the deleted-messages log opens")
                            icon:[RYGFeatureIcons deletedMessages].igName
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupProfileAnalyzer
                            name:RYGLocalized(@"Profile Analyzer")
                            desc:RYGLocalized(@"Prompt before Profile Analyzer opens")
                            icon:[RYGFeatureIcons profileAnalyzer].igName
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupCallRecordings
                            name:RYGLocalized(@"Call recordings")
                            desc:RYGLocalized(@"Prompt before the call recordings open")
                            icon:[RYGFeatureIcons callRecordings].igName
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupActivityLog
                            name:RYGLocalized(@"Activity log")
                            desc:RYGLocalized(@"Prompt before the activity log opens")
                            icon:[RYGFeatureIcons readReceipts].igName
                           indep:NO],
            [RYGLockGroupInfo id:RYGLockGroupMessagesTab
                            name:RYGLocalized(@"DM inbox")
                            desc:RYGLocalized(@"Prompt on every entry to the DM inbox, including launch-to-messages")
                            icon:@"ig_icon_direct_prism_outline_24"
                           indep:YES],
            [RYGLockGroupInfo id:RYGLockGroupChats
                            name:RYGLocalized(@"Per-chat locks")
                            desc:RYGLocalized(@"Long-press a chat to lock it individually")
                            icon:@"ig_icon_direct_off_prism_outline_24"
                           indep:YES],
            [RYGLockGroupInfo id:RYGLockGroupHiddenReveal
                            name:RYGLocalized(@"Reveal hidden chats")
                            desc:RYGLocalized(@"Prompt before holding the inbox name reveals hidden chats")
                            icon:[RYGFeatureIcons revealHidden].igName
                           indep:YES],
        ];
    });
    return all;
}

RYGLockGroupInfo *RYGLockGroupInfoFor(NSString *identifier) {
    if (!identifier.length) return nil;
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary new];
        for (RYGLockGroupInfo *g in RYGLockAllGroups()) m[g.identifier] = g;
        map = [m copy];
    });
    return map[identifier];
}

NSString *RYGLockPrefEnabled(NSString *gid)             { return [NSString stringWithFormat:@"lock_%@_enabled", gid]; }
NSString *RYGLockPrefRelockOnBackground(NSString *gid)  { return [NSString stringWithFormat:@"lock_%@_relock_background", gid]; }
NSString *RYGLockPrefIdleTimeout(NSString *gid)         { return [NSString stringWithFormat:@"lock_%@_idle_timeout", gid]; }
NSString *RYGLockPrefIndependentSession(NSString *gid)  { return [NSString stringWithFormat:@"lock_%@_independent_session", gid]; }
NSString *RYGLockPrefRelockOnDismiss(NSString *gid)     { return [NSString stringWithFormat:@"lock_%@_relock_on_dismiss", gid]; }
