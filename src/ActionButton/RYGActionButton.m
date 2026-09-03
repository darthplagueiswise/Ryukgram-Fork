#import "RYGActionButton.h"
#import "RYGActionMenu.h"
#import "RYGRepostSheet.h"
#import "../Utils.h"
#import "../Features/StoriesAndMessages/OverlayHelpers.h"
#import <objc/runtime.h>

static const void *kRYGCtxKey       = &kRYGCtxKey;
static const void *kRYGProviderKey  = &kRYGProviderKey;
static const void *kRYGPrefKey      = &kRYGPrefKey;
const void *kRYGDismissKey   = &kRYGDismissKey;


@interface RYGActionButton () <UIContextMenuInteractionDelegate>
@end

@implementation RYGActionButton

+ (instancetype)shared {
    static RYGActionButton *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [RYGActionButton new]; });
    return s;
}

+ (UIMenu *)deferredMenuForContext:(RYGActionContext)ctx
                          fromView:(UIView *)sourceView
                     mediaProvider:(RYGActionMediaProvider)provider {
    __weak UIView *weakSource = sourceView;
    RYGActionMediaProvider capturedProvider = [provider copy];

    UIDeferredMenuElement *deferred = [UIDeferredMenuElement
        elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> * _Nonnull)) {
        UIView *view = weakSource;
        id media = (view && capturedProvider) ? capturedProvider(view) : nil;
        NSArray *actions = [RYGMediaActions actionsForContext:ctx
                                                        media:media
                                                     fromView:view];
        UIMenu *built = [RYGActionMenu buildMenuWithActions:actions];
        completion(built.children);
    }];

    return [UIMenu menuWithTitle:@""
                           image:nil
                      identifier:nil
                         options:0
                        children:@[deferred]];
}

+ (void)configureButton:(UIButton *)button
                context:(RYGActionContext)ctx
                prefKey:(NSString *)prefKey
          mediaProvider:(RYGActionMediaProvider)provider {
    if (!button) return;

    objc_setAssociatedObject(button, kRYGCtxKey, @(ctx), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, kRYGProviderKey, [provider copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(button, kRYGPrefKey, [prefKey copy], OBJC_ASSOCIATION_COPY_NONATOMIC);

    NSString *defaultTap = [RYGUtils getStringPref:prefKey];
    if (!defaultTap.length) defaultTap = @"menu";

    [button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
    for (id<UIInteraction> it in [button.interactions copy]) {
        if ([(id)it isKindOfClass:[UIContextMenuInteraction class]]) {
            [button removeInteraction:it];
        }
    }

    if ([defaultTap isEqualToString:@"menu"]) {
        button.menu = [self deferredMenuForContext:ctx fromView:button mediaProvider:provider];
        button.showsMenuAsPrimaryAction = YES;
        return;
    }

    button.showsMenuAsPrimaryAction = NO;
    button.menu = nil;
    [button addTarget:[self shared]
               action:@selector(rygTapHandler:)
     forControlEvents:UIControlEventTouchUpInside];

    UIContextMenuInteraction *interaction =
        [[UIContextMenuInteraction alloc] initWithDelegate:[self shared]];
    [button addInteraction:interaction];
}

+ (void)bounceButton:(UIView *)view {
    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [UIView animateWithDuration:0.1
                     animations:^{ view.transform = CGAffineTransformMakeScale(0.82, 0.82); }
                     completion:^(BOOL _) {
        [UIView animateWithDuration:0.1 animations:^{
            view.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)rygTapHandler:(UIButton *)sender {
    [RYGActionButton bounceButton:sender];

    NSNumber *ctxNum = objc_getAssociatedObject(sender, kRYGCtxKey);
    RYGActionMediaProvider provider = objc_getAssociatedObject(sender, kRYGProviderKey);
    NSString *prefKey = objc_getAssociatedObject(sender, kRYGPrefKey);
    if (!ctxNum || !provider) return;

    NSString *tap = [RYGUtils getStringPref:prefKey];
    if (!tap.length) tap = @"menu";
    if ([tap isEqualToString:@"menu"]) return;

    id media = provider(sender);
    if (media == (id)kCFNull) return;

    RYGActionContext tapCtx = (RYGActionContext)ctxNum.integerValue;

    // Legacy values from older builds — translate before dispatch.
    if ([tap isEqualToString:@"copy_link"])       tap = @"copy_url";
    if ([tap isEqualToString:@"download_photos"]) tap = @"download_save";

    [RYGMediaActions executeActionForContext:tapCtx actionID:tap media:media fromView:sender];

    void (^dismiss)(void) = objc_getAssociatedObject(sender, kRYGDismissKey);
    if (dismiss) dismiss();
}

// MARK: - UIContextMenuInteractionDelegate

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    UIView *view = interaction.view;
    NSNumber *ctxNum = objc_getAssociatedObject(view, kRYGCtxKey);
    RYGActionMediaProvider provider = objc_getAssociatedObject(view, kRYGProviderKey);
    if (!ctxNum || !provider) return nil;
    RYGActionContext ctx = (RYGActionContext)ctxNum.integerValue;

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggested) {
        return [RYGActionButton deferredMenuForContext:ctx
                                              fromView:view
                                         mediaProvider:provider];
    }];
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction
    willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                   animator:(id<UIContextMenuInteractionAnimating>)animator {
    UIView *view = interaction.view;
    void (^dismiss)(void) = objc_getAssociatedObject(view, kRYGDismissKey);
    if (dismiss) {
        if (animator) {
            [animator addCompletion:^{ dismiss(); }];
        } else {
            dismiss();
        }
    }
}

@end
