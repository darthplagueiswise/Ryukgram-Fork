// Skip the sensitive-content cover by withholding its descriptor at the data
// layer. nil-ing mediaOverlay/mediaOverlayInfo

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL ryg_skipSensitiveOn(void) {
    return [RYGUtils getBoolPref:@"skip_sensitive_content"];
}

%hook IGMedia
- (id)mediaOverlay {
    if (ryg_skipSensitiveOn()) return nil;
    return %orig;
}
- (id)mediaOverlayInfo {
    if (ryg_skipSensitiveOn()) return nil;
    return %orig;
}
%end
