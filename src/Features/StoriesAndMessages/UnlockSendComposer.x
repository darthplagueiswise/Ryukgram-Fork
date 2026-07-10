// Bypasses the DM "You can't send messages" banner and restores the text input
// in restricted threads. Force the cached send-block state available at its
// setters so the banner, composer and message-list inset all stay consistent;
// also force the helper for the path that reads it before the state is built.
// Sends may still be rejected server-side. Group only inits when the pref is on.
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

%group UnlockSendComposer

%hook IGDirectThreadViewUnavailableComposerHelper
- (long long)unavailableComposerType {
	return 0;
}
%end

%hook IGDirectThreadViewSessionState

- (void)setCurrentUnavailableComposerType:(long long)type {
	%orig(0);
}

- (void)setIsThreadInputDisabled:(BOOL)disabled {
	%orig(NO);
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"unlock_send_composer"]) {
		%init(UnlockSendComposer);
	}
}
