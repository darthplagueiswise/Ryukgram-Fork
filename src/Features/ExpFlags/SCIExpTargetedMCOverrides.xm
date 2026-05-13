#import <Foundation/Foundation.h>

// beta2 hotfix:
// The first targeted MobileConfig bridge was still too risky for launch. Some
// MobileConfig getter arguments are not guaranteed Objective-C objects, so
// probing them as id can crash as soon as a related toggle is ON.
//
// Keep this translation unit present for build stability, but install no hooks.
// MC override work must stay observe-only until each getter ABI/callsite is
// proven from the actual executable/framework.

__attribute__((constructor))
static void SCIExpTargetedMCOverridesBootstrap(void) {
    // Intentionally inert. No MobileConfig ObjC/C hooks are installed here.
}
