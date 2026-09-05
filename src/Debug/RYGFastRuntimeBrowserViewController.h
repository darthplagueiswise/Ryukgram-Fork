#pragma once
#import "RYGPortedRuntimeBrowserViewController.h"

// Compatibility name kept for older Developer call sites. The implementation
// is intentionally the WAT dogfood2-derived browser; the previous independent
// RyukGram browser engine/UI is no longer instantiated through this class.
@interface RYGFastRuntimeBrowserViewController : RYGPortedRuntimeBrowserViewController
- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery;
- (instancetype)initWithTitle:(NSString *)title
                 initialQuery:(NSString *)initialQuery
allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride;
@end
