#import "RYGMessageListTracker.h"
#import <substrate.h>

static __weak id rygLiveMessageListDataSource;

id rygCurrentMessageListDataSource(void) { return rygLiveMessageListDataSource; }

static __weak id rygLiveThreadPaginationHandler;

id rygCurrentThreadPaginationHandler(void) { return rygLiveThreadPaginationHandler; }

static id (*orig_paginationHandlerInit)(id, SEL, id);
static id new_paginationHandlerInit(id self, SEL _cmd, id fetcher) {
	id result = orig_paginationHandlerInit(self, _cmd, fetcher);
	if (result) rygLiveThreadPaginationHandler = result;
	RYGProbeOnce(@"jump.tracker.pagination", @"%@", NSStringFromClass([result class]));
	return result;
}

static void (*orig_listDidUpdate)(id, SEL, id, id, BOOL, unsigned long long);
static void new_listDidUpdate(id self, SEL _cmd, id source, id diff, BOOL initial, unsigned long long reason) {
	if (source) rygLiveMessageListDataSource = source;
	RYGProbeOnce(@"jump.tracker.datasource", @"%@", NSStringFromClass([source class]));
	orig_listDidUpdate(self, _cmd, source, diff, initial, reason);
}

%ctor {
	Class cls = NSClassFromString(@"IGDirectMessageListDataSourceAdapter");
	SEL sel = NSSelectorFromString(@"messageListDataSource:didUpdateWithDiffResult:isInitialLoad:updateReason:");

	if (cls && class_getInstanceMethod(cls, sel)) {
		MSHookMessageEx(cls, sel, (IMP)new_listDidUpdate, (IMP *)&orig_listDidUpdate);
	}

	Class handler = NSClassFromString(@"IGDirectMDCoreThreadPaginationHandler");
	SEL handlerInit = NSSelectorFromString(@"initWithDirectThreadDataFetcher:");

	if (handler && class_getInstanceMethod(handler, handlerInit)) {
		MSHookMessageEx(handler, handlerInit, (IMP)new_paginationHandlerInit, (IMP *)&orig_paginationHandlerInit);
	}
}
