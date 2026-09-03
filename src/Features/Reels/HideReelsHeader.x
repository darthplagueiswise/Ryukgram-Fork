#import "../../Utils.h"
#import <substrate.h>
#import <objc/runtime.h>

// IG 443 dropped IGSundialViewerNavigationBarOld.
static void (*orig_navBarDidMoveToWindow)(id, SEL);

static void ryg_navBarDidMoveToWindow(id self, SEL _cmd) {
    orig_navBarDidMoveToWindow(self, _cmd);
    RYGProbeOnce(@"reelsheader.didmovetowindow", @"%@", NSStringFromClass(object_getClass(self)));
    if ([RYGUtils getBoolPref:@"hide_reels_header"]) [(UIView *)self removeFromSuperview];
}

%ctor {
    Class cls = NSClassFromString(@"_TtC33IGSundialViewerNavigationBarSwift28IGSundialViewerNavigationBar")
             ?: NSClassFromString(@"IGSundialViewerNavigationBarSwift.IGSundialViewerNavigationBar")
             ?: NSClassFromString(@"IGSundialViewerNavigationBar")
             ?: NSClassFromString(@"IGSundialViewerNavigationBarOld");
    RYGProbeClass(@"reelsheader.class", @"IGSundialViewerNavigationBar");
    if (!cls) return;
    MSHookMessageEx(cls, @selector(didMoveToWindow),
                    (IMP)ryg_navBarDidMoveToWindow, (IMP *)&orig_navBarDidMoveToWindow);
}
