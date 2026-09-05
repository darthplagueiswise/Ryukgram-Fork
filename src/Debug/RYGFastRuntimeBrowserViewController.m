#import "RYGFastRuntimeBrowserViewController.h"

// Compatibility subclass only. All runtime discovery, typed editing,
// persistence, Apply/PENDING semantics and receiver observation live in the
// canonical WAT dogfood2-derived RYGPorted/RYGRuntimeSurface owners.
@implementation RYGFastRuntimeBrowserViewController

- (instancetype)initWithTitle:(NSString *)title initialQuery:(NSString *)initialQuery {
    return [super initWithTitle:title initialQuery:initialQuery];
}

- (instancetype)initWithTitle:(NSString *)title
                 initialQuery:(NSString *)initialQuery
allowsBulkVisibilityOverride:(BOOL)allowsBulkVisibilityOverride {
    return [super initWithTitle:title
                   initialQuery:initialQuery
  allowsBulkVisibilityOverride:allowsBulkVisibilityOverride];
}

@end
