// SCISymbolsBrowserViewController.h
// ABI-aware Mach-O browser for Instagram/FBShared symbols.

#import "SCIBaseSettingsListViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCICSymbolsBrowserMode) {
    SCICSymbolsBrowserModeCFunctions = 0,
    SCICSymbolsBrowserModeDataParams = 1,
    SCICSymbolsBrowserModeSwiftDisassembly = 2,
};

@interface SCISymbolsBrowserViewController : SCIBaseSettingsListViewController <UISearchBarDelegate>
- (instancetype)initWithMode:(SCICSymbolsBrowserMode)mode;
@end

NS_ASSUME_NONNULL_END
