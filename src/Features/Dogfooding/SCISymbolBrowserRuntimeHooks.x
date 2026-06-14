#import "SCISymbolBrowserEngine.h"

%ctor {
	@autoreleasepool {
		[SCISymbolBrowserEngine reinstallPersistedHooks];
	}
}
