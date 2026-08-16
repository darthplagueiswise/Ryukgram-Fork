// Reroute IG's native DM "Save to camera roll" (photos + videos) into our
// pipeline, and force the native Save affordances visible (in-viewer button +
// long-press menu) since IG hides them for some accounts / vanish mode.
// Actions come from RYGActionMenuConfig. Gated by dm_native_save_enabled.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../ActionButton/RYGActionCatalog.h"
#import "../../ActionButton/RYGActionMenu.h"
#import "../../ActionButton/RYGActionMenuConfig.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "RYGDirectUserResolver.h"
#import <objc/runtime.h>

// Set while a long-press re-fires the save action, so the hook opens the menu.
static BOOL rygNSForceMenu = NO;

static UIViewController *rygNSTopVC(void) {
    UIWindow *kw = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows)
            if (w.isKeyWindow) { kw = w; break; }
        if (kw) break;
    }
    if (!kw) kw = UIApplication.sharedApplication.windows.firstObject;
    UIViewController *vc = kw.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static NSString *rygNSIvarStr(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    id v = iv ? object_getIvar(obj, iv) : nil;
    return [v isKindOfClass:NSString.class] ? v : nil;
}

// Frontmost on-screen VC of the given class.
static UIViewController *rygNSFindFrontVC(UIViewController *vc, Class cls) {
    if (!vc) return nil;
    UIViewController *hit = nil;
    if ([vc isKindOfClass:cls] && vc.isViewLoaded && vc.view.window) hit = vc;
    if ([vc isKindOfClass:UINavigationController.class])
        for (UIViewController *c in ((UINavigationController *)vc).viewControllers) { UIViewController *r = rygNSFindFrontVC(c, cls); if (r) hit = r; }
    if ([vc isKindOfClass:UITabBarController.class])
        for (UIViewController *c in ((UITabBarController *)vc).viewControllers) { UIViewController *r = rygNSFindFrontVC(c, cls); if (r) hit = r; }
    for (UIViewController *c in vc.childViewControllers) { UIViewController *r = rygNSFindFrontVC(c, cls); if (r) hit = r; }
    if (vc.presentedViewController) { UIViewController *r = rygNSFindFrontVC(vc.presentedViewController, cls); if (r) hit = r; }
    return hit;
}

static id rygNSIvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static UIViewController *rygNSFrontVCOfClass(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return nil;
    UIWindow *kw = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) { kw = w; break; }
        if (kw) break;
    }
    return rygNSFindFrontVC(kw.rootViewController, cls);
}

static NSString *rygNSSenderIDFromViewer(UIViewController *viewer) {
    const char *names[] = { "_mediaDisplayedInUI", "_initialMedia" };
    for (int i = 0; i < 2 && viewer; i++) {
        id m = rygNSIvarObj(viewer, names[i]);
        NSString *sid = m ? rygNSIvarStr(m, "_senderId") : nil;
        if (sid.length) return sid;
    }
    return nil;
}

// Match a PK against IGDirectThreadMetadata._users (the thread's IGUser list).
static id rygNSUserInMeta(id meta, NSString *pk) {
    id users = rygNSIvarObj(meta, "_users");
    if (![users isKindOfClass:NSArray.class] || !pk.length) return nil;
    for (id u in (NSArray *)users) {
        NSString *upk = rygDirectUserResolverPKFromUser(u);
        if (upk && [upk isEqualToString:pk]) return u;
    }
    return nil;
}

// 1:1 fallback: the single non-self participant (groups stay ambiguous → nil).
static id rygNSOtherParticipant(id meta, NSString *selfPK) {
    id users = rygNSIvarObj(meta, "_users");
    if (![users isKindOfClass:NSArray.class]) return nil;
    id other = nil;
    for (id u in (NSArray *)users) {
        NSString *upk = rygDirectUserResolverPKFromUser(u);
        if (!upk.length || (selfPK.length && [upk isEqualToString:selfPK])) continue;
        if (other) return nil;  // more than one other → group, ambiguous
        other = u;
    }
    return other;
}

static NSString *rygNSSelfPK(id session) {
    @try {
        id u = [session valueForKey:@"user"];
        return rygDirectUserResolverPKFromUser(u);
    } @catch (__unused id e) { return nil; }
}

// The aggregated viewer exposes the exact senderId; a thread long-press has no
// per-message sender, so fall back to the 1:1 other participant.
static id rygNSResolveUser(id media, NSString **outPK) {
    UIViewController *agg = rygNSFrontVCOfClass(@"IGDirectAggregatedMediaViewerViewController");
    if (agg) {
        NSString *sid = rygNSSenderIDFromViewer(agg);
        id u = rygNSUserInMeta(rygNSIvarObj(agg, "_metadata"), sid);
        if (u) { if (outPK) *outPK = sid; return u; }
    }

    UIViewController *thread = rygNSFrontVCOfClass(@"IGDirectThreadViewController");
    if (thread) {
        id session = rygNSIvarObj(thread, "_threadSession");
        id meta = rygNSIvarObj(rygNSIvarObj(session, "_threadInfoProvider"), "_threadMetadata");
        id u = rygNSOtherParticipant(meta, rygNSSelfPK(rygNSIvarObj(session, "_userSession")));
        if (u) { if (outPK) *outPK = rygDirectUserResolverPKFromUser(u); return u; }
    }

    NSString *ownerID = rygNSIvarStr(media, "_ownerID");
    if (ownerID.length) { if (outPK) *outPK = ownerID; return rygDirectUserResolverUserForPK(ownerID); }
    return nil;
}

static RYGGallerySaveMetadata *rygNSMetadata(id media) {
    RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
    md.source = (int16_t)RYGGallerySourceDMs;
    md.sourceMediaPK = rygNSIvarStr(media, "_mediaID");

    NSString *pk = nil;
    id user = rygNSResolveUser(media, &pk);
    if (pk.length) md.sourceUserPK = pk;
    if (user) {
        md.sourceUsername = rygDirectUserResolverUsernameFromUser(user);
        md.sourceProfileURLString = rygDirectUserResolverProfilePicURLStringFromUser(user);
    }
    if (!md.sourceUsername.length) md.sourceUsername = rygNSIvarStr(media, "_ownerUsername");
    return md;
}

static void rygNSDoRun(id media, BOOL isVideo, DownloadAction action, RYGGallerySaveMetadata *md) {
    [RYGMediaActions setCurrentFilenameStem:
        [RYGMediaActions filenameStemForUsername:md.sourceUsername contextLabel:@"dm"]];

    if (isVideo) {
        if ([RYGMediaActions downloadVisualDMVideo:media action:action metadata:md]) return;
        NSURL *url = [RYGUtils getVideoUrl:(IGVideo *)media];
        if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find media")]; return; }
        RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:YES];
        dl.pendingGallerySaveMetadata = md;
        [dl downloadFileWithURL:url fileExtension:@"mp4" hudLabel:nil];
        return;
    }

    NSURL *url = [RYGUtils getPhotoUrl:(IGPhoto *)media];
    if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find media")]; return; }
    RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:YES];
    dl.pendingGallerySaveMetadata = md;
    [dl downloadFileWithURL:url fileExtension:@"jpg" hudLabel:nil];
}

static void rygNSRun(id media, BOOL isVideo, DownloadAction action) {
    rygNSDoRun(media, isVideo, action, rygNSMetadata(media));
}

static void rygNSExpand(id media, BOOL isVideo) {
    NSURL *url = isVideo ? [RYGUtils getVideoUrl:(IGVideo *)media] : [RYGUtils getPhotoUrl:(IGPhoto *)media];
    if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find media")]; return; }
    [RYGMediaViewer showWithVideoURL:(isVideo ? url : nil) photoURL:(isVideo ? nil : url) caption:nil];
}

// Maps an AID to its RYGAction. Returns nil for gallery when the gallery is
// off, which also drops the row (actionsForConfig: discards nil).
static RYGAction *rygNSLeafForAID(NSString *aid, id media, BOOL isVideo) {
    RYGActionDescriptor *desc = [RYGActionCatalog descriptorForActionID:aid source:RYGActionSourceDMNativeSave];
    if (!desc) return nil;

    if ([aid isEqualToString:RYGAID_Expand])
        return [RYGAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ rygNSExpand(media, isVideo); }];
    if ([aid isEqualToString:RYGAID_DownloadSave])
        return [RYGAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ rygNSRun(media, isVideo, saveToPhotos); }];
    if ([aid isEqualToString:RYGAID_DownloadGallery]) {
        if (![RYGUtils getBoolPref:@"ryg_gallery_enabled"]) return nil;
        return [RYGAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ rygNSRun(media, isVideo, saveToGallery); }];
    }
    if ([aid isEqualToString:RYGAID_DownloadShare])
        return [RYGAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ rygNSRun(media, isVideo, share); }];
    return nil;
}

// Outside-tap dismiss for the centred alert; ignores touches inside it.
@interface RYGNSTapCloser : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIAlertController *alert;
@end
@implementation RYGNSTapCloser
- (void)bgTap { [self.alert dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return self.alert && ![touch.view isDescendantOfView:self.alert.view];
}
@end

static void rygNSPresentList(id media, BOOL isVideo, RYGActionMenuConfig *cfg) {
    UIViewController *top = rygNSTopVC();
    if (!top) { rygNSRun(media, isVideo, saveToPhotos); return; }

    NSArray<RYGAction *> *all = [RYGActionMenu actionsForConfig:cfg dateHeader:nil
        resolver:^RYGAction *(NSString *aid) { return rygNSLeafForAID(aid, media, isVideo); }];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:RYGLocalized(@"Save media") message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
    NSUInteger count = 0;
    for (RYGAction *a in all) {
        if (a.isSeparator || !a.handler) continue;
        void (^handler)(void) = a.handler;
        [sheet addAction:[UIAlertAction actionWithTitle:a.title style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) { handler(); }]];
        count++;
    }
    if (!count) { rygNSRun(media, isVideo, saveToPhotos); return; }
    [sheet addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:sheet animated:YES completion:^{
        UIView *bg = sheet.view.superview;
        if (!bg) return;
        RYGNSTapCloser *closer = [RYGNSTapCloser new];
        closer.alert = sheet;
        static const void *kCloserKey = &kCloserKey;
        objc_setAssociatedObject(sheet, kCloserKey, closer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:closer action:@selector(bgTap)];
        tap.delegate = closer;
        tap.cancelsTouchesInView = NO;
        [bg addGestureRecognizer:tap];
    }];
}

// YES = we handled it; caller skips IG's native save. Tap runs the default
// (menu when unset); a viewer long-press forces the full menu via rygNSForceMenu.
static BOOL rygNSHandle(id media, BOOL isVideo) {
    RYGActionMenuConfig *cfg = [RYGActionMenuConfig configForSource:RYGActionSourceDMNativeSave];
    NSString *tap = rygNSForceMenu ? @"menu" : (cfg.defaultTap.length ? cfg.defaultTap : @"menu");

    if ([tap isEqualToString:@"menu"]) { rygNSPresentList(media, isVideo, cfg); return YES; }

    RYGAction *action = rygNSLeafForAID(tap, media, isVideo);
    if (action.handler) { action.handler(); return YES; }
    // defaultTap resolved to nil (e.g. gallery while gallery off) — fall back.
    rygNSRun(media, isVideo, saveToPhotos);
    return YES;
}

// The viewer's Save button, matched by its language-independent action.
static BOOL rygNSIsSaveButton(UIControl *c) {
    for (id t in c.allTargets)
        for (NSString *a in [c actionsForTarget:t forControlEvent:UIControlEventTouchUpInside] ?: @[])
            if ([a hasPrefix:@"didTapSaveButton"]) return YES;
    return NO;
}

@interface RYGNSSaveLongPress : NSObject
@property (nonatomic, weak) UIControl *button;
@end
@implementation RYGNSSaveLongPress
- (void)fire:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIControl *b = self.button;
    if (!b) return;
    rygNSForceMenu = YES;
    [b sendActionsForControlEvents:UIControlEventTouchUpInside];
    rygNSForceMenu = NO;
}
@end

static void rygNSAttachLongPress(UIView *v) {
    if (!v) return;
    if ([v isKindOfClass:UIControl.class] && rygNSIsSaveButton((UIControl *)v)) {
        static const void *kLPKey = &kLPKey;
        if (!objc_getAssociatedObject(v, kLPKey)) {
            RYGNSSaveLongPress *h = [RYGNSSaveLongPress new];
            h.button = (UIControl *)v;
            UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:h action:@selector(fire:)];
            [v addGestureRecognizer:lp];
            objc_setAssociatedObject(v, kLPKey, h, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    for (UIView *s in v.subviews) rygNSAttachLongPress(s);
}

%group RYGNativeDMSaveGroup

%hook IGDirectAggregatedMediaViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    rygNSAttachLongPress(((UIViewController *)self).view);
}
- (void)viewDidLayoutSubviews {
    %orig;
    rygNSAttachLongPress(((UIViewController *)self).view);
}
%end

// Demangled: IGDirectMediaViewerSaving.IGDirectSaveMediaManager
%hook _TtC25IGDirectMediaViewerSaving24IGDirectSaveMediaManager

+ (id)savePhotoToCameraRoll:(id)photo resolver:(id)resolver fromModule:(id)module wasGeneratedByAI:(BOOL)ai session:(id)session {
    if (rygNSHandle(photo, NO)) return nil;
    return %orig;
}

+ (id)saveVideoToCameraRoll:(id)video resolver:(id)resolver fromModule:(id)module launcherSet:(id)set {
    if (rygNSHandle(video, YES)) return nil;
    return %orig;
}

%end

// IGDirectMessageMenuOption enum: 6 = Save to camera roll.
static NSNumber *const kRYGSaveMenuOption = @6;

static BOOL rygNSSaveableContentType(id ct) {
    return [ct isKindOfClass:[NSString class]] && ([ct isEqualToString:@"photo"] || [ct isEqualToString:@"video"]);
}

// IG drops Save from the eligible options for some accounts / vanish mode; add it back.
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration
+ (id)menuConfigurationWithEligibleOptions:(id)options messageViewModel:(id)arg2 contentType:(id)arg3 isSticker:(_Bool)arg4 isMusicSticker:(_Bool)arg5 directNuxManager:(id)arg6 sessionUserDefaults:(id)arg7 launcherSet:(id)arg8 userSession:(id)arg9 tapHandler:(id)arg10 {
    if ([options isKindOfClass:[NSArray class]] && !arg4 && rygNSSaveableContentType(arg3) && ![options containsObject:kRYGSaveMenuOption]) {
        NSMutableArray *opts = [options mutableCopy];
        NSUInteger at = [opts indexOfObject:@0];
        at = (at == NSNotFound) ? 0 : at + 1;
        [opts insertObject:kRYGSaveMenuOption atIndex:MIN(at, opts.count)];
        return %orig(opts, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
    }
    return %orig;
}
%end

// IG sets canSave=NO for some accounts / vanish mode; force it on.
%hook _TtC44IGDirectAggregatedMediaViewerComponentsSwift63IGDirectAggregatedMediaViewerViewControllerTitleViewModelObject
- (id)initWithAuthorProfileImage:(id)arg1 authorUsername:(id)arg2 canForward:(_Bool)arg3 canSave:(_Bool)arg4 canAddToStory:(_Bool)arg5 canShowAIRestyle:(_Bool)arg6 canUnsend:(_Bool)arg7 canReport:(_Bool)arg8 displayConfig:(id)arg9 isPending:(_Bool)arg10 isMoreMenuListStyle:(_Bool)arg11 senderIsCurrentUser:(_Bool)arg12 shouldHideInfoViews:(_Bool)arg13 subtitle:(id)arg14 entryPoint:(long long)arg15 canTapAuthor:(_Bool)arg16 {
    return %orig(arg1, arg2, arg3, YES, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16);
}
%end

%end // group

%ctor {
    if ([RYGUtils getBoolPref:@"dm_native_save_enabled"])
        %init(RYGNativeDMSaveGroup);
}
