#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Generic, lazy WAT runtime browser port for RyukGram.
/// No runtime scan or persisted hook installation happens at process startup.
@interface RYGWATRuntimeBrowserViewController : UITableViewController
@end

NS_ASSUME_NONNULL_END
