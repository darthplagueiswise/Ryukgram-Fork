// SCISymbolBrowserBootstrap.x — re-applies persisted symbol-browser overrides at
// launch so forced BOOLs take effect before any UI is built. The engine returns
// immediately when the override dict is empty, so this is free for users who
// never forced anything (priv-main launch discipline).
#import "SCISymbolBrowserEngine.h"

%ctor {
	@autoreleasepool {
		[SCISymbolBrowserEngine reinstallPersistedHooks];
	}
}
