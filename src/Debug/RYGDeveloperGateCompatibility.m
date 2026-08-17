#import "RYGDeveloperGateViewController.h"

// Compatibility note
// ------------------
// This translation unit intentionally installs nothing. The former second
// refreshGates swizzle duplicated image/method enumeration and made constructor
// order select different implementations. RYGDeveloperGateABICompatibility is
// the only adapter now; it performs an image-scoped, surface-targeted scan of
// Instagram + FBSharedFramework instead of enumerating all safe BOOL methods.
