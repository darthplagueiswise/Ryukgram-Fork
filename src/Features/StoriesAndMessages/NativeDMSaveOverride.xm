// Reroute IG's native DM "Save to camera roll" (photos + videos) into our
// pipeline, and force the native Save affordances visible (in-viewer button +
// long-press menu) since IG hides them for some accounts / vanish mode.
// Actions come from SCIActionMenuConfig. Gated by dm_native_save_enabled.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Downloader/Download.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIActionCatalog.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "SCIDirectUserResolver.h"
#import <objc/runtime.h>

static UIViewController *sciNSTopVC(void) {
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

static NSString *sciNSIvarStr(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable([obj class], name);
    id v = iv ? object_getIvar(obj, iv) : nil;
    return [v isKindOfClass:NSString.class] ? v : nil;
}

// Frontmost on-screen VC of the given class.
static UIViewController *sciNSFindFrontVC(UIViewController *vc, Class cls) {
    if (!vc) return nil;
    UIViewController *hit = nil;
    if ([vc isKindOfClass:cls] && vc.isViewLoaded && vc.view.window) hit = vc;
    if ([vc isKindOfClass:UINavigationController.class])
        for (UIViewController *c in ((UINavigationController *)vc).viewControllers) { UIViewController *r = sciNSFindFrontVC(c, cls); if (r) hit = r; }
    if ([vc isKindOfClass:UITabBarController.class])
        for (UIViewController *c in ((UITabBarController *)vc).viewControllers) { UIViewController *r = sciNSFindFrontVC(c, cls); if (r) hit = r; }
    for (UIViewController *c in vc.childViewControllers) { UIViewController *r = sciNSFindFrontVC(c, cls); if (r) hit = r; }
    if (vc.presentedViewController) { UIViewController *r = sciNSFindFrontVC(vc.presentedViewController, cls); if (r) hit = r; }
    return hit;
}

static id sciNSIvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static UIViewController *sciNSFrontVCOfClass(NSString *clsName) {
    Class cls = NSClassFromString(clsName);
    if (!cls) return nil;
    UIWindow *kw = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) { kw = w; break; }
        if (kw) break;
    }
    return sciNSFindFrontVC(kw.rootViewController, cls);
}

static NSString *sciNSSenderIDFromViewer(UIViewController *viewer) {
    const char *names[] = { "_mediaDisplayedInUI", "_initialMedia" };
    for (int i = 0; i < 2 && viewer; i++) {
        id m = sciNSIvarObj(viewer, names[i]);
        NSString *sid = m ? sciNSIvarStr(m, "_senderId") : nil;
        if (sid.length) return sid;
    }
    return nil;
}

// Match a PK against IGDirectThreadMetadata._users (the thread's IGUser list).
static id sciNSUserInMeta(id meta, NSString *pk) {
    id users = sciNSIvarObj(meta, "_users");
    if (![users isKindOfClass:NSArray.class] || !pk.length) return nil;
    for (id u in (NSArray *)users) {
        NSString *upk = sciDirectUserResolverPKFromUser(u);
        if (upk && [upk isEqualToString:pk]) return u;
    }
    return nil;
}

// 1:1 fallback: the single non-self participant (groups stay ambiguous → nil).
static id sciNSOtherParticipant(id meta, NSString *selfPK) {
    id users = sciNSIvarObj(meta, "_users");
    if (![users isKindOfClass:NSArray.class]) return nil;
    id other = nil;
    for (id u in (NSArray *)users) {
        NSString *upk = sciDirectUserResolverPKFromUser(u);
        if (!upk.length || (selfPK.length && [upk isEqualToString:selfPK])) continue;
        if (other) return nil;  // more than one other → group, ambiguous
        other = u;
    }
    return other;
}

static NSString *sciNSSelfPK(id session) {
    @try {
        id u = [session valueForKey:@"user"];
        return sciDirectUserResolverPKFromUser(u);
    } @catch (__unused id e) { return nil; }
}

// The aggregated viewer exposes the exact senderId; a thread long-press has no
// per-message sender, so fall back to the 1:1 other participant.
static id sciNSResolveUser(id media, NSString **outPK) {
    UIViewController *agg = sciNSFrontVCOfClass(@"IGDirectAggregatedMediaViewerViewController");
    if (agg) {
        NSString *sid = sciNSSenderIDFromViewer(agg);
        id u = sciNSUserInMeta(sciNSIvarObj(agg, "_metadata"), sid);
        if (u) { if (outPK) *outPK = sid; return u; }
    }

    UIViewController *thread = sciNSFrontVCOfClass(@"IGDirectThreadViewController");
    if (thread) {
        id session = sciNSIvarObj(thread, "_threadSession");
        id meta = sciNSIvarObj(sciNSIvarObj(session, "_threadInfoProvider"), "_threadMetadata");
        id u = sciNSOtherParticipant(meta, sciNSSelfPK(sciNSIvarObj(session, "_userSession")));
        if (u) { if (outPK) *outPK = sciDirectUserResolverPKFromUser(u); return u; }
    }

    NSString *ownerID = sciNSIvarStr(media, "_ownerID");
    if (ownerID.length) { if (outPK) *outPK = ownerID; return sciDirectUserResolverUserForPK(ownerID); }
    return nil;
}

static SCIGallerySaveMetadata *sciNSMetadata(id media) {
    SCIGallerySaveMetadata *md = [SCIGallerySaveMetadata new];
    md.source = (int16_t)SCIGallerySourceDMs;
    md.sourceMediaPK = sciNSIvarStr(media, "_mediaID");

    NSString *pk = nil;
    id user = sciNSResolveUser(media, &pk);
    if (pk.length) md.sourceUserPK = pk;
    if (user) {
        md.sourceUsername = sciDirectUserResolverUsernameFromUser(user);
        md.sourceProfileURLString = sciDirectUserResolverProfilePicURLStringFromUser(user);
    }
    if (!md.sourceUsername.length) md.sourceUsername = sciNSIvarStr(media, "_ownerUsername");
    return md;
}

static void sciNSDoRun(id media, BOOL isVideo, DownloadAction action, SCIGallerySaveMetadata *md) {
    [SCIMediaActions setCurrentFilenameStem:
        [SCIMediaActions filenameStemForUsername:md.sourceUsername contextLabel:@"dm"]];

    if (isVideo) {
        if ([SCIMediaActions downloadVisualDMVideo:media action:action metadata:md]) return;
        NSURL *url = [SCIUtils getVideoUrl:(IGVideo *)media];
        if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
        SCIDownloadDelegate *dl = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:YES];
        dl.pendingGallerySaveMetadata = md;
        [dl downloadFileWithURL:url fileExtension:@"mp4" hudLabel:nil];
        return;
    }

    NSURL *url = [SCIUtils getPhotoUrl:(IGPhoto *)media];
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    SCIDownloadDelegate *dl = [[SCIDownloadDelegate alloc] initWithAction:action showProgress:YES];
    dl.pendingGallerySaveMetadata = md;
    [dl downloadFileWithURL:url fileExtension:@"jpg" hudLabel:nil];
}

static void sciNSRun(id media, BOOL isVideo, DownloadAction action) {
    sciNSDoRun(media, isVideo, action, sciNSMetadata(media));
}

static void sciNSExpand(id media, BOOL isVideo) {
    NSURL *url = isVideo ? [SCIUtils getVideoUrl:(IGVideo *)media] : [SCIUtils getPhotoUrl:(IGPhoto *)media];
    if (!url) { [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find media")]; return; }
    [SCIMediaViewer showWithVideoURL:(isVideo ? url : nil) photoURL:(isVideo ? nil : url) caption:nil];
}

// Maps an AID to its SCIAction. Returns nil for gallery when the gallery is
// off, which also drops the row (actionsForConfig: discards nil).
static SCIAction *sciNSLeafForAID(NSString *aid, id media, BOOL isVideo) {
    SCIActionDescriptor *desc = [SCIActionCatalog descriptorForActionID:aid source:SCIActionSourceDMNativeSave];
    if (!desc) return nil;

    if ([aid isEqualToString:SCIAID_Expand])
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ sciNSExpand(media, isVideo); }];
    if ([aid isEqualToString:SCIAID_DownloadSave])
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ sciNSRun(media, isVideo, saveToPhotos); }];
    if ([aid isEqualToString:SCIAID_DownloadGallery]) {
        if (![SCIUtils getBoolPref:@"sci_gallery_enabled"]) return nil;
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ sciNSRun(media, isVideo, saveToGallery); }];
    }
    if ([aid isEqualToString:SCIAID_DownloadShare])
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{ sciNSRun(media, isVideo, share); }];
    return nil;
}

// Outside-tap dismiss for the centred alert; ignores touches inside it.
@interface SCINSTapCloser : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIAlertController *alert;
@end
@implementation SCINSTapCloser
- (void)bgTap { [self.alert dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch {
    return self.alert && ![touch.view isDescendantOfView:self.alert.view];
}
@end

static void sciNSPresentList(id media, BOOL isVideo, SCIActionMenuConfig *cfg) {
    UIViewController *top = sciNSTopVC();
    if (!top) { sciNSRun(media, isVideo, saveToPhotos); return; }

    NSArray<SCIAction *> *all = [SCIActionMenu actionsForConfig:cfg dateHeader:nil
        resolver:^SCIAction *(NSString *aid) { return sciNSLeafForAID(aid, media, isVideo); }];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:SCILocalized(@"Save media") message:nil
                                                          preferredStyle:UIAlertControllerStyleAlert];
    NSUInteger count = 0;
    for (SCIAction *a in all) {
        if (a.isSeparator || !a.handler) continue;
        void (^handler)(void) = a.handler;
        [sheet addAction:[UIAlertAction actionWithTitle:a.title style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) { handler(); }]];
        count++;
    }
    if (!count) { sciNSRun(media, isVideo, saveToPhotos); return; }
    [sheet addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];

    [top presentViewController:sheet animated:YES completion:^{
        UIView *bg = sheet.view.superview;
        if (!bg) return;
        SCINSTapCloser *closer = [SCINSTapCloser new];
        closer.alert = sheet;
        static const void *kCloserKey = &kCloserKey;
        objc_setAssociatedObject(sheet, kCloserKey, closer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:closer action:@selector(bgTap)];
        tap.delegate = closer;
        tap.cancelsTouchesInView = NO;
        [bg addGestureRecognizer:tap];
    }];
}

// YES = we handled it; caller skips IG's native save.
static BOOL sciNSHandle(id media, BOOL isVideo) {
    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceDMNativeSave];
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";

    if ([tap isEqualToString:@"menu"]) { sciNSPresentList(media, isVideo, cfg); return YES; }

    SCIAction *action = sciNSLeafForAID(tap, media, isVideo);
    if (action.handler) { action.handler(); return YES; }
    // defaultTap resolved to nil (e.g. gallery while gallery off) — fall back.
    sciNSRun(media, isVideo, saveToPhotos);
    return YES;
}

%group SCINativeDMSaveGroup

// Demangled: IGDirectMediaViewerSaving.IGDirectSaveMediaManager
%hook _TtC25IGDirectMediaViewerSaving24IGDirectSaveMediaManager

+ (id)savePhotoToCameraRoll:(id)photo resolver:(id)resolver fromModule:(id)module wasGeneratedByAI:(BOOL)ai session:(id)session {
    if (sciNSHandle(photo, NO)) return nil;
    return %orig;
}

+ (id)saveVideoToCameraRoll:(id)video resolver:(id)resolver fromModule:(id)module launcherSet:(id)set {
    if (sciNSHandle(video, YES)) return nil;
    return %orig;
}

%end

// IGDirectMessageMenuOption enum: 6 = Save to camera roll.
static NSNumber *const kSCISaveMenuOption = @6;

static BOOL sciNSSaveableContentType(id ct) {
    return [ct isKindOfClass:[NSString class]] && ([ct isEqualToString:@"photo"] || [ct isEqualToString:@"video"]);
}

// IG drops Save from the eligible options for some accounts / vanish mode; add it back.
%hook _TtC32IGDirectMessageMenuConfiguration32IGDirectMessageMenuConfiguration
+ (id)menuConfigurationWithEligibleOptions:(id)options messageViewModel:(id)arg2 contentType:(id)arg3 isSticker:(_Bool)arg4 isMusicSticker:(_Bool)arg5 directNuxManager:(id)arg6 sessionUserDefaults:(id)arg7 launcherSet:(id)arg8 userSession:(id)arg9 tapHandler:(id)arg10 {
    if ([options isKindOfClass:[NSArray class]] && !arg4 && sciNSSaveableContentType(arg3) && ![options containsObject:kSCISaveMenuOption]) {
        NSMutableArray *opts = [options mutableCopy];
        NSUInteger at = [opts indexOfObject:@0];
        at = (at == NSNotFound) ? 0 : at + 1;
        [opts insertObject:kSCISaveMenuOption atIndex:MIN(at, opts.count)];
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
    if ([SCIUtils getBoolPref:@"dm_native_save_enabled"])
        %init(SCINativeDMSaveGroup);
}
