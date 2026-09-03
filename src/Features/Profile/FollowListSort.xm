#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGProfileHelpers.h"
#import "../../RYGChrome.h"
#import "../../UI/RYGPopupChrome.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Client-side filter / sort / search for followers / following lists.
// friendship_status: following = I follow them, followedBy = they follow me.

typedef NS_OPTIONS(NSUInteger, RYGFollowFilter) {
	RYGFilterMutual    = 1 << 0,
	RYGFilterIFollow   = 1 << 1,
	RYGFilterFollowsMe = 1 << 2,
	RYGFilterVerified  = 1 << 3,
	RYGFilterNotFollowsMe = 1 << 4,
};

typedef NS_ENUM(NSInteger, RYGFollowSortKey) {
	RYGSortDefault = 0,
	RYGSortName,
	RYGSortVerified,
	RYGSortMutual,
	RYGSortFollowsMe,
	RYGSortIFollow,
};

static const void *kFilterKey  = &kFilterKey;
static const void *kSortKey    = &kSortKey;
static const void *kReverseKey = &kReverseKey;
static const void *kButtonKey  = &kButtonKey;
static const void *kFloatingKey = &kFloatingKey;
static const void *kHasSearchBarKey = &kHasSearchBarKey;
static const void *kQueryKey   = &kQueryKey;

@interface IGFollowListViewController (RYGSort)
- (void)ryg_presentSheet;
- (void)ryg_installFloating;
- (void)ryg_changed;
- (void)ryg_reRender;
- (UIScrollView *)ryg_collectionView;
- (void)ryg_jumpToTop;
- (void)ryg_jumpToBottom;
- (void)ryg_triggerPaginate;
- (void)ryg_loadAll;
- (void)ryg_loadAllStep;
- (NSUInteger)ryg_loadedCount;
- (void)_maybePaginateList;
@end

static const void *kLoadingKey = &kLoadingKey;
static const void *kLoadStateKey = &kLoadStateKey;
static const void *kRelRetryKey = &kRelRetryKey;
static const void *kInRetryKey = &kInRetryKey;

#pragma mark - data

static id rygFieldCache(id obj, NSString *key) {
	if (!obj) return nil;
	Ivar iv = NULL;
	for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c))
		iv = class_getInstanceVariable(c, "_fieldCache");
	if (!iv) return nil;
	id fc = object_getIvar(obj, iv);
	if (![fc isKindOfClass:NSDictionary.class]) return nil;
	id v = fc[key];
	return (v == [NSNull null]) ? nil : v;
}

static BOOL rygIvarBOOL(id obj, const char *name) {
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return NO;
	return *(BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static id rygIvarObj(id obj, const char *name) {
	Ivar iv = class_getInstanceVariable([obj class], name);
	return iv ? object_getIvar(obj, iv) : nil;
}

typedef struct { BOOL following; BOOL followedBy; BOOL verified; BOOL relKnown; } RYGUserAttr;

static RYGUserAttr rygAttrForConfig(id cfg, NSString **outName, NSString **outFull) {
	RYGUserAttr a = (RYGUserAttr){NO, NO, NO, NO};
	id user = nil;
	@try { user = [cfg valueForKey:@"user"]; } @catch (__unused id e) {}
	if (!user) { if (outName) *outName = @""; if (outFull) *outFull = @""; return a; }

	BOOL fo = NO, fb = NO;
	if ([RYGProfileHelpers relationForUser:user following:&fo followedBy:&fb]) {
		a.relKnown = YES; a.following = fo; a.followedBy = fb;
	}

	id ver = rygFieldCache(user, @"is_verified");
	if (ver == nil || ver == (id)[NSNull null]) { @try { ver = [user valueForKey:@"isVerified"]; } @catch (__unused id e) {} }
	a.verified = [ver respondsToSelector:@selector(boolValue)] ? [ver boolValue] : NO;

	if (outName) {
		id n = rygFieldCache(user, @"username");
		if (![n isKindOfClass:NSString.class]) { @try { n = [user valueForKey:@"username"]; } @catch (__unused id e) {} }
		*outName = [n isKindOfClass:NSString.class] ? n : @"";
	}
	if (outFull) {
		id f = rygFieldCache(user, @"full_name");
		if (![f isKindOfClass:NSString.class]) { @try { f = [user valueForKey:@"fullName"]; } @catch (__unused id e) {} }
		*outFull = [f isKindOfClass:NSString.class] ? f : @"";
	}
	return a;
}

#pragma mark - per-view state (resets when the VC is dismissed)

static RYGFollowFilter rygFilter(id vc) { return (RYGFollowFilter)[objc_getAssociatedObject(vc, kFilterKey) unsignedIntegerValue]; }
static RYGFollowSortKey rygSort(id vc)  { return (RYGFollowSortKey)[objc_getAssociatedObject(vc, kSortKey) integerValue]; }
static BOOL rygReverse(id vc)           { return [objc_getAssociatedObject(vc, kReverseKey) boolValue]; }
static NSString *rygQuery(id vc)        { NSString *q = objc_getAssociatedObject(vc, kQueryKey); return [q isKindOfClass:NSString.class] ? q : @""; }
static BOOL rygActive(id vc)            { return rygFilter(vc) != 0 || rygSort(vc) != RYGSortDefault || rygReverse(vc) || rygQuery(vc).length > 0; }

static const RYGFollowFilter kRYGRelFilters = RYGFilterMutual | RYGFilterIFollow | RYGFilterFollowsMe | RYGFilterNotFollowsMe;

static BOOL rygNeedsRel(RYGFollowFilter f, RYGFollowSortKey s) {
	if (f & kRYGRelFilters) return YES;
	return s == RYGSortMutual || s == RYGSortFollowsMe || s == RYGSortIFollow;
}

static BOOL rygPassesFilter(RYGFollowFilter f, RYGUserAttr a) {
	if ((f & kRYGRelFilters) && !a.relKnown) return YES;
	if ((f & RYGFilterMutual)    && !(a.following && a.followedBy)) return NO;
	if ((f & RYGFilterIFollow)   && !a.following)                  return NO;
	if ((f & RYGFilterFollowsMe) && !a.followedBy)                 return NO;
	if ((f & RYGFilterNotFollowsMe) && a.followedBy)              return NO;
	if ((f & RYGFilterVerified)  && !a.verified)                   return NO;
	return YES;
}

static const void *kSheetKey = &kSheetKey;

static NSArray<NSDictionary *> *rygFilterRows(void) {
	return @[
		@{@"t": RYGLocalized(@"Mutuals"),         @"i": @"person.2.fill",          @"v": @(RYGFilterMutual)},
		@{@"t": RYGLocalized(@"People I follow"), @"i": @"person.fill.checkmark",  @"v": @(RYGFilterIFollow)},
		@{@"t": RYGLocalized(@"Follows me"),      @"i": @"arrow.left.circle.fill", @"v": @(RYGFilterFollowsMe)},
		@{@"t": RYGLocalized(@"Doesn't follow you"), @"i": @"person.crop.circle.badge.xmark", @"v": @(RYGFilterNotFollowsMe)},
		@{@"t": RYGLocalized(@"Verified"),        @"i": @"checkmark.seal.fill",    @"v": @(RYGFilterVerified)},
	];
}
static NSArray<NSDictionary *> *rygSortRows(void) {
	return @[
		@{@"t": RYGLocalized(@"Default"),            @"i": @"line.3.horizontal",      @"v": @(RYGSortDefault)},
		@{@"t": RYGLocalized(@"Name (A–Z)"),         @"i": @"textformat",             @"v": @(RYGSortName)},
		@{@"t": RYGLocalized(@"Verified first"),     @"i": @"checkmark.seal.fill",    @"v": @(RYGSortVerified)},
		@{@"t": RYGLocalized(@"Mutuals first"),      @"i": @"person.2.fill",          @"v": @(RYGSortMutual)},
		@{@"t": RYGLocalized(@"Follows me first"),   @"i": @"arrow.left.circle.fill", @"v": @(RYGSortFollowsMe)},
		@{@"t": RYGLocalized(@"People I follow first"), @"i": @"person.fill.checkmark", @"v": @(RYGSortIFollow)},
	];
}

#pragma mark - options sheet

@interface RYGFollowSortSheet : UITableViewController <UISearchBarDelegate>
@property (nonatomic, weak) IGFollowListViewController *listVC;
@property (nonatomic, strong) UISearchBar *searchBar;
- (void)refresh;
@end

@implementation RYGFollowSortSheet

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = RYGLocalized(@"Filter & sort");
	self.view.backgroundColor = [RYGPopupChrome backgroundColor];
	self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(ryg_done)];

	// No native (server) search bar on this list — provide our own client search
	// here as the fallback. When IG's native bar exists we omit it (it covers search).
	if (![objc_getAssociatedObject(self.listVC, kHasSearchBarKey) boolValue]) {
		UISearchBar *sb = [[UISearchBar alloc] init];
		sb.placeholder = RYGLocalized(@"Search by name or username");
		sb.delegate = self;
		sb.searchBarStyle = UISearchBarStyleMinimal;
		sb.autocapitalizationType = UITextAutocapitalizationTypeNone;
		sb.autocorrectionType = UITextAutocorrectionTypeNo;
		sb.text = rygQuery(self.listVC);
		[sb sizeToFit];
		self.tableView.tableHeaderView = sb;
		self.searchBar = sb;
	}
}

- (void)ryg_done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text {
	IGFollowListViewController *vc = self.listVC;
	if (!vc) return;
	objc_setAssociatedObject(vc, kQueryKey, text ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[vc ryg_changed];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)sb { [sb setShowsCancelButton:YES animated:YES]; [self ryg_setSearching:YES]; }
- (void)searchBarTextDidEndEditing:(UISearchBar *)sb   { [sb setShowsCancelButton:NO  animated:YES]; [self ryg_setSearching:NO];  }
- (void)searchBarCancelButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

// Short fixed detent while typing keeps the list visible above the keyboard
// (a lone detent can't be keyboard-expanded like medium/large).
- (void)ryg_setSearching:(BOOL)searching {
	if (@available(iOS 16.0, *)) {
		UISheetPresentationController *spc = self.navigationController.sheetPresentationController;
		[spc animateChanges:^{
			if (searching) {
				UISheetPresentationControllerDetent *small = [UISheetPresentationControllerDetent
					customDetentWithIdentifier:@"rygSearch"
					resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) { return 240.0; }];
				spc.detents = @[small];
				spc.largestUndimmedDetentIdentifier = @"rygSearch";
			} else {
				spc.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
				spc.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
			}
		}];
	}
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	if (self.listVC)
		objc_setAssociatedObject(self.listVC, kSheetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	switch (s) {
		case 0: return rygFilterRows().count;
		case 1: return rygSortRows().count + 1; // +1 reverse row
		case 2: return 3;
		default: return 1;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	switch (s) {
		case 0: return RYGLocalized(@"Show only");
		case 1: return RYGLocalized(@"Sort by");
		case 2: return RYGLocalized(@"List");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return RYGLocalized(@"Hides everyone who doesn't match all picked filters.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.tintColor = UIColor.systemBlueColor;
	IGFollowListViewController *vc = self.listVC;

	if (ip.section == 0) {
		NSDictionary *r = rygFilterRows()[ip.row];
		cell.textLabel.text = RYGLocalized(r[@"t"]);
		cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
		cell.accessoryType = (rygFilter(vc) & [r[@"v"] unsignedIntegerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)rygSortRows().count) {
			NSDictionary *r = rygSortRows()[ip.row];
			cell.textLabel.text = RYGLocalized(r[@"t"]);
			cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
			cell.accessoryType = (rygSort(vc) == (RYGFollowSortKey)[r[@"v"] integerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		} else {
			cell.textLabel.text = RYGLocalized(@"Reverse order");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.arrow.down"];
			cell.accessoryType = rygReverse(vc) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		}
	} else if (ip.section == 2) {
		BOOL loading = [objc_getAssociatedObject(vc, kLoadingKey) boolValue];
		if (ip.row == 0) {
			cell.textLabel.text = RYGLocalized(@"Jump to top");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.to.line"];
		} else if (ip.row == 1) {
			cell.textLabel.text = RYGLocalized(@"Jump to bottom");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.to.line"];
		} else {
			NSUInteger loaded = [vc ryg_loadedCount];
			BOOL end = rygIvarBOOL(vc, "_reachedUserListEnd");
			UITableViewCell *sub = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
			sub.tintColor = UIColor.systemBlueColor;
			sub.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
			sub.textLabel.text = loading ? RYGLocalized(@"Loading") : RYGLocalized(@"Load more");
			sub.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			sub.detailTextLabel.text = end
				? [NSString stringWithFormat:RYGLocalized(@"%lu loaded · all loaded"), (unsigned long)loaded]
				: [NSString stringWithFormat:RYGLocalized(@"%lu loaded"), (unsigned long)loaded];
			if (loading) {
				UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
				[spin startAnimating];
				sub.accessoryView = spin;
			} else if (end) {
				sub.textLabel.textColor = UIColor.tertiaryLabelColor;
				sub.selectionStyle = UITableViewCellSelectionStyleNone;
			}
			return sub;
		}
	} else {
		cell.textLabel.text = RYGLocalized(@"Reset");
		cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
		BOOL active = rygActive(vc);
		cell.textLabel.textColor = active ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
		cell.tintColor = UIColor.systemRedColor;
		cell.selectionStyle = active ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	}
	return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:YES];
	IGFollowListViewController *vc = self.listVC;
	if (!vc) return;

	if (ip.section == 0) {
		RYGFollowFilter bit = (RYGFollowFilter)[rygFilterRows()[ip.row][@"v"] unsignedIntegerValue];
		objc_setAssociatedObject(vc, kFilterKey, @(rygFilter(vc) ^ bit), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[vc ryg_changed];
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)rygSortRows().count) {
			objc_setAssociatedObject(vc, kSortKey, rygSortRows()[ip.row][@"v"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		} else {
			objc_setAssociatedObject(vc, kReverseKey, @(!rygReverse(vc)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		[vc ryg_changed];
	} else if (ip.section == 2) {
		if (ip.row == 0) [vc ryg_jumpToTop];
		else if (ip.row == 1) [vc ryg_jumpToBottom];
		else [vc ryg_loadAll];
	} else {
		if (!rygActive(vc)) return;
		objc_setAssociatedObject(vc, kFilterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(vc, kSortKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(vc, kReverseKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(vc, kQueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		self.searchBar.text = @"";
		[vc ryg_changed];
	}
	[self refresh];
}

@end

#pragma mark - hook

%group FollowListSort

%hook IGFollowListViewController

- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *objs = %orig;
	if (!rygActive(self) || ![objs isKindOfClass:NSArray.class] || objs.count == 0) return objs;

	RYGFollowFilter filter = rygFilter(self);
	RYGFollowSortKey sortKey = rygSort(self);
	BOOL reverse = rygReverse(self);

	NSString *query = rygQuery(self);
	BOOL needsRel = rygNeedsRel(filter, sortKey);
	BOOL sawUnknown = NO;
	NSMutableArray *deco = [NSMutableArray array];
	for (id o in objs) {
		if (![o isKindOfClass:%c(IGUserListItemConfiguration)]) continue;
		NSString *name = nil, *full = nil;
		RYGUserAttr a = rygAttrForConfig(o, &name, &full);
		if (needsRel && !a.relKnown) sawUnknown = YES;
		if (!rygPassesFilter(filter, a)) continue;
		if (query.length &&
			[name rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound &&
			[full rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
		[deco addObject:@{ @"cfg": o, @"i": @(deco.count), @"name": name ?: @"",
			@"mutual": @(a.following && a.followedBy), @"fme": @(a.followedBy),
			@"ifo": @(a.following), @"ver": @(a.verified) }];
	}

	if (sawUnknown) {
		NSInteger tries = [objc_getAssociatedObject(self, kRelRetryKey) integerValue];
		if (tries < 6) {
			objc_setAssociatedObject(self, kRelRetryKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(ryg_reRender) object:nil];
			[self performSelector:@selector(ryg_reRender) withObject:nil afterDelay:0.45];
		}
	} else {
		objc_setAssociatedObject(self, kRelRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	NSString *boolKey = nil;
	switch (sortKey) {
		case RYGSortVerified:  boolKey = @"ver";    break;
		case RYGSortMutual:    boolKey = @"mutual"; break;
		case RYGSortFollowsMe: boolKey = @"fme";    break;
		case RYGSortIFollow:   boolKey = @"ifo";    break;
		default: break;
	}

	if (sortKey != RYGSortDefault) {
		[deco sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
			NSComparisonResult c = NSOrderedSame;
			if (sortKey == RYGSortName) {
				c = [x[@"name"] caseInsensitiveCompare:y[@"name"]];
			} else {
				BOOL bx = [x[boolKey] boolValue], by = [y[boolKey] boolValue];
				c = (bx == by) ? NSOrderedSame : (bx ? NSOrderedAscending : NSOrderedDescending);
			}
			if (c == NSOrderedSame) return [x[@"i"] compare:y[@"i"]];
			return reverse ? (NSComparisonResult)(-c) : c;
		}];
	} else if (reverse) {
		deco = [[[deco reverseObjectEnumerator] allObjects] mutableCopy];
	}

	NSMutableArray *processed = [NSMutableArray arrayWithCapacity:deco.count];
	for (NSDictionary *d in deco) [processed addObject:d[@"cfg"]];

	NSMutableArray *result = [NSMutableArray arrayWithCapacity:objs.count];
	BOOL injected = NO;
	for (id o in objs) {
		if ([o isKindOfClass:%c(IGUserListItemConfiguration)]) {
			if (!injected) { [result addObjectsFromArray:processed]; injected = YES; }
		} else {
			[result addObject:o];
		}
	}
	return result;
}

%new
- (void)ryg_reRender {
	objc_setAssociatedObject(self, kInRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self ryg_changed];
	objc_setAssociatedObject(self, kInRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (void)ryg_changed {
	if (![objc_getAssociatedObject(self, kInRetryKey) boolValue])
		objc_setAssociatedObject(self, kRelRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	RYGChromeButton *inl = objc_getAssociatedObject(self, kButtonKey);
	if ([inl isKindOfClass:RYGChromeButton.class])
		inl.iconTint = rygActive(self) ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
	RYGChromeButton *fl = objc_getAssociatedObject(self, kFloatingKey);
	if ([fl isKindOfClass:RYGChromeButton.class])
		fl.iconTint = rygActive(self) ? UIColor.systemBlueColor : UIColor.labelColor;

	RYGFollowSortSheet *sheet = objc_getAssociatedObject(self, kSheetKey);
	if ([sheet isKindOfClass:RYGFollowSortSheet.class]) [sheet refresh];

	Ivar iv = class_getInstanceVariable([self class], "_listAdapter");
	id adapter = iv ? object_getIvar(self, iv) : nil;
	if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)])
		((void (*)(id, SEL, BOOL, id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), YES, nil);
}

%new
- (void)ryg_presentSheet {
	if (objc_getAssociatedObject(self, kSheetKey)) return;
	RYGFollowSortSheet *sheet = [RYGFollowSortSheet new];
	sheet.listVC = self;
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
	nav.modalPresentationStyle = UIModalPresentationPageSheet;
	if (@available(iOS 15.0, *)) {
		UISheetPresentationController *spc = nav.sheetPresentationController;
		spc.detents = @[UISheetPresentationControllerDetent.mediumDetent];
		spc.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
		spc.prefersScrollingExpandsWhenScrolledToEdge = NO;
		spc.prefersGrabberVisible = YES;
		spc.preferredCornerRadius = 22;
	}
	objc_setAssociatedObject(self, kSheetKey, sheet, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self presentViewController:nav animated:YES completion:nil];
}

%new
- (UIScrollView *)ryg_collectionView {
	id cv = rygIvarObj(self, "_collectionView");
	return [cv isKindOfClass:UIScrollView.class] ? cv : nil;
}

%new
- (void)ryg_jumpToTop {
	UIScrollView *cv = [self ryg_collectionView];
	[cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:YES];
}

%new
- (void)ryg_triggerPaginate {
	// manualCheck:YES forces a page fetch without a real drag — pagination is
	// otherwise only scroll-gesture driven.
	SEL near = @selector(scrollViewWillScrollNearBottom:triggeredByManualCheck:);
	if ([self respondsToSelector:near]) {
		((void (*)(id, SEL, id, BOOL))objc_msgSend)(self, near, [self ryg_collectionView], YES);
		return;
	}
	SEL s = @selector(_maybePaginateList);
	if ([self respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(self, s);
}

%new
- (void)ryg_jumpToBottom {
	UIScrollView *cv = [self ryg_collectionView];
	if (!cv) return;
	CGFloat y = cv.contentSize.height - cv.bounds.size.height + cv.adjustedContentInset.bottom;
	[cv setContentOffset:CGPointMake(0, MAX(-cv.adjustedContentInset.top, y)) animated:YES];
	[self ryg_triggerPaginate];
}

// Page in a bounded batch via IG's near-bottom loader; press again to continue.
static const NSUInteger kLoadBatch = 200;

%new
- (void)ryg_loadAll {
	if ([objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
	if (rygIvarBOOL(self, "_reachedUserListEnd")) {
		RYGNotifyInfo(RYG_NOTIF_GENERIC, RYGLocalized(@"List fully loaded"), RYGLocalized(@"Everyone is already loaded."));
		return;
	}
	NSUInteger start = [self ryg_loadedCount];
	objc_setAssociatedObject(self, kLoadingKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, kLoadStateKey,
		[@{@"count": @(start), @"target": @(start + kLoadBatch), @"stalls": @0, @"iter": @0} mutableCopy],
		OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self ryg_changed];
	[self performSelector:@selector(ryg_loadAllStep) withObject:nil afterDelay:0.3];
}

%new
- (NSUInteger)ryg_loadedCount {
	id list = rygIvarObj(self, "_userList");
	if ([list respondsToSelector:@selector(count)]) return [(NSArray *)list count];
	for (NSString *k : @[@"users", @"allUsers", @"userList"]) {
		@try {
			id u = [list valueForKey:k];
			if ([u respondsToSelector:@selector(count)]) return [(NSArray *)u count];
		} @catch (__unused id e) {}
	}
	return 0;
}

%new
- (void)ryg_loadAllStep {
	if (![objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
	NSMutableDictionary *st = objc_getAssociatedObject(self, kLoadStateKey);
	NSUInteger count = [self ryg_loadedCount];
	BOOL reachedEnd = rygIvarBOOL(self, "_reachedUserListEnd");
	NSUInteger target = [st[@"target"] unsignedIntegerValue];

	NSUInteger lastCount = [st[@"count"] unsignedIntegerValue];
	NSUInteger stalls = (count <= lastCount) ? [st[@"stalls"] unsignedIntegerValue] + 1 : 0;
	NSInteger iter = [st[@"iter"] integerValue];
	st[@"count"] = @(count);
	st[@"stalls"] = @(stalls);

	if (reachedEnd || count >= target || stalls >= 6 || iter >= 60) {
		objc_setAssociatedObject(self, kLoadingKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		RYGNotifySuccess(RYG_NOTIF_GENERIC,
			reachedEnd ? RYGLocalized(@"List fully loaded") : RYGLocalized(@"Loaded more"),
			[NSString stringWithFormat:RYGLocalized(@"%lu accounts"), (unsigned long)count]);
		[self ryg_changed];
		return;
	}
	st[@"iter"] = @(iter + 1);
	if (!rygIvarBOOL(self, "_loading")) [self ryg_triggerPaginate];
	[self performSelector:@selector(ryg_loadAllStep) withObject:nil afterDelay:0.5];
}

- (void)searchBar:(id)bar didChangeSearchText:(NSString *)text {
	%orig;
	UIView *btn = objc_getAssociatedObject(self, kButtonKey);
	btn.hidden = (text.length > 0);
}

// Floating fallback: shown only on lists with no native search bar (small lists /
// accounts that don't get IG's search). The IGSearchBar hook hides it when the
// native bar exists and hosts the inline button instead.
%new
- (void)ryg_installFloating {
	RYGChromeButton *btn = objc_getAssociatedObject(self, kFloatingKey);
	if (!btn) {
		btn = [[RYGChromeButton alloc] initWithSymbol:@"line.3.horizontal.decrease" pointSize:18.0 diameter:46.0];
		btn.translatesAutoresizingMaskIntoConstraints = NO;
		btn.bubbleColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.96];
		btn.iconTint = rygActive(self) ? UIColor.systemBlueColor : UIColor.labelColor;
		btn.layer.shadowColor = UIColor.blackColor.CGColor;
		btn.layer.shadowOpacity = 0.18;
		btn.layer.shadowRadius = 8;
		btn.layer.shadowOffset = CGSizeMake(0, 2);
		[btn addTarget:self action:@selector(ryg_presentSheet) forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:btn];
		[NSLayoutConstraint activateConstraints:@[
			[btn.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
			[btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
			[btn.widthAnchor constraintEqualToConstant:46],
			[btn.heightAnchor constraintEqualToConstant:46],
		]];
		objc_setAssociatedObject(self, kFloatingKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	btn.hidden = [objc_getAssociatedObject(self, kHasSearchBarKey) boolValue];
	[self.view bringSubviewToFront:btn];
}

- (void)viewDidLayoutSubviews {
	%orig;
	if ([RYGUtils getBoolPref:@"ryg_followlist_sort_enabled"]) [self ryg_installFloating];
}

%end

// The follower/following search bar is an IGSearchBar inside an IGSearchBarCell
// (a list cell, not a VC ivar). Attach our filter button to it, scoped to the
// follow list, and inset the text field so it doesn't run under the button.
%hook IGSearchBar

- (void)layoutSubviews {
	%orig;
	if (![RYGUtils getBoolPref:@"ryg_followlist_sort_enabled"]) return;

	IGFollowListViewController *vc = nil;
	UIResponder *r = self;
	for (int i = 0; i < 40 && r; i++, r = r.nextResponder)
		if ([r isKindOfClass:%c(IGFollowListViewController)]) { vc = (IGFollowListViewController *)r; break; }
	if (!vc) return;

	objc_setAssociatedObject(vc, kHasSearchBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	UIView *floating = objc_getAssociatedObject(vc, kFloatingKey);
	floating.hidden = YES;

	RYGChromeButton *btn = objc_getAssociatedObject(vc, kButtonKey);
	if (![btn isKindOfClass:RYGChromeButton.class]) {
		btn = [[RYGChromeButton alloc] initWithSymbol:@"line.3.horizontal.decrease" pointSize:18.0 diameter:34.0];
		btn.bubbleColor = UIColor.clearColor;
		btn.iconTint = rygActive(vc) ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
		[btn addTarget:vc action:@selector(ryg_presentSheet) forControlEvents:UIControlEventTouchUpInside];
		objc_setAssociatedObject(vc, kButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	if (btn.superview != self) [self addSubview:btn];
	self.clipsToBounds = NO;
	CGFloat d = 34;
	UIView *field = self.subviews.firstObject;
	CGFloat cy = (field && field != btn) ? CGRectGetMidY(field.frame) : self.bounds.size.height / 2;
	btn.frame = CGRectMake(self.bounds.size.width - d - 18, cy - d / 2, d, d);
	[self bringSubviewToFront:btn];
}

%end

%end

%ctor {
	if ([RYGUtils getBoolPref:@"ryg_followlist_sort_enabled"]) %init(FollowListSort);
}
