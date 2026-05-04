#import <Foundation/Foundation.h>

// IMPORTANT:
// This file used to install a process-wide BOOL getter hook over every loaded
// Objective-C class whose class or selector contained broad tokens such as
// "enabled". That accidentally matched system/framework selectors such as
// -[WKScrollView isScrollEnabled], causing recursive WebKit calls and a stack
// guard crash before the DexKit UI could even be used.
//
// DexKit must stay metadata-only by default. Live observation/override should be
// implemented later as an explicit opt-in per provider/getter owner, never as a
// global runtime sweep.

%ctor {
    NSLog(@"[RyukGram][RuntimeExperiments] global BOOL hook router disabled; DexKit is metadata-only by default");
}
