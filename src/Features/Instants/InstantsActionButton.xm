// Instants action button — Expand / Save (Photos / Gallery) / Share / bulk
// variants. Wired through SCIActionMenuConfig (source = Instants) so the
// user can reorder entries, hide them, and pick a default tap action via
// Settings → Messages → Instants → Configure menu. Pref key
// `instants_download_btn` kept for backward compat.

#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../Downloader/Manager.h"
#import "../../Gallery/SCIGalleryFile.h"
#import "../../Gallery/SCIGallerySaveMetadata.h"
#import "../../SCIChrome.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../ActionButton/SCIActionMenu.h"
#import "../../ActionButton/SCIActionMenuConfig.h"
#import "../../ActionButton/SCIActionCatalog.h"

// ============================================================================
// Helpers — view discovery, ivar reads
// ============================================================================

static char kSCIInstantsDLBtnKey;
static char kSCIInstantsDLHitKey;
static char kSCIInstantsDLTargetKey;
static char kSCIInstantsDLWireKey;
static NSInteger sciInstantsConfigVersion = 0;

static UIImageView *sciFindIGImageViewIn(UIView *root);
static NSURL *sciIGImageViewURL(UIImageView *iv);

static UIWindow *sciInstantsWindow(UIView *fromView) {
    UIWindow *win = fromView.window;
    if (win) return win;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

static NSArray<UIView *> *sciAllSnapViewsIn(UIWindow *win) {
    if (!win) return @[];
    NSMutableArray *out = [NSMutableArray array];
    void (^__block walk)(UIView *) = nil;
    void (^walkBlock)(UIView *) = ^(UIView *v) {
        if (!v) return;
        if ([NSStringFromClass([v class]) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
            [out addObject:v];
        }
        for (UIView *sv in v.subviews) walk(sv);
    };
    walk = walkBlock;
    walk(win);
    return out;
}

// Pick the snap the user is currently viewing. Drop peeks via transform
// magnitude (rotated peeks have non-zero b/c), then pick highest superview
// index — UIView renders later siblings on top, so z-order breaks ties
// during transitions where outgoing + incoming snap overlap.
static UIView *sciActiveSnapView(UIView *fromView) {
    UIWindow *win = sciInstantsWindow(fromView);
    if (!win) return nil;
    NSArray *snaps = sciAllSnapViewsIn(win);
    if (snaps.count == 0) return nil;

    UIView *best = nil;
    NSUInteger bestSuperIdx = 0;
    for (UIView *snap in snaps) {
        UIImageView *probe = sciFindIGImageViewIn(snap);
        if (!(probe && (probe.image || sciIGImageViewURL(probe)))) continue;
        if (snap.hidden || snap.alpha < 0.5) continue;
        CGAffineTransform t = snap.transform;
        CGFloat rot = fabs(t.a - 1) + fabs(t.b) + fabs(t.c) + fabs(t.d - 1);
        if (rot > 0.1) continue;  // peek
        NSUInteger superIdx = snap.superview
            ? [snap.superview.subviews indexOfObject:snap] : 0;
        if (best == nil || superIdx >= bestSuperIdx) {
            best = snap;
            bestSuperIdx = superIdx;
        }
    }
    return best;
}

// ============================================================================
// Author / context extraction (for filenames + gallery metadata)
// ============================================================================

// Snap data model is Swift with empty ivar encodings; the username label
// drawn in the consumption VC is the only stable surface we can read.
typedef struct {
    NSString *username;
    NSString *userPK;
    NSString *mediaPK;
} SCIInstantContext;

static UIView *sciConsumptionVCView(UIView *fromView) {
    UIView *v = fromView;
    while (v) {
        UIResponder *r = v.nextResponder;
        if ([r isKindOfClass:[UIViewController class]]) {
            NSString *cn = NSStringFromClass([r class]);
            if ([cn containsString:@"QuickSnap"]) {
                return ((UIViewController *)r).view;
            }
        }
        v = v.superview;
    }
    return nil;
}

static NSString *sciScrapeUsernameForSnap(UIView *snap) {
    UIView *root = sciConsumptionVCView(snap) ?: snap.window;
    if (!root) return nil;

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:
        @"^@?[a-z0-9](?:[a-z0-9._]{0,28}[a-z0-9])?$" options:0 error:nil];

    NSMutableArray<UILabel *> *cands = [NSMutableArray array];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        if (v.hidden || v.alpha < 0.1) continue;
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            if (l.text.length > 0 && l.text.length <= 31) [cands addObject:l];
        }
        for (UIView *c in v.subviews) [queue addObject:c];
    }

    static NSSet *skip;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ skip = [NSSet setWithArray:@[@"now", @"just now", @"send", @"reply", @"share"]]; });
    NSCharacterSet *seps = [NSCharacterSet characterSetWithCharactersInString:@"·•|—–-"];

    for (UILabel *l in cands) {
        NSString *t = [l.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Strip "username · 4h" suffix.
        NSRange sep = [t rangeOfCharacterFromSet:seps];
        if (sep.location != NSNotFound) {
            t = [[t substringToIndex:sep.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if ([t hasPrefix:@"@"]) t = [t substringFromIndex:1];
        if (t.length == 0) continue;
        NSString *low = t.lowercaseString;
        if ([skip containsObject:low]) continue;
        if ([re numberOfMatchesInString:low options:0 range:NSMakeRange(0, low.length)] > 0) return t;
    }
    return nil;
}

static SCIInstantContext sciContextForSnap(UIView *snap) {
    SCIInstantContext out = {0};
    out.username = sciScrapeUsernameForSnap(snap);
    return out;
}

static NSString *sciInstantHudLabel(SCIInstantContext ctx) {
    if (ctx.username.length) return [@"@" stringByAppendingString:ctx.username];
    return SCILocalized(@"Instant");
}

static SCIGallerySaveMetadata *sciInstantMetadata(SCIInstantContext ctx, BOOL bulk) {
    SCIGallerySaveMetadata *m = [SCIGallerySaveMetadata new];
    m.source = SCIGallerySourceInstants;
    m.sourceUsername = ctx.username;
    m.sourceUserPK = ctx.userPK;
    m.sourceMediaPK = ctx.mediaPK;
    m.skipDedup = bulk;
    return m;
}


// ============================================================================
// Media discovery (subview walk)
// ============================================================================

// First populated IGImageView in the subtree. Falls back to a URL-only
// match (cell loaded but image not assigned yet).
static UIImageView *sciFindIGImageViewIn(UIView *root) {
    if (!root) return nil;
    Class igImg = NSClassFromString(@"IGImageView");
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    UIImageView *fallback = nil;
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.hidden || v.alpha < 0.05) continue;
        if (v.bounds.size.width < 8 || v.bounds.size.height < 8) {
            for (UIView *sv in v.subviews) [queue addObject:sv];
            continue;
        }
        BOOL match = (igImg && [v isKindOfClass:igImg]) || [v isKindOfClass:[UIImageView class]];
        if (match) {
            UIImageView *iv = (UIImageView *)v;
            if (iv.image) return iv;
            id spec = nil;
            @try { spec = [iv valueForKey:@"imageSpecifier"]; } @catch (__unused id e) {}
            id url = nil;
            if (spec) { @try { url = [spec valueForKey:@"url"]; } @catch (__unused id e) {} }
            if ([url isKindOfClass:[NSURL class]]) return iv;
            if (!fallback) fallback = iv;
        }
        for (UIView *sv in v.subviews) [queue addObject:sv];
    }
    return fallback;
}

static NSURL *sciIGImageViewURL(UIImageView *iv) {
    if (!iv) return nil;
    id spec = nil;
    @try { spec = [iv valueForKey:@"imageSpecifier"]; } @catch (__unused id e) {}
    if (!spec) return nil;
    id url = nil;
    @try { url = [spec valueForKey:@"url"]; } @catch (__unused id e) {}
    if ([url isKindOfClass:[NSURL class]]) return url;
    return nil;
}


typedef NS_ENUM(NSInteger, SCIInstantTarget) {
    SCIInstantTargetPhotos = 0,
    SCIInstantTargetGallery,
    SCIInstantTargetShare,
};

static DownloadAction sciDLActionForTarget(SCIInstantTarget t) {
    switch (t) {
        case SCIInstantTargetPhotos:  return saveToPhotos;
        case SCIInstantTargetGallery: return saveToGallery;
        case SCIInstantTargetShare:   return share;
    }
}


// ============================================================================
// Save flows (current snap, all snaps)
// ============================================================================

// Save a still UIImage by writing a temp jpg and routing through the
// SCIDownloadDelegate completion handler. NSURLSessionDownloadTask doesn't
// support file:// URLs, so we skip the network step entirely.
static void sciSaveImageViaDelegate(UIImage *img, SCIInstantTarget target,
                                    SCIInstantContext ctx, BOOL bulk) {
    if (!img) {
        SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"),
                       SCILocalized(@"Nothing to save"));
        return;
    }
    NSData *jpg = UIImageJPEGRepresentation(img, 1.0);
    if (!jpg) {
        SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"),
                       SCILocalized(@"Failed to save"));
        return;
    }
    NSString *shortID = [[[NSUUID UUID] UUIDString] substringToIndex:8];
    NSString *base;
    if (ctx.username.length) {
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
        NSString *uname = [[ctx.username componentsSeparatedByCharactersInSet:bad]
                            componentsJoinedByString:@""];
        if (uname.length > 30) uname = [uname substringToIndex:30];
        base = [NSString stringWithFormat:@"instant-@%@-%@.jpg", uname, shortID];
    } else {
        base = [NSString stringWithFormat:@"instant-%@.jpg", shortID];
    }
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                    URLByAppendingPathComponent:base];
    NSError *err = nil;
    if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:&err]) {
        SCINotifyError(SCI_NOTIF_GALLERY_SAVE, SCILocalized(@"Save failed"),
                       err.localizedDescription ?: SCILocalized(@"Failed to save"));
        return;
    }

    SCIDownloadDelegate *d = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target)
                                                            showProgress:NO];
    d.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);

    // Mimic the pill-ticket setup downloadFileWithURL: does, then jump straight
    // to the finish handler — NSURLSessionDownloadTask doesn't support file://.
    SCIDownloadPillView *pill = SCIDownloadPillView.shared;
    d.pill = pill;
    d.ticketId = [pill beginTicketWithTitle:sciInstantHudLabel(ctx) onCancel:nil];
    [d downloadDidFinishWithFileURL:tmp];
}

static void sciSaveSnapView(UIView *snap, SCIInstantTarget target, BOOL bulk) {
    if (!snap) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                       SCILocalized(@"Could not locate the instant on screen"));
        return;
    }
    SCIInstantContext ctx = sciContextForSnap(snap);
    UIImageView *iv = sciFindIGImageViewIn(snap);
    if (iv) {
        if (iv.image) {
            sciSaveImageViaDelegate(iv.image, target, ctx, bulk);
            return;
        }
        NSURL *url = sciIGImageViewURL(iv);
        if (url) {
            NSString *ext = url.pathExtension.length ? url.pathExtension.lowercaseString : @"jpg";
            SCIDownloadDelegate *d = [[SCIDownloadDelegate alloc] initWithAction:sciDLActionForTarget(target)
                                                                    showProgress:YES];
            d.pendingGallerySaveMetadata = sciInstantMetadata(ctx, bulk);
            [d downloadFileWithURL:url fileExtension:ext hudLabel:sciInstantHudLabel(ctx)];
            return;
        }
    }
    SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                   SCILocalized(@"No media available to save"));
}

static void sciSaveAllInstants(UIView *fromView, SCIInstantTarget target) {
    UIWindow *win = sciInstantsWindow(fromView);
    NSArray *snaps = sciAllSnapViewsIn(win);
    NSUInteger queued = 0;
    for (UIView *snap in snaps) {
        UIImageView *iv = sciFindIGImageViewIn(snap);
        if (!iv || (!iv.image && !sciIGImageViewURL(iv))) continue;
        sciSaveSnapView(snap, target, YES);
        queued++;
    }
    if (queued == 0) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD_BULK, SCILocalized(@"Download failed"),
                       SCILocalized(@"No instants currently loaded"));
        return;
    }
    SCINotifyInfo(SCI_NOTIF_DOWNLOAD_BULK,
                  [NSString stringWithFormat:SCILocalized(@"Queued %lu instants"), (unsigned long)queued],
                  nil);
}

// Expand the active snap in SCIMediaViewer. Writes the in-memory UIImage to
// a temp jpg and hands the URL + metadata to the viewer.
static void sciExpandSnapView(UIView *snap) {
    if (!snap) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                       SCILocalized(@"Could not locate the instant on screen"));
        return;
    }
    UIImageView *iv = sciFindIGImageViewIn(snap);
    UIImage *img = iv.image;
    if (!img) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                       SCILocalized(@"No media available to save"));
        return;
    }

    NSData *jpg = UIImageJPEGRepresentation(img, 1.0);
    if (!jpg) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                       SCILocalized(@"Failed to save"));
        return;
    }
    NSString *base = [NSString stringWithFormat:@"instant-expand-%@.jpg",
                       [[[NSUUID UUID] UUIDString] substringToIndex:8]];
    NSURL *tmp = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                    URLByAppendingPathComponent:base];
    if (![jpg writeToURL:tmp options:NSDataWritingAtomic error:nil]) {
        SCINotifyError(SCI_NOTIF_DOWNLOAD, SCILocalized(@"Download failed"),
                       SCILocalized(@"Failed to save"));
        return;
    }

    SCIInstantContext ctx = sciContextForSnap(snap);
    NSString *caption = ctx.username.length
        ? [@"@" stringByAppendingString:ctx.username] : nil;

    SCIMediaViewerItem *item = [SCIMediaViewerItem itemWithVideoURL:nil
                                                            photoURL:tmp
                                                             caption:caption];
    item.metadata = sciInstantMetadata(ctx, NO);

    [SCIMediaViewer showItem:item];
}



// ============================================================================
// Action button — wired through SCIActionMenuConfig (source = Instants).
// ============================================================================

static SCIAction *sciInstantsLeafForAID(NSString *aid, __weak UIView *headerRef) {
    BOOL galleryOn = [SCIUtils getBoolPref:@"sci_gallery_enabled"];
    SCIActionDescriptor *desc = [SCIActionCatalog descriptorForActionID:aid
                                                                  source:SCIActionSourceInstants];
    if (!desc) return nil;

    if ([aid isEqualToString:SCIAID_Expand]) {
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciExpandSnapView(sciActiveSnapView(hv));
        }];
    }
    if ([aid isEqualToString:SCIAID_DownloadSave]) {
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciSaveSnapView(sciActiveSnapView(hv), SCIInstantTargetPhotos, NO);
        }];
    }
    if ([aid isEqualToString:SCIAID_DownloadGallery]) {
        if (!galleryOn) return nil;
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciSaveSnapView(sciActiveSnapView(hv), SCIInstantTargetGallery, NO);
        }];
    }
    if ([aid isEqualToString:SCIAID_DownloadShare]) {
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciSaveSnapView(sciActiveSnapView(hv), SCIInstantTargetShare, NO);
        }];
    }
    if ([aid isEqualToString:SCIAID_BulkDownloadSave]) {
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciSaveAllInstants(hv, SCIInstantTargetPhotos);
        }];
    }
    if ([aid isEqualToString:SCIAID_BulkDownloadGallery]) {
        if (!galleryOn) return nil;
        return [SCIAction actionWithTitle:desc.title icon:desc.iconSF handler:^{
            UIView *hv = headerRef;
            if (!hv) return;
            sciSaveAllInstants(hv, SCIInstantTargetGallery);
        }];
    }
    return nil;
}

static UIMenu *sciInstantsBuildMenu(UIView *header) {
    if (!header) return [UIMenu menuWithTitle:@"" children:@[]];
    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
    __weak UIView *weakHeader = header;
    SCIAction *(^resolve)(NSString *) = ^SCIAction *(NSString *aid) {
        return sciInstantsLeafForAID(aid, weakHeader);
    };
    NSArray<SCIAction *> *flat = [SCIActionMenu actionsForConfig:cfg dateHeader:nil resolver:resolve];
    return [SCIActionMenu buildMenuWithActions:flat];
}

static void sciInstantsExecuteDefaultTap(UIView *header, SCIActionMenuConfig *cfg) {
    if (!header) return;
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
    if ([tap isEqualToString:@"menu"]) return;
    SCIAction *leaf = sciInstantsLeafForAID(tap, header);
    if (leaf.handler) leaf.handler();
}

@interface SCIInstantsActionTarget : NSObject
+ (instancetype)shared;
@end

@implementation SCIInstantsActionTarget
+ (instancetype)shared {
    static SCIInstantsActionTarget *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SCIInstantsActionTarget new]; });
    return s;
}
- (void)tap:(UIButton *)sender {
    UIView *header = objc_getAssociatedObject(sender, &kSCIInstantsDLTargetKey);
    if (!header) return;
    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
    sciInstantsExecuteDefaultTap(header, cfg);
}
@end


// Hide the button when no populated snap views are in the same window
// (camera composer, loading state).
static BOOL sciInstantsHasDownloadable(UIView *header) {
    UIWindow *win = sciInstantsWindow(header);
    if (!win) return NO;
    for (UIView *snap in sciAllSnapViewsIn(win)) {
        if (snap.hidden || snap.alpha < 0.1) continue;
        UIImageView *iv = sciFindIGImageViewIn(snap);
        if (iv && (iv.image || sciIGImageViewURL(iv))) return YES;
    }
    return NO;
}

static void sciInstantsRemoveDLButton(UIView *header) {
    SCIChromeButton *chrome = objc_getAssociatedObject(header, &kSCIInstantsDLBtnKey);
    UIButton *hit = objc_getAssociatedObject(header, &kSCIInstantsDLHitKey);
    if (chrome) [chrome removeFromSuperview];
    if (hit) [hit removeFromSuperview];
    objc_setAssociatedObject(header, &kSCIInstantsDLBtnKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(header, &kSCIInstantsDLHitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Idempotent re-wire — layoutSubviews fires while a menu is presented, and
// reassigning `hit.menu` mid-interaction collapses any open submenu. Cache
// the last-applied (tap mode, config version) and short-circuit on match.
static void sciInstantsWireActionButton(SCIChromeButton *chrome, UIButton *hit, UIView *header) {
    SCIActionMenuConfig *cfg = [SCIActionMenuConfig configForSource:SCIActionSourceInstants];
    NSString *tap = cfg.defaultTap.length ? cfg.defaultTap : @"menu";
    NSString *wireKey = [NSString stringWithFormat:@"%@|%ld", tap, (long)sciInstantsConfigVersion];

    objc_setAssociatedObject(hit, &kSCIInstantsDLTargetKey, header, OBJC_ASSOCIATION_ASSIGN);

    NSString *prevWire = objc_getAssociatedObject(hit, &kSCIInstantsDLWireKey);
    if ([prevWire isEqualToString:wireKey]) return;

    [hit removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];

    __weak UIView *weakHeader = header;
    UIDeferredMenuElement *deferred = [UIDeferredMenuElement
        elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        UIView *strongHeader = weakHeader;
        UIMenu *m = sciInstantsBuildMenu(strongHeader);
        completion(m.children ?: @[]);
    }];
    hit.menu = [UIMenu menuWithChildren:@[deferred]];

    if ([tap isEqualToString:@"menu"]) {
        hit.showsMenuAsPrimaryAction = YES;
    } else {
        // Tap fires direct action; long-press still surfaces the menu.
        hit.showsMenuAsPrimaryAction = NO;
        [hit addTarget:[SCIInstantsActionTarget shared]
                action:@selector(tap:)
      forControlEvents:UIControlEventTouchUpInside];
    }

    objc_setAssociatedObject(hit, &kSCIInstantsDLWireKey, wireKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

// IGQuickSnapNavigationV3HeaderButtonController.IGQuickSnapNavigationV3HeaderButtonView
%hook _TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView
- (void)layoutSubviews {
    %orig;
    UIView *header = (UIView *)self;
    if (![SCIUtils getBoolPref:@"instants_download_btn"]) {
        sciInstantsRemoveDLButton(header);
        return;
    }
    if (!sciInstantsHasDownloadable(header)) {
        sciInstantsRemoveDLButton(header);
        return;
    }

    SCIChromeButton *chrome = objc_getAssociatedObject(header, &kSCIInstantsDLBtnKey);
    UIButton *hit = objc_getAssociatedObject(header, &kSCIInstantsDLHitKey);
    if (!chrome || !hit) {
        // Visible chrome (capture-aware) + invisible UIButton hit target.
        // Splitting these survives the menu-platter absorption on dismiss.
        chrome = [[SCIChromeButton alloc] initWithSymbol:@"arrow.down"
                                               pointSize:18
                                                diameter:40];
        chrome.bubbleColor = [UIColor colorWithWhite:0 alpha:0.45];
        chrome.iconTint = [UIColor whiteColor];
        chrome.userInteractionEnabled = NO;
        chrome.translatesAutoresizingMaskIntoConstraints = YES;
        [header addSubview:chrome];

        hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.backgroundColor = [UIColor clearColor];
        hit.translatesAutoresizingMaskIntoConstraints = YES;
        [header addSubview:hit];

        objc_setAssociatedObject(header, &kSCIInstantsDLBtnKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(header, &kSCIInstantsDLHitKey, hit, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    sciInstantsWireActionButton(chrome, hit, header);

    CGFloat side = 40.0;
    CGFloat gap  = 8.0;
    CGFloat halfW = header.bounds.size.width / 2.0;

    UIView *anchor = nil;
    CGFloat minX = CGFLOAT_MAX;
    for (UIView *sv in header.subviews) {
        if (sv == chrome || sv == hit) continue;
        if (sv.hidden || sv.alpha < 0.01) continue;
        if (sv.bounds.size.width < 4 || sv.bounds.size.height < 4) continue;
        if (CGRectGetMidX(sv.frame) < halfW) continue;
        if (CGRectGetMinX(sv.frame) < minX) {
            minX = CGRectGetMinX(sv.frame);
            anchor = sv;
        }
    }

    CGRect frame;
    if (anchor) {
        frame = CGRectMake(CGRectGetMinX(anchor.frame) - side - gap,
                           CGRectGetMidY(anchor.frame) - side / 2,
                           side, side);
    } else {
        frame = CGRectMake(header.bounds.size.width - side - 12,
                           (header.bounds.size.height - side) / 2,
                           side, side);
    }
    chrome.frame = frame;
    hit.frame = frame;
    chrome.hidden = NO;
    chrome.alpha = 1.0;
    hit.hidden = NO;
    hit.alpha = 1.0;
    [header bringSubviewToFront:chrome];
    [header bringSubviewToFront:hit];
}
%end

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:SCIActionMenuConfigDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *n) {
        NSNumber *src = n.userInfo[@"source"];
        if (src.integerValue == SCIActionSourceInstants) sciInstantsConfigVersion++;
    }];
}
