#import "RYGJumpToMessage.h"
#import "RYGMessageListTracker.h"
#import "../../Localization/RYGLocalization.h"
#import "../../UI/Notification/RYGNotificationCenter.h"
#import "../../UI/Notification/RYGNotificationActions.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSUInteger const kMaxAttempts = 90;
static NSUInteger const kPagingStartsAt = 16;
static NSTimeInterval const kRetryDelay = 0.3;

static BOOL sCancelled;

@implementation RYGJumpToMessage

static Class messageListClass(void) {
	return NSClassFromString(@"_TtC33IGDirectMessageListViewController33IGDirectMessageListViewController");
}

static SEL resolveSelector(void) {
	return NSSelectorFromString(@"messageViewModelForServerIdentifier:");
}

// Announcers forward every selector, so respondsToSelector: matches objects that drop the call.
static BOOL reallyImplements(id obj, SEL sel) {
	return obj && sel && class_getInstanceMethod([obj class], sel) != NULL;
}

static id callSel(id obj, SEL sel) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try { return ((id (*)(id, SEL))objc_msgSend)(obj, sel); }
	@catch (__unused id e) { return nil; }
}

static id callSelArg(id obj, SEL sel, id arg) {
	if (!obj || !sel || ![obj respondsToSelector:sel]) return nil;

	@try { return ((id (*)(id, SEL, id))objc_msgSend)(obj, sel, arg); }
	@catch (__unused id e) { return nil; }
}

static UIViewController *findMessageListVC(UIViewController *root) {
	if (!root) return nil;

	Class cls = messageListClass();
	if (cls && [root isKindOfClass:cls] && root.viewIfLoaded.window) return root;

	for (UIViewController *child in root.childViewControllers) {
		UIViewController *found = findMessageListVC(child);
		if (found) return found;
	}

	return findMessageListVC(root.presentedViewController);
}

// The outgoing thread's list lingers in the hierarchy, so only an on-screen one counts.
static UIViewController *visibleMessageListVC(void) {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) continue;

		for (UIWindow *window in ((UIWindowScene *)scene).windows) {
			UIViewController *found = findMessageListVC(window.rootViewController);
			if (found) return found;
		}
	}
	return nil;
}

static void collectIvarObjects(id obj, NSMutableArray *out) {
	if (!obj) return;

	for (Class c = [obj class]; c && c != NSObject.class; c = class_getSuperclass(c)) {
		unsigned int n = 0;
		Ivar *ivars = class_copyIvarList(c, &n);
		if (!ivars) continue;

		for (unsigned int i = 0; i < n; i++) {
			const char *type = ivar_getTypeEncoding(ivars[i]);
			if (!type || type[0] != '@') continue;

			id value = nil;
			@try { value = object_getIvar(obj, ivars[i]); } @catch (__unused id e) {}
			if (value) [out addObject:value];
		}

		free(ivars);
	}
}

static BOOL sIslandAvailable;
static NSUInteger sLastModelCount;
static NSUInteger sStalledCycles;
static NSUInteger sModelsAtLastRequest;
static NSDate *sLastPageRequest;

static NSArray *loadedViewModels(id dataSource);

// An ivar walk can land on a same-shaped object that holds nothing.
static id findMessageListDataSource(UIViewController *list) {
	id live = rygCurrentMessageListDataSource();
	if (reallyImplements(live, resolveSelector())) return live;

	NSMutableArray *frontier = [NSMutableArray array];
	for (UIViewController *vc = list; vc; vc = vc.parentViewController) [frontier addObject:vc];

	id fallback = nil;

	for (NSUInteger depth = 0; depth < 4 && frontier.count; depth++) {
		NSMutableArray *next = [NSMutableArray array];

		for (id candidate in frontier) {
			if (reallyImplements(candidate, resolveSelector())) {
				if (loadedViewModels(candidate).count) return candidate;
				if (!fallback) fallback = candidate;
			}
			collectIvarObjects(candidate, next);
		}

		frontier = next;
	}

	return fallback;
}

static id resolveViewModel(id dataSource, UIViewController *list, NSString *messageId) {
	id viewModel = callSelArg(dataSource, resolveSelector(), messageId);
	if (viewModel) return viewModel;

	Class keyCls = NSClassFromString(@"IGDirectMessageKey");
	SEL initSel = NSSelectorFromString(@"initWithServerId:");
	if (!keyCls || ![keyCls instancesRespondToSelector:initSel]) return nil;

	id querier = callSel(list, NSSelectorFromString(@"messageViewModelQuerier"));

	@try {
		id key = ((id (*)(id, SEL, id))objc_msgSend)([keyCls alloc], initSel, messageId);
		return key ? callSelArg(querier, NSSelectorFromString(@"messageViewModelForMessageKey:"), key) : nil;
	} @catch (__unused id e) {
		return nil;
	}
}

static UIScrollView *listScrollView(UIView *root) {
	if ([root isKindOfClass:UICollectionView.class]) return (UICollectionView *)root;

	for (UIView *sub in root.subviews) {
		UIScrollView *found = listScrollView(sub);
		if (found) return found;
	}
	return nil;
}

static NSDate *viewModelDate(id viewModel) {
	id metadata = callSel(viewModel, NSSelectorFromString(@"messageMetadata"));
	id date = callSel(metadata, NSSelectorFromString(@"sentDate"));
	return [date isKindOfClass:NSDate.class] ? date : nil;
}

static BOOL hasPreviousMessages(id dataSource) {
	SEL sel = NSSelectorFromString(@"hasPreviousMessages");
	if (!reallyImplements(dataSource, sel)) return YES;

	@try { return ((BOOL (*)(id, SEL))objc_msgSend)(dataSource, sel); }
	@catch (__unused id e) { return YES; }
}

static NSArray *loadedViewModels(id dataSource) {
	id models = callSel(dataSource, NSSelectorFromString(@"messageViewModels"));
	return [models isKindOfClass:NSArray.class] ? models : nil;
}

// The island is the page Instagram loads around an anchor message. Announcers
// implement the same selectors, so match on identity.
static BOOL isAnnouncerLike(id obj) {
	NSString *name = NSStringFromClass([obj class]);
	return [name containsString:@"Announcer"] || [name containsString:@"Listener"] || [name containsString:@"Proxy"];
}

static id findPaginationHandler(id dataSource, UIViewController *list) {
	SEL island = NSSelectorFromString(@"loadMessageIslandForAnchorMessageId:");
	Class known = NSClassFromString(@"IGDirectMDCoreThreadPaginationHandler");

	id tracked = rygCurrentThreadPaginationHandler();
	if (reallyImplements(tracked, island) && !isAnnouncerLike(tracked)) return tracked;

	NSMutableArray *frontier = [NSMutableArray array];
	if (dataSource) [frontier addObject:dataSource];
	for (UIViewController *vc = list; vc; vc = vc.parentViewController) [frontier addObject:vc];

	NSMutableArray *seen = [NSMutableArray array];
	id loose = nil;

	for (NSUInteger depth = 0; depth < 5 && frontier.count; depth++) {
		NSMutableArray *next = [NSMutableArray array];

		for (id candidate in frontier) {
			if (known && [candidate isKindOfClass:known]) return candidate;

			if (!loose && reallyImplements(candidate, island) && !isAnnouncerLike(candidate)) loose = candidate;

			BOOL alreadySeen = NO;
			for (id other in seen) { if (other == candidate) { alreadySeen = YES; break; } }
			if (alreadySeen) continue;

			[seen addObject:candidate];
			if (seen.count > 400) break;
			collectIvarObjects(candidate, next);
		}

		frontier = next;
	}

	return loose;
}

// The list controller never exposed a scroll selector to ObjC, so drive the
// IGListKit adapter that owns the section the view model lives in.
static id listAdapter(UIViewController *list) {
	Class cls = NSClassFromString(@"IGListAdapter");
	if (!cls) return nil;

	NSMutableArray *frontier = list ? [NSMutableArray arrayWithObject:list] : [NSMutableArray array];

	for (NSUInteger depth = 0; depth < 4 && frontier.count; depth++) {
		NSMutableArray *next = [NSMutableArray array];

		for (id candidate in frontier) {
			if ([candidate isKindOfClass:cls]) return candidate;
			collectIvarObjects(candidate, next);
		}

		frontier = next;
	}

	return nil;
}

static id tailLoadLogger(UIViewController *list) {
	Class cls = NSClassFromString(@"IGPerformanceTailLoadLogger");
	if (!cls) return nil;

	NSMutableArray *frontier = list ? [NSMutableArray arrayWithObject:list] : [NSMutableArray array];

	for (NSUInteger depth = 0; depth < 3 && frontier.count; depth++) {
		NSMutableArray *next = [NSMutableArray array];

		for (id candidate in frontier) {
			if ([candidate isKindOfClass:cls]) return candidate;
			collectIvarObjects(candidate, next);
		}

		frontier = next;
	}

	return nil;
}

static void setLoadingFlag(id dataSource, BOOL loading) {
	SEL sel = NSSelectorFromString(@"setIsLoadingThreadItemToScrollTo:");
	if (![dataSource respondsToSelector:sel]) return;

	@try { ((void (*)(id, SEL, BOOL))objc_msgSend)(dataSource, sel, loading); }
	@catch (__unused id e) {}
}

+ (BOOL)available {
	Class cls = messageListClass();
	return cls != nil;
}

+ (void)openThreadId:(NSString *)threadId messageId:(NSString *)messageId sentAt:(NSDate *)sentAt {
	if (!threadId.length) return;

	// Reaction rows carry a composite id; the chat only knows the message part.
	NSRange suffix = [messageId rangeOfString:@":rx:"];
	if (suffix.location != NSNotFound) messageId = [messageId substringToIndex:suffix.location];

	NSString *encoded = [threadId stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"instagram://direct-thread?thread_id=%@", encoded]];
	if (!url) return;

	[UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
	if (!messageId.length) return;

	sCancelled = NO;
	sIslandAvailable = YES;
	sLastModelCount = 0;
	sStalledCycles = 0;
	sModelsAtLastRequest = 0;
	sLastPageRequest = nil;

	__block RYGNotificationHandle *progress = nil;
	progress = RYGNotifyLoading(RYG_NOTIF_GENERIC, RYGLocalized(@"Loading…"), ^{
		sCancelled = YES;
		[progress dismiss];
	});
	[self findMessageId:messageId sentAt:sentAt attempt:0 requestedSurrounding:NO progress:progress];
}

// Thread, list and the page holding the message all arrive separately, so wait on the message.
+ (void)findMessageId:(NSString *)messageId
			   sentAt:(NSDate *)sentAt
			  attempt:(NSUInteger)attempt
 requestedSurrounding:(BOOL)requestedSurrounding
			 progress:(RYGNotificationHandle *)progress {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (sCancelled) {
			[progress dismiss];
			return;
		}

		UIViewController *list = visibleMessageListVC();
		id dataSource = list ? findMessageListDataSource(list) : nil;
		id viewModel = list ? resolveViewModel(dataSource, list, messageId) : nil;

		if (viewModel) {
			setLoadingFlag(dataSource, NO);
			[progress dismiss];
			[self scrollList:list toViewModel:viewModel messageId:messageId attempt:attempt];
			return;
		}

		NSArray *models = loadedViewModels(dataSource);
		NSDate *oldest = models.count ? viewModelDate(models.firstObject) : nil;
		NSDate *newest = models.count ? viewModelDate(models.lastObject) : nil;
		if (oldest && newest && [oldest compare:newest] == NSOrderedDescending) {
			NSDate *swap = oldest; oldest = newest; newest = swap;
		}

		BOOL morePages = hasPreviousMessages(dataSource);

		if (models.count > sLastModelCount) { sLastModelCount = models.count; sStalledCycles = 0; }
		else if (attempt >= 4) sStalledCycles++;

		BOOL exhausted = models.count && (!morePages || sStalledCycles >= 40);

		// Paged past the target without finding it, so land on the nearest survivor.
		BOOL pagedPast = sentAt && oldest && [oldest compare:sentAt] != NSOrderedDescending;
		if (pagedPast || exhausted || attempt + 1 >= kMaxAttempts) {
			setLoadingFlag(dataSource, NO);

			id nearest = nil;
			NSTimeInterval bestGap = 0;
			for (id candidate in models) {
				NSDate *date = viewModelDate(candidate);
				if (!date || !sentAt) continue;

				NSTimeInterval gap = fabs([date timeIntervalSinceDate:sentAt]);
				if (!nearest || gap < bestGap) { nearest = candidate; bestGap = gap; }
			}

			if (nearest) {
				[progress dismiss];
				[self scrollList:list toViewModel:nearest messageId:nil attempt:attempt];
				RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"Jumped to around that time"), nil);
			} else {
				[progress error:RYGLocalized(@"Couldn't find that message in the chat")];
			}
			return;
		}

		BOOL asked = requestedSurrounding;

		if (dataSource && !asked && attempt >= 1) {
			id handler = findPaginationHandler(dataSource, list);
			SEL island = NSSelectorFromString(@"loadMessageIslandForAnchorMessageId:");

			sIslandAvailable = handler != nil;

			if (handler) {
				setLoadingFlag(dataSource, YES);
				@try { ((void (*)(id, SEL, id))objc_msgSend)(handler, island, messageId); }
				@catch (__unused id e) {}
				asked = YES;
			} else {
				SEL surrounding = NSSelectorFromString(@"loadSurroundingMessagesForMessageId:timestamp:");
				if (reallyImplements(dataSource, surrounding)) {
					@try { ((void (*)(id, SEL, id, id))objc_msgSend)(dataSource, surrounding, messageId, sentAt); }
					@catch (__unused id e) {}
					asked = YES;
				}
			}
		}

		// One page in flight at a time; overlapping calls get dropped and stick Instagram's spinner.
		NSUInteger pagingFrom = sIslandAvailable ? kPagingStartsAt : 4;
		BOOL pageArrived = models.count > sModelsAtLastRequest;
		BOOL requestTimedOut = sLastPageRequest && -[sLastPageRequest timeIntervalSinceNow] > 4.0;

		if (dataSource && attempt >= pagingFrom && morePages && (!sLastPageRequest || pageArrived || requestTimedOut)) {
			SEL previous = NSSelectorFromString(@"loadPreviousMessagesWithTailLoadLogger:");
			if (reallyImplements(dataSource, previous)) {
				sModelsAtLastRequest = models.count;
				sLastPageRequest = NSDate.date;

				id logger = tailLoadLogger(list);

				@try { ((void (*)(id, SEL, id))objc_msgSend)(dataSource, previous, logger); }
				@catch (__unused id e) {}
			}
		}

		[self findMessageId:messageId sentAt:sentAt attempt:attempt + 1 requestedSurrounding:asked progress:progress];
	});
}

+ (void)scrollList:(UIViewController *)list toViewModel:(id)viewModel messageId:(NSString *)messageId attempt:(NSUInteger)attempt {

	[self performScrollOnList:list toViewModel:viewModel messageId:messageId animated:YES];
	[self settleList:list toViewModel:viewModel messageId:messageId];
}

// Instagram's own entry points do the bookkeeping its list expects.
+ (void)performScrollOnList:(UIViewController *)list
				toViewModel:(id)viewModel
				  messageId:(NSString *)messageId
				   animated:(BOOL)animated {
	@try {
		SEL byId = NSSelectorFromString(@"messageListScrollToMessageWithIdentifier:animated:");
		if (messageId.length && [list respondsToSelector:byId]) {
			((void (*)(id, SEL, id, BOOL))objc_msgSend)(list, byId, messageId, animated);
			return;
		}

		SEL scrollToVM = NSSelectorFromString(@"scrollListToViewModel:scrollPosition:additionalOffset:animated:");
		if (viewModel && [list respondsToSelector:scrollToVM]) {
			((void (*)(id, SEL, id, unsigned long long, double, BOOL))objc_msgSend)
				(list, scrollToVM, viewModel, UICollectionViewScrollPositionCenteredVertically, 0.0, animated);
			return;
		}

		SEL scrollToObj = NSSelectorFromString(@"scrollToObject:supplementaryKinds:scrollDirection:scrollPosition:additionalOffset:animated:");
		id adapter = listAdapter(list);
		if (viewModel && [adapter respondsToSelector:scrollToObj]) {
			((void (*)(id, SEL, id, NSArray *, NSInteger, NSUInteger, CGFloat, BOOL))objc_msgSend)
				(adapter, scrollToObj, viewModel, nil, UICollectionViewScrollDirectionVertical,
				 UICollectionViewScrollPositionCenteredVertically, 0.0, animated);
			return;
		}
	} @catch (__unused id e) {}
}

// A jumped-to page can sit un-rendered until the list is touched, and drifts as it relayouts.
+ (void)settleList:(UIViewController *)list toViewModel:(id)viewModel messageId:(NSString *)messageId {
	UIScrollView *scroll = listScrollView(list.viewIfLoaded);
	if (!scroll) return;

	for (NSNumber *delay in @[@0.35, @0.9, @1.6]) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (sCancelled) return;

			if ([scroll isKindOfClass:UICollectionView.class]) {
				[((UICollectionView *)scroll).collectionViewLayout invalidateLayout];
			}
			[scroll layoutIfNeeded];

			[self performScrollOnList:list toViewModel:viewModel messageId:messageId animated:NO];

			// Cells only come back once the offset actually moves.
			CGPoint offset = scroll.contentOffset;
			[scroll setContentOffset:CGPointMake(offset.x, offset.y + 1.0) animated:NO];
			[scroll setContentOffset:offset animated:NO];
		});
	}
}

@end
