// Pure-black DM thread background + incoming bubbles.
// IGDirectThreadBackgroundImageView / IGDirectMessageBubbleView in InstagramHeaders.h.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "SCITheme.h"

static inline BOOL SCIOLEDChatActive(void) {
	return [SCITheme oledChat] && [SCITheme effectiveDark];
}

%group OLEDChatThemeGroup

%hook IGDirectThreadBackgroundImageView

- (void)layoutSubviews {
	%orig;

	if (SCIOLEDChatActive()) {
		((UIView *)self).backgroundColor = [SCITheme backgroundColor];
	}
}

- (void)setBackgroundColor:(UIColor *)color {
	if (SCIOLEDChatActive()) {
		%orig([SCITheme backgroundColor]);
		return;
	}

	%orig;
}

%end

%hook IGDirectMessageBubbleView

- (void)layoutSubviews {
	%orig;

	if (!SCIOLEDChatActive()) return;

	// Only swap the incoming-bubble surface — leaves tinted outgoing bubbles alone.
	if ([SCITheme colorIsNearBlack:self.backgroundColor]) {
		self.backgroundColor = [SCITheme backgroundColor];
	}
}

%end

%end

%ctor {
	[SCITheme migrateLegacyPrefs];

	if ([SCITheme oledChat]) {
		%init(OLEDChatThemeGroup,
			IGDirectThreadBackgroundImageView = NSClassFromString(@"_TtC33IGDirectThreadBackgroundImageView33IGDirectThreadBackgroundImageView") ?: NSClassFromString(@"IGDirectThreadBackgroundImageView"));
	}
}
