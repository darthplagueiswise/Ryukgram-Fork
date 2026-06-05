#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Defined in SeenButtons.x
extern BOOL sciAutoTypingEnabled(void);
extern void sciDoAutoSeenActiveThread(void);

%hook IGDirectTypingStatusService

- (void)updateOutgoingStatusIsActive:(_Bool)active threadKey:(id)key threadMetadata:(id)metadata typingStatusType:(long long)type {
	if (active && sciAutoTypingEnabled()) {
		sciDoAutoSeenActiveThread();
	}

	if ([SCIUtils getBoolPref:@"disable_typing_status"]) return;

	%orig(active, key, metadata, type);
}

%end