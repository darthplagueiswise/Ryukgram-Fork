// Skip the sensitive-content cover by withholding its descriptor at the data
// layer. nil-ing mediaOverlay/mediaOverlayInfo

#import <UIKit/UIKit.h>
#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static inline BOOL sci_skipSensitiveOn(void) {
    return [SCIUtils getBoolPref:@"skip_sensitive_content"];
}

%hook IGMedia
- (id)mediaOverlay {
    if (sci_skipSensitiveOn()) return nil;
    return %orig;
}
- (id)mediaOverlayInfo {
    if (sci_skipSensitiveOn()) return nil;
    return %orig;
}
%end
