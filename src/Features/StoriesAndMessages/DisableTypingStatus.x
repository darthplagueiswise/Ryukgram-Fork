#import "../../Utils.h"
#import "../../InstagramHeaders.h"

extern BOOL rygAutoTypingEnabled(void);
extern void rygDoAutoSeenActiveThread(void);

%hook IGDirectTypingStatusService
- (void)updateOutgoingStatusIsActive:(_Bool)active threadKey:(id)key threadMetadata:(id)meta typingStatusType:(long long)type {
    if (active && rygAutoTypingEnabled()) rygDoAutoSeenActiveThread();
    if ([RYGUtils getBoolPref:@"disable_typing_status"]) return;
    %orig(active, key, meta, type);
}
%end
