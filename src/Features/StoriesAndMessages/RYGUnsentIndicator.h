#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// YES when the unsent tint owns this view's bubble; chat backgrounds must skip it.
BOOL RYGUnsentTintOwnsView(UIView *view);

#ifdef __cplusplus
}
#endif
