// Story interaction pipeline — confirm gate + seen/advance per policy table.

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RYGStoryInteraction) {
    RYGStoryInteractionLike,
    RYGStoryInteractionEmojiReaction,
    RYGStoryInteractionTextReply,
};

void rygStoryInteraction(RYGStoryInteraction type,
                         void (^action)(void),
                         void (^_Nullable uiRevert)(void),
                         void (^_Nullable uiReapply)(void));

// Side-effects only (seen/advance). No confirm, no action.
void rygStoryInteractionSideEffects(RYGStoryInteraction type);
