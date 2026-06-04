#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../UI/SCIPopupChrome.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Client-side filter + sort for followers/following lists. The list feeds
// IGUserListItemConfiguration rows (wrapping IGUser) mixed with header/
// suggestion rows we leave in place. friendship_status' following/followedBy
// getters return NSNumber — following = I follow them, followedBy = they follow me.

typedef NS_OPTIONS(NSUInteger, SCIFollowFilter) {
	SCIFilterMutual    = 1 << 0,
	SCIFilterIFollow   = 1 << 1,
	SCIFilterFollowsMe = 1 << 2,
	SCIFilterVerified  = 1 << 3,
};

typedef NS_ENUM(NSInteger, SCIFollowSortKey) {
	SCISortDefault = 0,
	SCISortName,
	SCISortVerified,
	SCISortMutual,
	SCISortFollowsMe,
	SCISortIFollow,
};

static const void *kFilterKey  = &kFilterKey;
static const void *kSortKey    = &kSortKey;
static const void *kReverseKey = &kReverseKey;
static const void *kButtonKey  = &kButtonKey;

@interface IGFollowListViewController (SCISort)
- (void)sci_installSortButton;
- (void)sci_presentSheet;
- (void)sci_changed;
- (UIScrollView *)sci_collectionView;
- (void)sci_jumpToTop;
- (void)sci_jumpToBottom;
- (void)sci_triggerPaginate;
- (void)sci_loadAll;
- (void)sci_loadAllStep;
- (NSUInteger)sci_loadedCount;
- (void)_maybePaginateList;
@end

static const void *kLoadingKey = &kLoadingKey;
static const void *kLoadStateKey = &kLoadStateKey;

#pragma mark - data

static id sciFieldCache(id obj, NSString *key) {
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

static BOOL sciRelFlag(id rel, SEL getter) {
	if (!rel || ![rel respondsToSelector:getter]) return NO;
	id v = ((id (*)(id, SEL))objc_msgSend)(rel, getter);
	return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

static BOOL sciIvarBOOL(id obj, const char *name) {
	Ivar iv = class_getInstanceVariable([obj class], name);
	if (!iv) return NO;
	return *(BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}

static id sciIvarObj(id obj, const char *name) {
	Ivar iv = class_getInstanceVariable([obj class], name);
	return iv ? object_getIvar(obj, iv) : nil;
}

typedef struct { BOOL following; BOOL followedBy; BOOL verified; } SCIUserAttr;

static SCIUserAttr sciAttrForConfig(id cfg, NSString **outName) {
	SCIUserAttr a = (SCIUserAttr){NO, NO, NO};
	id user = nil;
	@try { user = [cfg valueForKey:@"user"]; } @catch (__unused id e) {}
	if (!user) { if (outName) *outName = @""; return a; }

	id rel = sciFieldCache(user, @"friendship_status");
	a.following  = sciRelFlag(rel, @selector(following));
	a.followedBy = sciRelFlag(rel, @selector(followedBy));
	a.verified   = [sciFieldCache(user, @"is_verified") boolValue];

	if (outName) {
		id n = sciFieldCache(user, @"username");
		if (![n isKindOfClass:NSString.class]) { @try { n = [user valueForKey:@"username"]; } @catch (__unused id e) {} }
		*outName = [n isKindOfClass:NSString.class] ? n : @"";
	}
	return a;
}

#pragma mark - per-view state (resets when the VC is dismissed)

static SCIFollowFilter sciFilter(id vc) { return (SCIFollowFilter)[objc_getAssociatedObject(vc, kFilterKey) unsignedIntegerValue]; }
static SCIFollowSortKey sciSort(id vc)  { return (SCIFollowSortKey)[objc_getAssociatedObject(vc, kSortKey) integerValue]; }
static BOOL sciReverse(id vc)           { return [objc_getAssociatedObject(vc, kReverseKey) boolValue]; }
static BOOL sciActive(id vc)            { return sciFilter(vc) != 0 || sciSort(vc) != SCISortDefault || sciReverse(vc); }

static BOOL sciPassesFilter(SCIFollowFilter f, SCIUserAttr a) {
	if ((f & SCIFilterMutual)    && !(a.following && a.followedBy)) return NO;
	if ((f & SCIFilterIFollow)   && !a.following)                  return NO;
	if ((f & SCIFilterFollowsMe) && !a.followedBy)                 return NO;
	if ((f & SCIFilterVerified)  && !a.verified)                   return NO;
	return YES;
}

static const void *kSheetKey = &kSheetKey;

static NSArray<NSDictionary *> *sciFilterRows(void) {
	return @[
		@{@"t": SCILocalized(@"Mutuals"),         @"i": @"person.2.fill",          @"v": @(SCIFilterMutual)},
		@{@"t": SCILocalized(@"People I follow"), @"i": @"person.fill.checkmark",  @"v": @(SCIFilterIFollow)},
		@{@"t": SCILocalized(@"Follows me"),      @"i": @"arrow.left.circle.fill", @"v": @(SCIFilterFollowsMe)},
		@{@"t": SCILocalized(@"Verified"),        @"i": @"checkmark.seal.fill",    @"v": @(SCIFilterVerified)},
	];
}
static NSArray<NSDictionary *> *sciSortRows(void) {
	return @[
		@{@"t": SCILocalized(@"Default"),            @"i": @"line.3.horizontal",      @"v": @(SCISortDefault)},
		@{@"t": SCILocalized(@"Name (A–Z)"),         @"i": @"textformat",             @"v": @(SCISortName)},
		@{@"t": SCILocalized(@"Verified first"),     @"i": @"checkmark.seal.fill",    @"v": @(SCISortVerified)},
		@{@"t": SCILocalized(@"Mutuals first"),      @"i": @"person.2.fill",          @"v": @(SCISortMutual)},
		@{@"t": SCILocalized(@"Follows me first"),   @"i": @"arrow.left.circle.fill", @"v": @(SCISortFollowsMe)},
		@{@"t": SCILocalized(@"People I follow first"), @"i": @"person.fill.checkmark", @"v": @(SCISortIFollow)},
	];
}

#pragma mark - options sheet

@interface SCIFollowSortSheet : UITableViewController
@property (nonatomic, weak) IGFollowListViewController *listVC;
- (void)refresh;
@end

@implementation SCIFollowSortSheet

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = SCILocalized(@"Filter & sort");
	self.view.backgroundColor = [SCIPopupChrome backgroundColor];
	self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(sci_done)];
}

- (void)sci_done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	if (self.listVC)
		objc_setAssociatedObject(self.listVC, kSheetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	switch (s) {
		case 0: return sciFilterRows().count;
		case 1: return sciSortRows().count + 1; // +1 reverse row
		case 2: return 3;
		default: return 1;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	switch (s) {
		case 0: return SCILocalized(@"Show only");
		case 1: return SCILocalized(@"Sort by");
		case 2: return SCILocalized(@"List");
		default: return nil;
	}
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return SCILocalized(@"Hides everyone who doesn't match all picked filters.");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.tintColor = UIColor.systemBlueColor;
	IGFollowListViewController *vc = self.listVC;

	if (ip.section == 0) {
		NSDictionary *r = sciFilterRows()[ip.row];
		cell.textLabel.text = SCILocalized(r[@"t"]);
		cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
		cell.accessoryType = (sciFilter(vc) & [r[@"v"] unsignedIntegerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)sciSortRows().count) {
			NSDictionary *r = sciSortRows()[ip.row];
			cell.textLabel.text = SCILocalized(r[@"t"]);
			cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
			cell.accessoryType = (sciSort(vc) == (SCIFollowSortKey)[r[@"v"] integerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		} else {
			cell.textLabel.text = SCILocalized(@"Reverse order");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.arrow.down"];
			cell.accessoryType = sciReverse(vc) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		}
	} else if (ip.section == 2) {
		BOOL loading = [objc_getAssociatedObject(vc, kLoadingKey) boolValue];
		if (ip.row == 0) {
			cell.textLabel.text = SCILocalized(@"Jump to top");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.to.line"];
		} else if (ip.row == 1) {
			cell.textLabel.text = SCILocalized(@"Jump to bottom");
			cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.to.line"];
		} else {
			NSUInteger loaded = [vc sci_loadedCount];
			BOOL end = sciIvarBOOL(vc, "_reachedUserListEnd");
			UITableViewCell *sub = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
			sub.tintColor = UIColor.systemBlueColor;
			sub.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
			sub.textLabel.text = loading ? SCILocalized(@"Loading") : SCILocalized(@"Load more");
			sub.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			sub.detailTextLabel.text = end
				? [NSString stringWithFormat:SCILocalized(@"%lu loaded · all loaded"), (unsigned long)loaded]
				: [NSString stringWithFormat:SCILocalized(@"%lu loaded"), (unsigned long)loaded];
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
		cell.textLabel.text = SCILocalized(@"Reset");
		cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
		BOOL active = sciActive(vc);
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
		SCIFollowFilter bit = (SCIFollowFilter)[sciFilterRows()[ip.row][@"v"] unsignedIntegerValue];
		objc_setAssociatedObject(vc, kFilterKey, @(sciFilter(vc) ^ bit), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[vc sci_changed];
	} else if (ip.section == 1) {
		if (ip.row < (NSInteger)sciSortRows().count) {
			objc_setAssociatedObject(vc, kSortKey, sciSortRows()[ip.row][@"v"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		} else {
			objc_setAssociatedObject(vc, kReverseKey, @(!sciReverse(vc)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
		[vc sci_changed];
	} else if (ip.section == 2) {
		if (ip.row == 0) [vc sci_jumpToTop];
		else if (ip.row == 1) [vc sci_jumpToBottom];
		else [vc sci_loadAll];
	} else {
		if (!sciActive(vc)) return;
		objc_setAssociatedObject(vc, kFilterKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(vc, kSortKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		objc_setAssociatedObject(vc, kReverseKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		[vc sci_changed];
	}
	[self refresh];
}

@end

#pragma mark - hook

%group FollowListSort

%hook IGFollowListViewController

- (NSArray *)objectsForListAdapter:(id)arg1 {
	NSArray *objs = %orig;
	if (!sciActive(self) || ![objs isKindOfClass:NSArray.class] || objs.count == 0) return objs;

	SCIFollowFilter filter = sciFilter(self);
	SCIFollowSortKey sortKey = sciSort(self);
	BOOL reverse = sciReverse(self);

	NSMutableArray *deco = [NSMutableArray array];
	for (id o in objs) {
		if (![o isKindOfClass:%c(IGUserListItemConfiguration)]) continue;
		NSString *name = nil;
		SCIUserAttr a = sciAttrForConfig(o, &name);
		if (!sciPassesFilter(filter, a)) continue;
		[deco addObject:@{ @"cfg": o, @"i": @(deco.count), @"name": name ?: @"",
			@"mutual": @(a.following && a.followedBy), @"fme": @(a.followedBy),
			@"ifo": @(a.following), @"ver": @(a.verified) }];
	}

	NSString *boolKey = nil;
	switch (sortKey) {
		case SCISortVerified:  boolKey = @"ver";    break;
		case SCISortMutual:    boolKey = @"mutual"; break;
		case SCISortFollowsMe: boolKey = @"fme";    break;
		case SCISortIFollow:   boolKey = @"ifo";    break;
		default: break;
	}

	if (sortKey != SCISortDefault) {
		[deco sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
			NSComparisonResult c = NSOrderedSame;
			if (sortKey == SCISortName) {
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
- (void)sci_changed {
	UIButton *btn = objc_getAssociatedObject(self, kButtonKey);
	if (btn) btn.tintColor = sciActive(self) ? UIColor.systemBlueColor : UIColor.labelColor;

	SCIFollowSortSheet *sheet = objc_getAssociatedObject(self, kSheetKey);
	if ([sheet isKindOfClass:SCIFollowSortSheet.class]) [sheet refresh];

	Ivar iv = class_getInstanceVariable([self class], "_listAdapter");
	id adapter = iv ? object_getIvar(self, iv) : nil;
	if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)])
		((void (*)(id, SEL, BOOL, id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), YES, nil);
}

%new
- (void)sci_presentSheet {
	if (objc_getAssociatedObject(self, kSheetKey)) return;
	SCIFollowSortSheet *sheet = [SCIFollowSortSheet new];
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
- (void)sci_installSortButton {
	if (objc_getAssociatedObject(self, kButtonKey)) return;

	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	btn.translatesAutoresizingMaskIntoConstraints = NO;
	btn.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.96];
	btn.layer.cornerRadius = 23;
	btn.layer.shadowColor = UIColor.blackColor.CGColor;
	btn.layer.shadowOpacity = 0.18;
	btn.layer.shadowRadius = 8;
	btn.layer.shadowOffset = CGSizeMake(0, 2);
	[btn setImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease"] forState:UIControlStateNormal];
	btn.tintColor = sciActive(self) ? UIColor.systemBlueColor : UIColor.labelColor;
	[btn addTarget:self action:@selector(sci_presentSheet) forControlEvents:UIControlEventTouchUpInside];

	[self.view addSubview:btn];
	[NSLayoutConstraint activateConstraints:@[
		[btn.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
		[btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
		[btn.widthAnchor constraintEqualToConstant:46],
		[btn.heightAnchor constraintEqualToConstant:46],
	]];
	objc_setAssociatedObject(self, kButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%new
- (UIScrollView *)sci_collectionView {
	id cv = sciIvarObj(self, "_collectionView");
	return [cv isKindOfClass:UIScrollView.class] ? cv : nil;
}

%new
- (void)sci_jumpToTop {
	UIScrollView *cv = [self sci_collectionView];
	[cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:YES];
}

%new
- (void)sci_triggerPaginate {
	// manualCheck:YES forces a page fetch without a real drag — pagination is
	// otherwise only scroll-gesture driven.
	SEL near = @selector(scrollViewWillScrollNearBottom:triggeredByManualCheck:);
	if ([self respondsToSelector:near]) {
		((void (*)(id, SEL, id, BOOL))objc_msgSend)(self, near, [self sci_collectionView], YES);
		return;
	}
	SEL s = @selector(_maybePaginateList);
	if ([self respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(self, s);
}

%new
- (void)sci_jumpToBottom {
	UIScrollView *cv = [self sci_collectionView];
	if (!cv) return;
	CGFloat y = cv.contentSize.height - cv.bounds.size.height + cv.adjustedContentInset.bottom;
	[cv setContentOffset:CGPointMake(0, MAX(-cv.adjustedContentInset.top, y)) animated:YES];
	[self sci_triggerPaginate];
}

// Page in a bounded batch via IG's near-bottom loader; press again to continue.
static const NSUInteger kLoadBatch = 200;

%new
- (void)sci_loadAll {
	if ([objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
	if (sciIvarBOOL(self, "_reachedUserListEnd")) {
		SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"List fully loaded"), SCILocalized(@"Everyone is already loaded."));
		return;
	}
	NSUInteger start = [self sci_loadedCount];
	objc_setAssociatedObject(self, kLoadingKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, kLoadStateKey,
		[@{@"count": @(start), @"target": @(start + kLoadBatch), @"stalls": @0, @"iter": @0} mutableCopy],
		OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[self sci_changed];
	[self performSelector:@selector(sci_loadAllStep) withObject:nil afterDelay:0.3];
}

%new
- (NSUInteger)sci_loadedCount {
	id list = sciIvarObj(self, "_userList");
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
- (void)sci_loadAllStep {
	if (![objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
	NSMutableDictionary *st = objc_getAssociatedObject(self, kLoadStateKey);
	NSUInteger count = [self sci_loadedCount];
	BOOL reachedEnd = sciIvarBOOL(self, "_reachedUserListEnd");
	NSUInteger target = [st[@"target"] unsignedIntegerValue];

	NSUInteger lastCount = [st[@"count"] unsignedIntegerValue];
	NSUInteger stalls = (count <= lastCount) ? [st[@"stalls"] unsignedIntegerValue] + 1 : 0;
	NSInteger iter = [st[@"iter"] integerValue];
	st[@"count"] = @(count);
	st[@"stalls"] = @(stalls);

	if (reachedEnd || count >= target || stalls >= 6 || iter >= 60) {
		objc_setAssociatedObject(self, kLoadingKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		SCINotifySuccess(SCI_NOTIF_GENERIC,
			reachedEnd ? SCILocalized(@"List fully loaded") : SCILocalized(@"Loaded more"),
			[NSString stringWithFormat:SCILocalized(@"%lu accounts"), (unsigned long)count]);
		[self sci_changed];
		return;
	}
	st[@"iter"] = @(iter + 1);
	if (!sciIvarBOOL(self, "_loading")) [self sci_triggerPaginate];
	[self performSelector:@selector(sci_loadAllStep) withObject:nil afterDelay:0.5];
}

- (void)viewDidLoad {
	%orig;
	[self sci_installSortButton];
}

%end

%end

%ctor {
	if ([SCIUtils getBoolPref:@"sci_followlist_sort_enabled"]) %init(FollowListSort);
}
