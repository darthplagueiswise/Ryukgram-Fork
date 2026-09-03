#import "OverlayHelpers.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../ActionButton/RYGMediaActions.h"
#import "../../Downloader/Download.h"
#import "../../Gallery/RYGGalleryFile.h"
#import "../../Gallery/RYGGallerySaveMetadata.h"
#import "RYGDirectUserResolver.h"

// MARK: - DM sender metadata

static NSString *rygStringFromAny(id v) {
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    if ([v isKindOfClass:[NSNumber class]]) return [(NSNumber *)v stringValue];
    return nil;
}

static id rygActiveUserSession(void) {
    @try {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                @try {
                    id session = [window valueForKey:@"userSession"];
                    if (session) return session;
                } @catch (__unused id e) {}
            }
        }
    } @catch (__unused id e) {}
    return nil;
}

// Resolves to IGUser via the shared cache, with session.user as the
// self-authored fallback.
static id rygResolveUserForPK(NSString *pk) {
    if (!pk.length) return nil;
    id user = rygDirectUserResolverUserForPK(pk);
    if (user) return user;

    id session = rygActiveUserSession();
    if (!session) return nil;
    @try {
        id selfUser = [session valueForKey:@"user"];
        NSString *selfPK = rygDirectUserResolverPKFromUser(selfUser);
        if (selfPK && [selfPK isEqualToString:pk]) return selfUser;
    } @catch (__unused id e) {}
    return nil;
}

// IGDevirtualizedValueObject resolves its accessors via forwardInvocation —
// respondsToSelector: lies but methodSignatureForSelector: tells the truth.
static id rygCall0(id obj, SEL sel) {
    if (!obj || !sel) return nil;
    @try {
        if (![obj respondsToSelector:sel] && ![obj methodSignatureForSelector:sel]) return nil;
        typedef id (*Fn)(id, SEL);
        return ((Fn)objc_msgSend)(obj, sel);
    } @catch (__unused id e) { return nil; }
}

// IGDirectVisualMessage._message → IGDirectUIMessage.metadata.senderPk.
// IGDirectAudioMessageViewModel.messageMetadata.senderPk. Both funnel here.
static NSString *rygSenderPKFromMessageObject(id msg) {
    if (!msg) return nil;
    Ivar inner = class_getInstanceVariable([msg class], "_message");
    if (inner) {
        id wrapped = object_getIvar(msg, inner);
        if (wrapped) msg = wrapped;
    }
    for (NSString *sel in @[@"metadata", @"messageMetadata"]) {
        id mdObj = rygCall0(msg, NSSelectorFromString(sel));
        if (!mdObj) continue;
        NSString *pk = rygStringFromAny(rygCall0(mdObj, @selector(senderPk)));
        if (pk.length) return pk;
    }
    return rygStringFromAny(rygCall0(msg, @selector(senderPk)));
}

RYGGallerySaveMetadata *rygDMMetadataFromMessage(id msg) {
    RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
    md.source = (int16_t)RYGGallerySourceDMs;
    if (!msg) return md;

    NSString *senderPK = rygSenderPKFromMessageObject(msg);
    if (!senderPK.length) return md;

    md.sourceUserPK = senderPK;
    id user = rygResolveUserForPK(senderPK);
    if (user) {
        md.sourceUsername = rygDirectUserResolverUsernameFromUser(user);
        md.sourceProfileURLString = rygDirectUserResolverProfilePicURLStringFromUser(user);
    }
    return md;
}

RYGGallerySaveMetadata *rygDMMetadataForVC(UIViewController *dmVC) {
    RYGGallerySaveMetadata *md = [RYGGallerySaveMetadata new];
    md.source = (int16_t)RYGGallerySourceDMs;
    if (!dmVC) return md;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    return rygDMMetadataFromMessage(msg);
}

// MARK: - Context detection

BOOL rygOverlayIsInDMContext(UIView *overlay) {
    Class dmCls = NSClassFromString(@"IGDirectVisualMessageViewerController");
    if (!dmCls) return NO;

    UIResponder *r = overlay.nextResponder;
    while (r) {
        if ([r isKindOfClass:dmCls]) return YES;
        r = r.nextResponder;
    }

    // Fallback: _gestureDelegate ivar is the DM VC in DM contexts.
    static Ivar gdIvar = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class c = NSClassFromString(@"IGStoryFullscreenOverlayView");
        if (c) gdIvar = class_getInstanceVariable(c, "_gestureDelegate");
    });
    if (gdIvar) {
        id d = object_getIvar(overlay, gdIvar);
        if (d && [d isKindOfClass:dmCls]) return YES;
    }
    return NO;
}

UIView *rygFindOverlayInView(UIView *root) {
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls || !root) return nil;
    if ([root isKindOfClass:overlayCls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = rygFindOverlayInView(sub);
        if (found) return found;
    }
    return nil;
}

// MARK: - DM media URL

NSURL *rygDMMediaURL(UIViewController *dmVC, BOOL *outIsVideo) {
    if (!dmVC) return nil;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return nil;

    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    Ivar mIvar = vmi ? class_getInstanceVariable([vmi class], "_media") : nil;
    id visMedia = mIvar ? object_getIvar(vmi, mIvar) : nil;
    if (!visMedia) return nil;

    @try {
        id rawVideo = [msg valueForKey:@"rawVideo"];
        if (rawVideo) {
            NSURL *url = [RYGUtils getVideoUrl:rawVideo];
            if (url) { if (outIsVideo) *outIsVideo = YES; return url; }
        }
    } @catch (__unused NSException *e) {}

    Ivar pi = class_getInstanceVariable([visMedia class], "_photo_photo");
    id photo = pi ? object_getIvar(visMedia, pi) : nil;
    if (photo) {
        if (outIsVideo) *outIsVideo = NO;
        return [RYGUtils getPhotoUrl:photo];
    }
    return nil;
}

// MARK: - DM actions

void rygDMExpandMedia(UIViewController *dmVC) {
    BOOL isVideo = NO;
    NSURL *url = rygDMMediaURL(dmVC, &isVideo);
    if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find media")]; return; }
    if (isVideo) [RYGMediaViewer showWithVideoURL:url photoURL:nil caption:nil];
    else         [RYGMediaViewer showWithVideoURL:nil photoURL:url caption:nil];
}

static RYGGallerySaveMetadata *rygDMMetadata(UIViewController *dmVC) {
    RYGGallerySaveMetadata *md = rygDMMetadataForVC(dmVC);
    md.contextLabel = @"dm";
    return md;
}

// The IGVideo backing the current visual message (rawVideo for view-once,
// _visualMediaInfo._media._video_video otherwise). nil for photo messages.
static id rygDMVisualVideoObject(UIViewController *dmVC) {
    if (!dmVC) return nil;
    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    if (!msg) return nil;

    @try { id rawVideo = [msg valueForKey:@"rawVideo"]; if (rawVideo) return rawVideo; } @catch (__unused id e) {}

    Ivar vmiIvar = class_getInstanceVariable([msg class], "_visualMediaInfo");
    id vmi = vmiIvar ? object_getIvar(msg, vmiIvar) : nil;
    Ivar mIvar = vmi ? class_getInstanceVariable([vmi class], "_media") : nil;
    id visMedia = mIvar ? object_getIvar(vmi, mIvar) : nil;
    Ivar vvIvar = visMedia ? class_getInstanceVariable([visMedia class], "_video_video") : nil;
    return vvIvar ? object_getIvar(visMedia, vvIvar) : nil;
}

static void rygDMStartDownload(UIViewController *dmVC, DownloadAction action) {
    // Video carries an inline DASH manifest with higher-bitrate reps than the
    // single progressive URL — route through the HD picker first.
    RYGGallerySaveMetadata *md = rygDMMetadata(dmVC);
    id video = rygDMVisualVideoObject(dmVC);
    if (video && [RYGMediaActions downloadVisualDMVideo:video action:action metadata:md]) return;

    BOOL isVideo = NO;
    NSURL *url = rygDMMediaURL(dmVC, &isVideo);
    if (!url) { [RYGUtils showErrorHUDWithDescription:RYGLocalized(@"Could not find media")]; return; }
    RYGDownloadDelegate *dl = [[RYGDownloadDelegate alloc] initWithAction:action showProgress:YES];
    dl.pendingGallerySaveMetadata = md;
    [dl downloadFileWithURL:url fileExtension:(isVideo ? @"mp4" : @"jpg") hudLabel:nil];
}

void rygDMShareMedia(UIViewController *dmVC)             { rygDMStartDownload(dmVC, share); }
void rygDMDownloadMedia(UIViewController *dmVC)          { rygDMStartDownload(dmVC, saveToPhotos); }
void rygDMDownloadMediaToGallery(UIViewController *dmVC) { rygDMStartDownload(dmVC, saveToGallery); }

// Toggles dmVisualMsgsViewedButtonEnabled for ~1s so VisualMsgModifier lets
// the begin/end playback callbacks through.
void rygDMMarkCurrentAsViewed(UIViewController *dmVC) {
    if (!dmVC) return;

    BOOL wasEnabled = dmVisualMsgsViewedButtonEnabled;
    dmVisualMsgsViewedButtonEnabled = YES;

    Ivar dsIvar = class_getInstanceVariable([dmVC class], "_dataSource");
    id ds = dsIvar ? object_getIvar(dmVC, dsIvar) : nil;
    Ivar msgIvar = ds ? class_getInstanceVariable([ds class], "_currentMessage") : nil;
    id msg = msgIvar ? object_getIvar(ds, msgIvar) : nil;
    Ivar erIvar = class_getInstanceVariable([dmVC class], "_eventResponders");
    NSArray *responders = erIvar ? object_getIvar(dmVC, erIvar) : nil;

    if (responders && msg) {
        for (id resp in responders) {
            SEL beginSel = @selector(visualMessageViewerController:didBeginPlaybackForVisualMessage:atIndex:);
            if ([resp respondsToSelector:beginSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger);
                ((Fn)objc_msgSend)(resp, beginSel, dmVC, msg, 0);
            }
            SEL endSel = @selector(visualMessageViewerController:didEndPlaybackForVisualMessage:atIndex:mediaCurrentTime:forNavType:);
            if ([resp respondsToSelector:endSel]) {
                typedef void (*Fn)(id, SEL, id, id, NSInteger, CGFloat, NSInteger);
                ((Fn)objc_msgSend)(resp, endSel, dmVC, msg, 0, 0.0, 0);
            }
        }
    }

    BOOL advanced = NO;
    if ([RYGUtils getBoolPref:@"dm_visual_advance_on_mark_seen"] && dmVC.isViewLoaded) {
        UIView *overlay = rygFindOverlayInView(dmVC.view);
        SEL tapSel = @selector(fullscreenOverlay:didTapInRegion:);
        if (overlay && [dmVC respondsToSelector:tapSel]) {
            // region 3 = forward tap; advances to next stacked media, auto-dismisses on the last.
            ((void(*)(id, SEL, id, NSInteger))objc_msgSend)(dmVC, tapSel, overlay, 3);
            advanced = YES;
        }
    }

    if (!advanced) {
        SEL dismissSel = NSSelectorFromString(@"_didTapHeaderViewDismissButton:");
        if ([dmVC respondsToSelector:dismissSel]) {
            ((void(*)(id,SEL,id))objc_msgSend)(dmVC, dismissSel, nil);
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        dmVisualMsgsViewedButtonEnabled = wasEnabled;
    });

    RYGNotifySuccess(RYG_NOTIF_SEEN_DM, RYGLocalized(@"Marked as viewed"), nil);
}

// MARK: - Settings shortcut

void rygOpenMessagesSettings(UIView *source) {
    UIWindow *win = source.window;
    if (!win) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { win = w; break; }
            }
            if (win) break;
        }
    }
    if (!win) return;
    [RYGUtils showSettingsVC:win atTopLevelEntry:RYGLocalized(@"Messages")];
}
