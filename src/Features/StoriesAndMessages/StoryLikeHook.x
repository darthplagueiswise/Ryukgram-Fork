// Story like button hook. Routes through the interaction pipeline.

#import "RYGStoryInteractionPipeline.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static void (*orig_rygStoryLikeTap)(id, SEL, id);
static void new_rygStoryLikeTap(id self, SEL _cmd, id button) {
    BOOL isSelected = [button isKindOfClass:[UIButton class]] ? [(UIButton *)button isSelected] : NO;
    if (!isSelected) { orig_rygStoryLikeTap(self, _cmd, button); return; }

    UIButton *btn = (UIButton *)button;
    SEL setLiked = NSSelectorFromString(@"setIsLiked:animated:");

    rygStoryInteraction(RYGStoryInteractionLike,
        ^{ orig_rygStoryLikeTap(self, _cmd, button); },
        ^{
            [UIView performWithoutAnimation:^{
                [btn setSelected:NO];
                if ([btn respondsToSelector:setLiked])
                    ((void(*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLiked, NO, NO);
            }];
        },
        ^{
            [btn setSelected:YES];
            if ([btn respondsToSelector:setLiked])
                ((void(*)(id, SEL, BOOL, BOOL))objc_msgSend)(btn, setLiked, YES, YES);
        });
}

%ctor {
    Class cls = NSClassFromString(@"_TtC22IGStoryLikesController38IGStoryLikesInteractionControllingImpl");
    if (!cls) cls = NSClassFromString(@"IGStoryLikesInteractionControllingImpl");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"handleStoryLikeTapWith:");
    if (!class_getInstanceMethod(cls, sel)) sel = NSSelectorFromString(@"handleStoryLikeTapWithButton:");
    if (!class_getInstanceMethod(cls, sel)) return;
    MSHookMessageEx(cls, sel, (IMP)new_rygStoryLikeTap, (IMP *)&orig_rygStoryLikeTap);
}
