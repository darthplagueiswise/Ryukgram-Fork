#import "RYGDeveloperRuntimeBrowserViewController.h"

// The structured runtime browser now owns class navigation, ABI inspection,
// live observation and safe BOOL actions. Keep the developer entry point as a
// distinct class for routing/feature ownership, without overriding table
// selection and accidentally swallowing class-row taps.
@implementation RYGDeveloperRuntimeBrowserViewController
@end