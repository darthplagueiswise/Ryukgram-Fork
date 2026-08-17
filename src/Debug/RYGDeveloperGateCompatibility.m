#import "RYGDeveloperGateViewController.h"

// Compatibility note
// ------------------
// This file previously installed a second refreshGates swizzle and duplicated
// Objective-C image/method enumeration independently of the runtime browser.
// RYGDeveloperGateABICompatibility is now the only compatibility adapter for
// developer surfaces and consumes RYGRuntimeBrowserEngine's authoritative live
// scanner. Leaving this translation unit as a no-op prevents constructor order
// from selecting different scanners for Runtime Browser vs Prism/Glass/WordMark.
