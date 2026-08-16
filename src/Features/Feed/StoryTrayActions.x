// Story tray long-press actions — adds "Profile picture" to the legacy action sheet
// and the IG-Subscriptions story-peek prism menu. HD pic via /api/v1/users/{pk}/info/.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../ActionButton/RYGMediaViewer.h"
#import "../../Networking/RYGInstagramAPI.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static __weak id rygLongPressedTrayCell = nil;
static __weak id rygPeekCell = nil;

// ── Helpers ──

static UIImage *rygProfileImageFromCell(id cell) {
    Ivar avIvar = class_getInstanceVariable([cell class], "_avatarView");
    if (!avIvar) return nil;
    UIView *avatarView = object_getIvar(cell, avIvar);
    if (!avatarView) return nil;
    Ivar imgIvar = class_getInstanceVariable([avatarView class], "_ownerImageView");
    if (!imgIvar) return nil;
    UIImageView *imgView = object_getIvar(avatarView, imgIvar);
    if ([imgView isKindOfClass:[UIImageView class]]) return imgView.image;
    return nil;
}

static NSString *rygUsernameFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id title = [model valueForKey:@"title"];
        if ([title isKindOfClass:[NSAttributedString class]])
            return [[(NSAttributedString *)title string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } @catch (NSException *e) {}
    return nil;
}

static NSString *rygFullNameFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id owner = [model valueForKey:@"reelOwner"];
        if (!owner) return nil;
        Ivar ui = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!ui) return nil;
        id igUser = object_getIvar(owner, ui);
        Ivar fi = NULL;
        for (Class c = [igUser class]; c && !fi; c = class_getSuperclass(c))
            fi = class_getInstanceVariable(c, "_fieldCache");
        if (!fi) return nil;
        id fc = object_getIvar(igUser, fi);
        if (![fc isKindOfClass:[NSDictionary class]]) return nil;
        id name = [(NSDictionary *)fc objectForKey:@"full_name"];
        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) return name;
    } @catch (NSException *e) {}
    return nil;
}

static NSString *rygCaptionFromCell(id cell) {
    NSString *username = rygUsernameFromCell(cell);
    NSString *fullName = rygFullNameFromCell(cell);
    if (username && fullName) return [NSString stringWithFormat:@"%@\n%@", username, fullName];
    return username ?: fullName;
}

static NSString *rygUserPKFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id owner = [model valueForKey:@"reelOwner"];
        if (!owner) return nil;
        Ivar ui = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!ui) return nil;
        id igUser = object_getIvar(owner, ui);
        Ivar pi = NULL;
        for (Class c = [igUser class]; c && !pi; c = class_getSuperclass(c))
            pi = class_getInstanceVariable(c, "_pk");
        if (!pi) return nil;
        return [object_getIvar(igUser, pi) description];
    } @catch (NSException *e) {}
    return nil;
}

// Fetch HD profile pic via API, fallback to local avatar
static void rygShowHDProfilePic(NSString *pk, NSString *caption, UIImage *fallback) {
    NSString *path = [NSString stringWithFormat:@"users/%@/info/", pk];
    [RYGInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error || !response) {
            if (fallback) {
                NSData *d = UIImageJPEGRepresentation(fallback, 1.0);
                NSURL *p = [RYGTempFiles claimWithExt:@"jpg" ttl:900 tag:[@"pfp_" stringByAppendingString:pk ?: @"x"]];
                [d writeToFile:p.path atomically:YES];
                [RYGMediaViewer showWithVideoURL:nil photoURL:p caption:caption];
            }
            return;
        }

        NSDictionary *user = response[@"user"];
        NSString *hdURL = nil;

        NSDictionary *hdInfo = user[@"hd_profile_pic_url_info"];
        if ([hdInfo isKindOfClass:[NSDictionary class]]) hdURL = hdInfo[@"url"];

        if (!hdURL) {
            NSArray *versions = user[@"hd_profile_pic_versions"];
            if ([versions isKindOfClass:[NSArray class]] && versions.count > 0)
                hdURL = [versions.lastObject objectForKey:@"url"];
        }

        if (!hdURL) hdURL = user[@"profile_pic_url"];

        if (hdURL) {
            [RYGMediaViewer showWithVideoURL:nil photoURL:[NSURL URLWithString:hdURL] caption:caption];
        } else if (fallback) {
            NSData *d = UIImageJPEGRepresentation(fallback, 1.0);
            NSURL *p = [RYGTempFiles claimWithExt:@"jpg" ttl:900 tag:[@"pfp_" stringByAppendingString:pk ?: @"x"]];
            [d writeToFile:p.path atomically:YES];
            [RYGMediaViewer showWithVideoURL:nil photoURL:p caption:caption];
        }
    }];
}

// ── Capture long-pressed cell ──

static void (*orig_didLongPressCell)(id, SEL, UIGestureRecognizer *);
static void hook_didLongPressCell(id self, SEL _cmd, UIGestureRecognizer *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan)
        rygLongPressedTrayCell = gesture.view;
    orig_didLongPressCell(self, _cmd, gesture);
}

// ── Inject action into the sheet ──

static void (*orig_present)(id, SEL, id, BOOL, id);
static void hook_present(id self, SEL _cmd, id vc, BOOL animated, id completion) {
    if (rygLongPressedTrayCell && [NSStringFromClass([vc class]) containsString:@"StoryPeek"])
        rygPeekCell = rygLongPressedTrayCell;
    if (rygLongPressedTrayCell && [RYGUtils getBoolPref:@"story_tray_actions"]) {
        Ivar actIvar = class_getInstanceVariable([vc class], "_actions");
        NSArray *actions = actIvar ? object_getIvar(vc, actIvar) : nil;

        if (actions) {
            id cell = rygLongPressedTrayCell;
            rygLongPressedTrayCell = nil;

            Class actionCls = NSClassFromString(@"IGActionSheetControllerAction");
            NSString *pk = rygUserPKFromCell(cell);
            if (actionCls && pk) {
                NSString *caption = rygCaptionFromCell(cell);
                UIImage *localPic = rygProfileImageFromCell(cell);

                typedef id (*InitFn)(id, SEL, id, id, NSInteger, id, id, id);
                void (^handler)(void) = ^{ rygShowHDProfilePic(pk, caption, localPic); };
                id action = ((InitFn)objc_msgSend)([actionCls alloc],
                    @selector(initWithTitle:subtitle:style:handler:accessibilityIdentifier:accessibilityLabel:),
                    RYGLocalized(@"Profile picture"), nil, (NSInteger)0, handler, nil, nil);

                if (action) {
                    NSMutableArray *newActions = [actions mutableCopy];
                    [newActions insertObject:action atIndex:0];
                    object_setIvar(vc, actIvar, [newActions copy]);
                }
            }
        }
    }

    if (rygLongPressedTrayCell) rygLongPressedTrayCell = nil;
    orig_present(self, _cmd, vc, animated, completion);
}

// The story-peek menu (IGDSPrismMenuView) is built from fixed Swift handlers (no
// items array), so we inject a row from the menu's own layoutSubviews, styled from
// the last native row; tap dismisses the peek and opens the HD profile pic.
@interface RYGTrayPeekTap : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *menuView;
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, strong) UIImage *fallback;
@end
@implementation RYGTrayPeekTap
- (void)tap {
    NSString *pk = self.pk; NSString *cap = self.caption; UIImage *fb = self.fallback;
    UIResponder *r = self.menuView;
    while (r && ![r isKindOfClass:UIViewController.class]) r = r.nextResponder;
    UIViewController *vc = (UIViewController *)r;
    if (vc) [vc dismissViewControllerAnimated:YES completion:^{ rygShowHDProfilePic(pk, cap, fb); }];
    else rygShowHDProfilePic(pk, cap, fb);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)o { return YES; }
@end

static const void *kRygPeekInjectedKey = &kRygPeekInjectedKey;

static void rygInjectPeekRow(UIView *menuView, id cell) {
    if (!menuView || objc_getAssociatedObject(menuView, kRygPeekInjectedKey)) return;
    NSString *pk = rygUserPKFromCell(cell);
    if (!pk) return;

    Ivar elIvar = class_getInstanceVariable([menuView class], "menuElementViews");
    NSArray *elements = elIvar ? object_getIvar(menuView, elIvar) : nil;
    if (![elements isKindOfClass:[NSArray class]] || elements.count == 0) return;
    UIView *template = elements.lastObject;
    if (!template.superview) return;

    Class builderClass = NSClassFromString(@"IGDSPrismMenuItemBuilder");
    Class itemViewClass = NSClassFromString(@"_TtC13IGDSPrismMenu21IGDSPrismMenuItemView");
    if (!builderClass || !itemViewClass) return;

    id builder = ((id(*)(id,SEL,id))objc_msgSend)([builderClass alloc], @selector(initWithTitle:), RYGLocalized(@"Profile picture"));
    builder = ((id(*)(id,SEL,id))objc_msgSend)(builder, @selector(withHandler:), ^{});
    id menuItem = ((id(*)(id,SEL))objc_msgSend)(builder, @selector(build));
    if (!menuItem) return;

    BOOL edr = NO;
    Ivar edrIv = class_getInstanceVariable([template class], "edrEnabled");
    if (edrIv) edr = *(BOOL *)((uint8_t *)(__bridge void *)template + ivar_getOffset(edrIv));
    UIView *itemView = ((id(*)(id,SEL,id,BOOL,BOOL,BOOL))objc_msgSend)([itemViewClass alloc],
        @selector(initWithMenuItem:edrEnabled:isHeader:isSubmenu:), menuItem, edr, NO, NO);
    if (!itemView) return;

    CGFloat h = template.frame.size.height, x = template.frame.origin.x, w = template.frame.size.width;
    CGFloat y = CGRectGetMaxY(template.frame);

    RYGTrayPeekTap *target = [RYGTrayPeekTap new];
    target.menuView = menuView;
    target.pk = pk;
    target.caption = rygCaptionFromCell(cell);
    target.fallback = rygProfileImageFromCell(cell);

    UIControl *wrapper = [[UIControl alloc] initWithFrame:CGRectMake(x, y, w, h)];
    itemView.frame = wrapper.bounds;
    itemView.userInteractionEnabled = NO;
    [wrapper addSubview:itemView];
    [wrapper addTarget:target action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    UITapGestureRecognizer *ownTap = [[UITapGestureRecognizer alloc] initWithTarget:target action:@selector(tap)];
    ownTap.delegate = target;
    [wrapper addGestureRecognizer:ownTap];
    [template.superview addSubview:wrapper];

    CGRect mF = menuView.frame; mF.size.height += h; menuView.frame = mF;
    UIView *node = template.superview;
    while (node && node != menuView) {
        CGRect nf = node.frame; nf.size.height += h; node.frame = nf; node.clipsToBounds = NO;
        node = node.superview;
    }
    menuView.clipsToBounds = NO;
    objc_setAssociatedObject(menuView, kRygPeekInjectedKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    rygPeekCell = nil;
}

static void (*orig_prismLayout)(id, SEL);
static void new_prismLayout(id self, SEL _cmd) {
    orig_prismLayout(self, _cmd);
    if (rygPeekCell && [RYGUtils getBoolPref:@"story_tray_actions"])
        rygInjectPeekRow((UIView *)self, rygPeekCell);
}

%ctor {
    Class prism = NSClassFromString(@"_TtC13IGDSPrismMenu17IGDSPrismMenuView");
    if (prism && class_getInstanceMethod(prism, @selector(layoutSubviews)))
        MSHookMessageEx(prism, @selector(layoutSubviews), (IMP)new_prismLayout, (IMP *)&orig_prismLayout);

    Class scCls = NSClassFromString(@"IGStorySectionController");
    if (scCls) {
        SEL sel = NSSelectorFromString(@"_didLongPressCell:");
        if (class_getInstanceMethod(scCls, sel))
            MSHookMessageEx(scCls, sel, (IMP)hook_didLongPressCell, (IMP *)&orig_didLongPressCell);
    }

    MSHookMessageEx([UIViewController class], @selector(presentViewController:animated:completion:),
                    (IMP)hook_present, (IMP *)&orig_present);
}
