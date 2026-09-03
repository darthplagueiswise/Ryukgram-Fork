// RYGActionButton — wires a UIButton to the RyukGram action menu system.
// Tap fires the default action; long-press opens the full context menu.

#import <UIKit/UIKit.h>
#import "RYGMediaActions.h"

NS_ASSUME_NONNULL_BEGIN

typedef id _Nullable (^RYGActionMediaProvider)(UIView *sourceView);

@interface RYGActionButton : NSObject

/// Key for an optional dismiss callback block (void(^)(void)) stored on
/// the button via objc_setAssociatedObject. Called when the context menu
/// or UIMenu dismisses. Used by stories to resume playback.
extern const void *kRYGDismissKey;

/// Configure an existing UIButton with RyukGram action-menu behavior.
///
/// `prefKey` is the NSUserDefaults key storing the default-tap choice
/// (one of `menu`, `expand`, `download_share`, `download_photos`).
+ (void)configureButton:(UIButton *)button
                context:(RYGActionContext)ctx
                prefKey:(NSString *)prefKey
          mediaProvider:(RYGActionMediaProvider)provider;

/// Build the deferred UIMenu for a given context + provider. Exposed so
/// callers that already have their own UIButton wiring can reuse just the
/// menu construction.
+ (UIMenu *)deferredMenuForContext:(RYGActionContext)ctx
                          fromView:(UIView *)sourceView
                     mediaProvider:(RYGActionMediaProvider)provider;

/// Haptic + scale-bounce feedback.
+ (void)bounceButton:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
