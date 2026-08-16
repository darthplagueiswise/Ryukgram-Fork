// Pure-black DM thread background + incoming bubbles.
// IGDirectThreadBackgroundImageView / IGDirectMessageBubbleView in InstagramHeaders.h.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "RYGTheme.h"

static inline BOOL RYGOLEDChatActive(void) {
	return [RYGTheme oledChat] && [RYGTheme effectiveDark];
}

%group OLEDChatThemeGroup

%hook IGDirectThreadBackgroundImageView

- (void)layoutSubviews {
	%orig;

	if (RYGOLEDChatActive()) {
		((UIView *)self).backgroundColor = [RYGTheme backgroundColor];
	}
}

- (void)setBackgroundColor:(UIColor *)color {
	if (RYGOLEDChatActive()) {
		%orig([RYGTheme backgroundColor]);
		return;
	}

	%orig;
}

%end

%hook IGDirectMessageBubbleView

- (void)layoutSubviews {
	%orig;

	if (!RYGOLEDChatActive()) return;

	// Only swap the incoming-bubble surface — leaves tinted outgoing bubbles alone.
	if ([RYGTheme colorIsNearBlack:self.backgroundColor]) {
		self.backgroundColor = [RYGTheme backgroundColor];
	}
}

%end

%end

%ctor {
	[RYGTheme migrateLegacyPrefs];

	if ([RYGTheme oledChat]) {
		%init(OLEDChatThemeGroup,
			IGDirectThreadBackgroundImageView = NSClassFromString(@"_TtC33IGDirectThreadBackgroundImageView33IGDirectThreadBackgroundImageView") ?: NSClassFromString(@"IGDirectThreadBackgroundImageView"));
	}
}