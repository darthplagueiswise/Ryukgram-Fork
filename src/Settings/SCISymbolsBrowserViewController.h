// SCISymbolsBrowserViewController.h
// ABI-aware, on-demand Mach-O browser for the executable and every loaded app
// framework/dylib. No symbol catalogue or ASLR address is preloaded/persisted.

#import "SCIBaseSettingsListViewController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCICSymbolsBrowserMode) {
    SCICSymbolsBrowserModeObjCMethods = 0,
    SCICSymbolsBrowserModeCFunctions = 1,
    SCICSymbolsBrowserModeDataParams = 2,
    SCICSymbolsBrowserModeSwiftDisassembly = 3,
};

@interface SCISymbolsBrowserViewController : SCIBaseSettingsListViewController <UISearchResultsUpdating>
- (instancetype)initWithMode:(SCICSymbolsBrowserMode)mode;
@end

NS_ASSUME_NONNULL_END
