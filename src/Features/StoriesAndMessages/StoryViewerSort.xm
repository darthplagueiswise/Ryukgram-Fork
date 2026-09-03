// Replaces IG's native "who viewed my story" list with our own (RYGStoryViewerList):
// full viewer list pulled from list_reel_media_viewer (lazy-loaded), with our own
// search / filter / sort / pins. We overlay our list on the VC and hide IG's.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../UI/RYGIcon.h"
#import "RYGStoryViewerList.h"
#import <objc/runtime.h>

static const void *kListKey = &kListKey;
static const void *kNativeModeKey = &kNativeModeKey;

static id rygIvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    const char *t = ivar_getTypeEncoding(iv);
    if (!t || t[0] != '@') return nil;   // object ivars only — primitives would return garbage
    return object_getIvar(obj, iv);
}

static BOOL rygVLEnabled(void) { return [RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]; }
static BOOL rygVLDefaultNative(void) { return [[RYGUtils getStringPref:@"story_viewer_default_list"] isEqualToString:@"instagram"]; }

@interface IGStoryViewersListViewController (RYGVL)
- (NSString *)ryg_viewerMediaID;
- (void)ryg_installOurList;
- (void)ryg_toggleMode;
- (void)ryg_applyMode;
- (void)ryg_reloadList;
- (BOOL)ryg_nativeMode;
@end

%hook IGStoryViewersListViewController

%new
- (NSString *)ryg_viewerMediaID {
    id item = nil;
    @try { item = [self valueForKey:@"item"]; } @catch (__unused id e) {}
    if (!item) return nil;
    NSMutableArray *hosts = [NSMutableArray arrayWithObject:item];
    for (NSString *nested in @[@"media", @"storyItem", @"item"]) {
        @try { if ([item respondsToSelector:NSSelectorFromString(nested)]) { id s = [item valueForKey:nested]; if (s) [hosts addObject:s]; } } @catch (__unused id e) {}
    }
    for (id host in hosts) for (NSString *sel in @[@"pk", @"mediaID", @"mediaId", @"id"]) {
        @try {
            if (![host respondsToSelector:NSSelectorFromString(sel)]) continue;
            id v = [host valueForKey:sel];
            NSString *str = [v isKindOfClass:NSString.class] ? v : ([v respondsToSelector:@selector(stringValue)] ? [v stringValue] : nil);
            if (str.length) return [str componentsSeparatedByString:@"_"].firstObject ?: str;
        } @catch (__unused id e) {}
    }
    return nil;
}

%new
- (void)ryg_installOurList {
    if (objc_getAssociatedObject(self, kListKey)) return;
    NSString *mid = [self ryg_viewerMediaID];
    if (!mid.length) return;

    RYGStoryViewerListView *list = [[RYGStoryViewerListView alloc] initWithMediaID:mid];
    list.translatesAutoresizingMaskIntoConstraints = NO;
    list.backgroundColor = [RYGPopupChrome backgroundColor] ?: (self.view.backgroundColor ?: UIColor.systemBackgroundColor);
    [self.view addSubview:list];
    [NSLayoutConstraint activateConstraints:@[
        [list.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [list.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [list.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [list.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    objc_setAssociatedObject(self, kListKey, list, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self ryg_applyMode];
    [self.view bringSubviewToFront:list];
}

%new
- (BOOL)ryg_nativeMode {
    id v = objc_getAssociatedObject(self, kNativeModeKey);
    return v ? [v boolValue] : rygVLDefaultNative();
}

%new
- (void)ryg_toggleMode {
    objc_setAssociatedObject(self, kNativeModeKey, @(![self ryg_nativeMode]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self ryg_applyMode];
    UIView *list = objc_getAssociatedObject(self, kListKey);
    if (list && !list.hidden) [self.view bringSubviewToFront:list];
}

%new
- (void)ryg_reloadList { [(RYGStoryViewerListView *)objc_getAssociatedObject(self, kListKey) reload]; }

%new
- (void)ryg_applyMode {
    BOOL native = [self ryg_nativeMode];
    UIView *list = objc_getAssociatedObject(self, kListKey);
    UIView *cv = rygIvarObj(self, "_collectionView");
    if (list && list.hidden != native) list.hidden = native;
    if ([cv isKindOfClass:UIView.class] && cv.hidden == native) cv.hidden = !native;
}

// Install before the view appears and hide IG's list up front, so IG's native
// list never draws a frame before ours — no flash.
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (![RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]) return;
    UIView *cv = rygIvarObj(self, "_collectionView");
    if ([cv isKindOfClass:UIView.class] && ![self ryg_nativeMode]) cv.hidden = YES;
    [self ryg_installOurList];
}

- (void)viewDidLoad {
    %orig;
    if (![RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]) return;
    UIView *cv = rygIvarObj(self, "_collectionView");
    if ([cv isKindOfClass:UIView.class] && ![self ryg_nativeMode]) cv.hidden = YES;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (![RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]) return;
    if (!objc_getAssociatedObject(self, kListKey)) [self ryg_installOurList];
    [self ryg_applyMode];
}

%end

#pragma mark - header controls (claim IG button slots)

static const void *kHijackKey = &kHijackKey;

@interface IGStoryViewersHeaderView (RYGHdr)
- (void)ryg_hdrToggle;
- (void)ryg_hdrReload;
- (void)ryg_claimSlots;
- (void)ryg_forceSlotFlags;
@end

static IGStoryViewersListViewController *rygScanVC(UIViewController *vc, Class k) {
    if (!vc) return nil;
    if ([vc isKindOfClass:k]) return (IGStoryViewersListViewController *)vc;
    for (UIViewController *c in vc.childViewControllers) {
        IGStoryViewersListViewController *m = rygScanVC(c, k);
        if (m) return m;
    }
    return rygScanVC(vc.presentedViewController, k);
}

// The header is not in the VC's responder chain, so walk the live window tree.
static IGStoryViewersListViewController *rygViewerVC(void) {
    Class k = NSClassFromString(@"IGStoryViewersListViewController");
    if (!k) return nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            IGStoryViewersListViewController *m = rygScanVC(w.rootViewController, k);
            if (m && m.viewIfLoaded.window) return m;
        }
    }
    return nil;
}

// IG lays the header out via IGTableLayoutSpec; claiming a slot lets it position
// us on every A/B variant, which reading a button's frame never could.
static void rygClaimSlot(IGStoryViewersHeaderView *hdr, const char *ivar, SEL action, NSString *icon) {
    UIButton *b = rygIvarObj(hdr, ivar);
    if (![b isKindOfClass:UIButton.class]) return;
    objc_setAssociatedObject(b, kHijackKey, [NSValue valueWithPointer:action], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [b removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [b addTarget:hdr action:action forControlEvents:UIControlEventTouchUpInside];
    [b setImage:[RYGIcon imageNamed:icon pointSize:24] forState:UIControlStateNormal];
}

%hook IGTapButton

// IG re-adds its own target after we claim, so removeTarget: alone never sticks.
- (void)sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    NSValue *mine = objc_getAssociatedObject(self, kHijackKey);
    if (mine && [mine pointerValue] != (void *)action) return;
    %orig;
}

%end

%hook IGStoryViewersHeaderView

- (id)init {
    id r = %orig;
    if (r && rygVLEnabled()) {
        [r setShowAuraUpsellButton:YES];
        [r setShowPromoteButton:YES];
        [r ryg_claimSlots];
    }
    return r;
}

- (void)setShowAuraUpsellButton:(BOOL)show {
    if (!rygVLEnabled()) { %orig; return; }
    %orig(YES);
    [self ryg_claimSlots];
}

- (void)setShowPromoteButton:(BOOL)show {
    if (!rygVLEnabled()) { %orig; return; }
    %orig(YES);
    [self ryg_claimSlots];
}

// Server config can land after init and write the show* ivars past the setters.
- (void)didMoveToWindow {
    %orig;
    if (!rygVLEnabled() || !self.window) return;
    [self ryg_forceSlotFlags];
    [self ryg_claimSlots];
}

%new
- (void)ryg_forceSlotFlags {
    static const char *flags[] = {"_showAuraUpsellButton", "_showPromoteButton"};
    for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) {
        Ivar iv = class_getInstanceVariable([self class], flags[i]);
        if (iv) *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv)) = YES;
    }
    [self setNeedsLayout];
}

%new
- (void)ryg_claimSlots {
    BOOL native = [rygViewerVC() ryg_nativeMode];
    rygClaimSlot(self, "_auraUpsellButton", @selector(ryg_hdrToggle),
                 native ? @"ig_icon_circle_outline_24" : @"ig_icon_circle_check_outline_24");
    rygClaimSlot(self, "_promoteButton", @selector(ryg_hdrReload), @"reload_outline_24");
}

%new
- (void)ryg_hdrToggle {
    [rygViewerVC() ryg_toggleMode];
    [self ryg_claimSlots];
}

%new
- (void)ryg_hdrReload {
    [rygViewerVC() ryg_reloadList];
}

%end

%ctor {
    if ([RYGUtils getBoolPref:@"ryg_story_viewer_sort_enabled"]) %init;
}
