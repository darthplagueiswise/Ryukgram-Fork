// Story viewers list — filter / sort / search / pin.
// Reorders the IGListKit object array in objectsForListAdapter:; settings are
// sticky per-account. Pinned users float to top and bypass active filters.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../SCIChrome.h"
#import "../../UI/SCIPopupChrome.h"
#import "../../SCIAccountScopedDefaults.h"
#import "SCIStoryViewerPins.h"
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - state (sticky, per-account)

#define SVK_SORT    @"story_viewer_sort_key"
#define SVK_FILTER  @"story_viewer_filter_mask"
#define SVK_REVERSE @"story_viewer_reverse"

typedef NS_ENUM(NSInteger, SCISVSort) {
    SCISVSortDefault = 0,   // server order (most-recent viewer first)
    SCISVSortName,
    SCISVSortVerified,
    SCISVSortFollowing,     // accounts I follow first
    SCISVSortFollowsMe,     // accounts that follow me first
    SCISVSortMutual,
    SCISVSortLiked,
};

typedef NS_OPTIONS(NSUInteger, SCISVFilter) {
    SCISVFilterMutual    = 1 << 0,
    SCISVFilterIFollow   = 1 << 1,
    SCISVFilterFollowsMe = 1 << 2,
    SCISVFilterVerified  = 1 << 3,
    SCISVFilterLiked     = 1 << 4,
    SCISVFilterPinned    = 1 << 5,
    SCISVFilterNotFollowsMe = 1 << 6,
};

static SCISVSort sciSVSort(void) {
    return (SCISVSort)[[SCIAccountScopedDefaults objectForKey:SVK_SORT] integerValue];
}
static SCISVFilter sciSVFilter(void) {
    return (SCISVFilter)[[SCIAccountScopedDefaults objectForKey:SVK_FILTER] unsignedIntegerValue];
}
static BOOL sciSVReverse(void) {
    return [[SCIAccountScopedDefaults objectForKey:SVK_REVERSE] boolValue];
}
static void sciSVSetSort(SCISVSort v)    { [SCIAccountScopedDefaults setObject:@(v) forKey:SVK_SORT]; }
static void sciSVSetFilter(SCISVFilter v){ [SCIAccountScopedDefaults setObject:@(v) forKey:SVK_FILTER]; }
static void sciSVSetReverse(BOOL v)      { [SCIAccountScopedDefaults setObject:@(v) forKey:SVK_REVERSE]; }
static BOOL sciSVActive(void) {
    return sciSVSort() != SCISVSortDefault || sciSVFilter() != 0 || sciSVReverse();
}

#pragma mark - ivar helpers

static id sciIvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    return iv ? object_getIvar(obj, iv) : nil;
}
static BOOL sciIvarBOOL(id obj, const char *name) {
    if (!obj) return NO;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return NO;
    return *(BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}
static long long sciIvarI64(id obj, const char *name) {
    if (!obj) return 0;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return 0;
    return *(long long *)((char *)(__bridge void *)obj + ivar_getOffset(iv));
}
static id sciFieldCache(id obj, NSString *key) {
    if (!obj) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, "_fieldCache");
    if (!iv) return nil;
    id fc = object_getIvar(obj, iv);
    if (![fc isKindOfClass:NSDictionary.class]) return nil;
    id v = fc[key];
    return (v == [NSNull null]) ? nil : v;
}

#pragma mark - viewer model extraction

static BOOL sciIsViewerSource(id o) {
    if (!o) return NO;
    return [NSStringFromClass(object_getClass(o)) containsString:@"IGStoryViewerSource"];
}

typedef struct {
    BOOL following, followedBy, verified, liked;
} SCISVAttr;

static NSString *sciSVUserPK(id user) {
    NSString *pk = sciFieldCache(user, @"strong_id__");
    if (!pk.length) pk = sciFieldCache(user, @"pk");
    if (!pk.length && [user respondsToSelector:@selector(pk)]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(user, @selector(pk));
        if ([v isKindOfClass:NSString.class]) pk = v;
        else if (v) pk = [v description];
    }
    return pk ?: @"";
}

static SCISVAttr sciSVAttrForSource(id src, NSString **outName, NSString **outPK, id *outUser) {
    SCISVAttr a = (SCISVAttr){NO, NO, NO, NO};
    id user = sciIvarObj(src, "user");
    if (outUser) *outUser = user;
    if (outName) *outName = sciFieldCache(user, @"username") ?: @"";
    if (outPK)   *outPK   = sciSVUserPK(user);
    a.verified = [sciFieldCache(user, @"is_verified") boolValue];
    id rel = sciFieldCache(user, @"friendship_status");
    a.following  = [sciFieldCache(rel, @"following") boolValue];
    a.followedBy = [sciFieldCache(rel, @"followed_by") boolValue];
    a.liked = sciIvarBOOL(src, "showLikedBadge") || sciIvarI64(src, "likeType") != 0;
    return a;
}

static BOOL sciSVPassesNonPinned(SCISVFilter f, SCISVAttr a) {
    if ((f & SCISVFilterMutual)    && !(a.following && a.followedBy)) return NO;
    if ((f & SCISVFilterIFollow)   && !a.following)                  return NO;
    if ((f & SCISVFilterFollowsMe) && !a.followedBy)                 return NO;
    if ((f & SCISVFilterNotFollowsMe) && a.followedBy)              return NO;
    if ((f & SCISVFilterVerified)  && !a.verified)                   return NO;
    if ((f & SCISVFilterLiked)     && !a.liked)                      return NO;
    return YES;
}

#pragma mark - associated keys

static const void *kButtonKey = &kButtonKey;
static const void *kSheetKey  = &kSheetKey;
static const void *kLoadingKey = &kLoadingKey;
static const void *kLoadStateKey = &kLoadStateKey;
static const void *kQueryKey = &kQueryKey;

// Search query is transient per-VC (sort/filter are sticky per-account).
static NSString *sciSVQuery(id vc) {
    NSString *q = objc_getAssociatedObject(vc, kQueryKey);
    return [q isKindOfClass:NSString.class] ? q : @"";
}

#pragma mark - rows

static NSArray<NSDictionary *> *sciSVFilterRows(void) {
    return @[
        @{@"t": SCILocalized(@"Pinned"),          @"i": @"pin.fill",               @"v": @(SCISVFilterPinned)},
        @{@"t": SCILocalized(@"Mutuals"),         @"i": @"person.2.fill",          @"v": @(SCISVFilterMutual)},
        @{@"t": SCILocalized(@"People I follow"), @"i": @"person.fill.checkmark",  @"v": @(SCISVFilterIFollow)},
        @{@"t": SCILocalized(@"Follows me"),      @"i": @"arrow.left.circle.fill", @"v": @(SCISVFilterFollowsMe)},
        @{@"t": SCILocalized(@"Doesn't follow you"), @"i": @"person.crop.circle.badge.xmark", @"v": @(SCISVFilterNotFollowsMe)},
        @{@"t": SCILocalized(@"Verified"),        @"i": @"checkmark.seal.fill",    @"v": @(SCISVFilterVerified)},
        @{@"t": SCILocalized(@"Liked the story"), @"i": @"heart.fill",             @"v": @(SCISVFilterLiked)},
    ];
}
static NSArray<NSDictionary *> *sciSVSortRows(void) {
    return @[
        @{@"t": SCILocalized(@"Default (recent first)"), @"i": @"clock",                  @"v": @(SCISVSortDefault)},
        @{@"t": SCILocalized(@"Name (A–Z)"),             @"i": @"textformat",             @"v": @(SCISVSortName)},
        @{@"t": SCILocalized(@"Verified first"),         @"i": @"checkmark.seal.fill",    @"v": @(SCISVSortVerified)},
        @{@"t": SCILocalized(@"People I follow first"),  @"i": @"person.fill.checkmark",  @"v": @(SCISVSortFollowing)},
        @{@"t": SCILocalized(@"Follows me first"),       @"i": @"arrow.left.circle.fill", @"v": @(SCISVSortFollowsMe)},
        @{@"t": SCILocalized(@"Mutuals first"),          @"i": @"person.2.fill",          @"v": @(SCISVSortMutual)},
        @{@"t": SCILocalized(@"Liked first"),            @"i": @"heart.fill",             @"v": @(SCISVSortLiked)},
    ];
}

#pragma mark - forward decls on the VC

@interface IGStoryViewersListViewController (SCISV)
- (void)sci_changed;
- (void)sci_presentSheet;
- (void)sci_installButton;
- (UIScrollView *)sci_collectionView;
- (NSUInteger)sci_loadedCount;
- (BOOL)sci_hasNextPage;
- (void)sci_loadAll;
- (void)sci_loadAllStep;
- (void)sci_jumpToTop;
- (void)sci_jumpToBottom;
@end

#pragma mark - options sheet

@interface SCIStoryViewerSortSheet : UITableViewController <UISearchBarDelegate>
@property (nonatomic, weak) IGStoryViewersListViewController *listVC;
@property (nonatomic, strong) UISearchBar *searchBar;
- (void)refresh;
@end

@implementation SCIStoryViewerSortSheet

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SCILocalized(@"Filter & sort");
    self.view.backgroundColor = [SCIPopupChrome backgroundColor];
    self.tableView.backgroundColor = [SCIPopupChrome backgroundColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(sci_done)];

    UISearchBar *sb = [[UISearchBar alloc] init];
    sb.placeholder = SCILocalized(@"Search by name or username");
    sb.delegate = self;
    sb.searchBarStyle = UISearchBarStyleMinimal;
    sb.autocapitalizationType = UITextAutocapitalizationTypeNone;
    sb.autocorrectionType = UITextAutocorrectionTypeNo;
    sb.text = sciSVQuery(self.listVC);
    [sb sizeToFit];
    self.tableView.tableHeaderView = sb;
    self.searchBar = sb;
}
- (void)sci_done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refresh { [self.tableView reloadData]; }

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text {
    IGStoryViewersListViewController *vc = self.listVC;
    if (!vc) return;
    objc_setAssociatedObject(vc, kQueryKey, text ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc sci_changed];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)sb { [sb setShowsCancelButton:YES animated:YES]; [self sci_setSearching:YES]; }
- (void)searchBarTextDidEndEditing:(UISearchBar *)sb   { [sb setShowsCancelButton:NO  animated:YES]; [self sci_setSearching:NO];  }
- (void)searchBarCancelButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

// Short fixed detent while typing keeps the list visible above the keyboard
// (a lone detent can't be keyboard-expanded like medium/large).
- (void)sci_setSearching:(BOOL)searching {
    if (@available(iOS 16.0, *)) {
        UISheetPresentationController *spc = self.navigationController.sheetPresentationController;
        [spc animateChanges:^{
            if (searching) {
                UISheetPresentationControllerDetent *small = [UISheetPresentationControllerDetent
                    customDetentWithIdentifier:@"sciSearch"
                    resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> ctx) { return 240.0; }];
                spc.detents = @[small];
                spc.largestUndimmedDetentIdentifier = @"sciSearch";
            } else {
                spc.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
                spc.largestUndimmedDetentIdentifier = UISheetPresentationControllerDetentIdentifierMedium;
            }
        }];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.listVC) objc_setAssociatedObject(self.listVC, kSheetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return sciSVFilterRows().count;
        case 1: return sciSVSortRows().count + 1; // sorts + reverse row
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
    if (s == 0) return SCILocalized(@"Tick several to combine them. Pinned viewers always stay on top and ignore these filters.");
    if (s == 1) return SCILocalized(@"Settings are saved and reused next time.");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.tintColor = UIColor.systemBlueColor;

    if (ip.section == 0) {
        NSDictionary *r = sciSVFilterRows()[ip.row];
        cell.textLabel.text = r[@"t"];
        cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
        cell.accessoryType = (sciSVFilter() & [r[@"v"] unsignedIntegerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else if (ip.section == 1) {
        if (ip.row < (NSInteger)sciSVSortRows().count) {
            NSDictionary *r = sciSVSortRows()[ip.row];
            cell.textLabel.text = r[@"t"];
            cell.imageView.image = [UIImage systemImageNamed:r[@"i"]];
            cell.accessoryType = (sciSVSort() == (SCISVSort)[r[@"v"] integerValue]) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = SCILocalized(@"Reverse order");
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.arrow.down"];
            cell.accessoryType = sciSVReverse() ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (ip.section == 2) {
        IGStoryViewersListViewController *vc = self.listVC;
        BOOL loading = [objc_getAssociatedObject(vc, kLoadingKey) boolValue];
        if (ip.row == 0) {
            cell.textLabel.text = SCILocalized(@"Jump to top");
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.up.to.line"];
        } else if (ip.row == 1) {
            cell.textLabel.text = SCILocalized(@"Jump to bottom");
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.down.to.line"];
        } else {
            NSUInteger loaded = [vc sci_loadedCount];
            BOOL more = [vc sci_hasNextPage];
            UITableViewCell *sub = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            sub.tintColor = UIColor.systemBlueColor;
            sub.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
            sub.textLabel.text = loading ? SCILocalized(@"Loading") : SCILocalized(@"Load all viewers");
            sub.detailTextLabel.textColor = UIColor.secondaryLabelColor;
            sub.detailTextLabel.text = more
                ? [NSString stringWithFormat:SCILocalized(@"%lu loaded"), (unsigned long)loaded]
                : [NSString stringWithFormat:SCILocalized(@"%lu loaded · all loaded"), (unsigned long)loaded];
            if (loading) {
                UIActivityIndicatorView *spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
                [spin startAnimating];
                sub.accessoryView = spin;
            } else if (!more) {
                sub.textLabel.textColor = UIColor.tertiaryLabelColor;
                sub.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            return sub;
        }
    } else {
        cell.textLabel.text = SCILocalized(@"Reset");
        cell.imageView.image = [UIImage systemImageNamed:@"xmark.circle"];
        BOOL active = sciSVActive() || sciSVQuery(self.listVC).length > 0;
        cell.textLabel.textColor = active ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
        cell.tintColor = UIColor.systemRedColor;
        cell.selectionStyle = active ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    IGStoryViewersListViewController *vc = self.listVC;
    if (!vc) return;

    if (ip.section == 0) {
        SCISVFilter bit = (SCISVFilter)[sciSVFilterRows()[ip.row][@"v"] unsignedIntegerValue];
        sciSVSetFilter(sciSVFilter() ^ bit);
        [vc sci_changed];
    } else if (ip.section == 1) {
        if (ip.row < (NSInteger)sciSVSortRows().count) sciSVSetSort((SCISVSort)[sciSVSortRows()[ip.row][@"v"] integerValue]);
        else sciSVSetReverse(!sciSVReverse());
        [vc sci_changed];
    } else if (ip.section == 2) {
        if (ip.row == 0) [vc sci_jumpToTop];
        else if (ip.row == 1) [vc sci_jumpToBottom];
        else [vc sci_loadAll];
    } else {
        if (!sciSVActive() && sciSVQuery(vc).length == 0) return;
        sciSVSetSort(SCISVSortDefault);
        sciSVSetFilter(0);
        sciSVSetReverse(NO);
        objc_setAssociatedObject(vc, kQueryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.searchBar.text = @"";
        [vc sci_changed];
    }
    [self refresh];
}

@end

#pragma mark - pin badge on the viewer cell

static const NSInteger kSVPinBadgeTag = 0x5350494e; // 'SPIN'

static void sciSVRefreshPinBadge(id cell) {
    if (![cell respondsToSelector:@selector(avatarView)] || ![cell respondsToSelector:@selector(viewerSource)]) return;
    UIView *avatar = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(avatarView));
    if (![avatar isKindOfClass:UIView.class]) return;

    id src = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(viewerSource));
    NSString *pk = sciSVUserPK(sciIvarObj(src, "user"));
    BOOL pinned = pk.length && [SCIStoryViewerPins isPinned:pk];

    UIView *badge = [avatar viewWithTag:kSVPinBadgeTag];
    if (!pinned) { [badge removeFromSuperview]; return; }
    if (!badge) {
        CGFloat d = 18;
        UIView *b = [[UIView alloc] initWithFrame:CGRectMake(0, 0, d, d)];
        b.tag = kSVPinBadgeTag;
        b.backgroundColor = UIColor.systemBlueColor;
        b.layer.cornerRadius = d / 2;
        b.layer.borderWidth = 1.5;
        b.layer.borderColor = UIColor.systemBackgroundColor.CGColor;
        b.userInteractionEnabled = NO;
        UIImageView *iv = [[UIImageView alloc] initWithImage:
            [[UIImage systemImageNamed:@"pin.fill"] imageWithConfiguration:
                [UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightBold]]];
        iv.tintColor = UIColor.whiteColor;
        iv.frame = CGRectInset(b.bounds, 4, 4);
        iv.contentMode = UIViewContentModeScaleAspectFit;
        [b addSubview:iv];
        [avatar addSubview:b];
        badge = b;
    }
    CGFloat d = badge.bounds.size.width;
    avatar.clipsToBounds = NO;
    badge.center = CGPointMake(avatar.bounds.size.width - d / 2 + 1, d / 2 - 1);
    [avatar bringSubviewToFront:badge];
}

#pragma mark - hook

%hook IGStoryViewersListViewController

- (NSArray *)objectsForListAdapter:(id)adapter {
    NSArray *objs = %orig;
    if (![SCIUtils getBoolPref:@"sci_story_viewer_sort_enabled"]) return objs;
    if (![objs isKindOfClass:NSArray.class] || objs.count == 0) return objs;

    SCISVFilter filter = sciSVFilter();
    SCISVSort sortKey = sciSVSort();
    BOOL reverse = sciSVReverse();
    NSString *query = sciSVQuery(self);
    if (!sciSVActive() && [SCIStoryViewerPins count] == 0 && query.length == 0) return objs;

    NSMutableArray *deco = [NSMutableArray array];
    NSUInteger orig = 0;
    for (id o in objs) {
        if (!sciIsViewerSource(o)) continue;
        NSString *name = nil, *pk = nil; id user = nil;
        SCISVAttr a = sciSVAttrForSource(o, &name, &pk, &user);
        NSUInteger pinRank = pk.length ? [SCIStoryViewerPins rankOfPK:pk] : NSNotFound;
        BOOL pinned = pinRank != NSNotFound;

        BOOL pass;
        if (filter & SCISVFilterPinned) pass = pinned && sciSVPassesNonPinned(filter, a);
        else                            pass = pinned || sciSVPassesNonPinned(filter, a);
        if (!pass) { orig++; continue; }

        if (query.length) {
            NSString *full = sciFieldCache(user, @"full_name") ?: @"";
            if ([name rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound &&
                [full rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) { orig++; continue; }
        }

        [deco addObject:@{ @"src": o, @"i": @(orig++), @"name": name ?: @"",
            @"mutual": @(a.following && a.followedBy), @"fme": @(a.followedBy),
            @"ifo": @(a.following), @"ver": @(a.verified), @"liked": @(a.liked),
            @"pin": @(pinned), @"rank": @(pinned ? pinRank : NSNotFound) }];
    }

    NSString *boolKey = nil;
    switch (sortKey) {
        case SCISVSortVerified:  boolKey = @"ver";    break;
        case SCISVSortMutual:    boolKey = @"mutual"; break;
        case SCISVSortFollowsMe: boolKey = @"fme";    break;
        case SCISVSortFollowing: boolKey = @"ifo";    break;
        case SCISVSortLiked:     boolKey = @"liked";  break;
        default: break;
    }

    NSMutableArray *pinned = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];
    for (NSDictionary *d in deco) [([d[@"pin"] boolValue] ? pinned : rest) addObject:d];

    [pinned sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        return [x[@"rank"] compare:y[@"rank"]];
    }];

    if (sortKey != SCISVSortDefault) {
        [rest sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
            NSComparisonResult c;
            if (sortKey == SCISVSortName) c = [x[@"name"] caseInsensitiveCompare:y[@"name"]];
            else {
                BOOL bx = [x[boolKey] boolValue], by = [y[boolKey] boolValue];
                c = (bx == by) ? NSOrderedSame : (bx ? NSOrderedAscending : NSOrderedDescending);
            }
            if (c == NSOrderedSame) return [x[@"i"] compare:y[@"i"]];
            return reverse ? (NSComparisonResult)(-c) : c;
        }];
    } else if (reverse) {
        rest = [[[rest reverseObjectEnumerator] allObjects] mutableCopy];
    }

    NSMutableArray *sortedSrc = [NSMutableArray arrayWithCapacity:deco.count];
    for (NSDictionary *d in pinned) [sortedSrc addObject:d[@"src"]];
    for (NSDictionary *d in rest)   [sortedSrc addObject:d[@"src"]];

    // Re-thread: keep non-viewer rows (header label, tail spinner) at their ends.
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:objs.count];
    BOOL injected = NO;
    for (id o in objs) {
        if (sciIsViewerSource(o)) {
            if (!injected) { [result addObjectsFromArray:sortedSrc]; injected = YES; }
        } else {
            [result addObject:o];
        }
    }
    return result;
}

%new
- (void)sci_changed {
    BOOL active = sciSVActive() || sciSVQuery(self).length > 0;
    UIButton *btn = objc_getAssociatedObject(self, kButtonKey);
    if ([btn isKindOfClass:SCIChromeButton.class])
        ((SCIChromeButton *)btn).iconTint = active ? UIColor.systemBlueColor : UIColor.labelColor;

    SCIStoryViewerSortSheet *sheet = objc_getAssociatedObject(self, kSheetKey);
    if ([sheet isKindOfClass:SCIStoryViewerSortSheet.class]) [sheet refresh];

    id adapter = sciIvarObj(self, "_adapter");
    if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)])
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), YES, nil);
}

%new
- (void)sci_presentSheet {
    if (objc_getAssociatedObject(self, kSheetKey)) return;
    SCIStoryViewerSortSheet *sheet = [SCIStoryViewerSortSheet new];
    sheet.listVC = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:sheet];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *spc = nav.sheetPresentationController;
        spc.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
        spc.prefersScrollingExpandsWhenScrolledToEdge = NO;
        spc.prefersGrabberVisible = YES;
        spc.preferredCornerRadius = 22;
    }
    objc_setAssociatedObject(self, kSheetKey, sheet, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:nav animated:YES completion:nil];
}

%new
- (void)sci_installButton {
    if (objc_getAssociatedObject(self, kButtonKey)) return;
    SCIChromeButton *btn = [[SCIChromeButton alloc] initWithSymbol:@"line.3.horizontal.decrease" pointSize:18.0 diameter:46.0];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.bubbleColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.96];
    btn.iconTint = sciSVActive() ? UIColor.systemBlueColor : UIColor.labelColor;
    // No shadow: it draws outside the capture-redaction canvas and would leak on screenshots.
    [btn addTarget:self action:@selector(sci_presentSheet) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    [NSLayoutConstraint activateConstraints:@[
        [btn.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [btn.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24],
        [btn.widthAnchor constraintEqualToConstant:46],
        [btn.heightAnchor constraintEqualToConstant:46],
    ]];
    objc_setAssociatedObject(self, kButtonKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sci_longPress:)];
    lp.minimumPressDuration = 0.35;
    [[self sci_collectionView] addGestureRecognizer:lp];
}

%new
- (void)sci_longPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    UICollectionView *cv = (UICollectionView *)[self sci_collectionView];
    if (![cv isKindOfClass:UICollectionView.class]) return;
    CGPoint p = [gr locationInView:cv];
    NSIndexPath *ip = [cv indexPathForItemAtPoint:p];
    if (!ip) return;
    id cell = [cv cellForItemAtIndexPath:ip];
    if (![cell respondsToSelector:@selector(viewerSource)]) return;
    id src = ((id (*)(id, SEL))objc_msgSend)(cell, @selector(viewerSource));
    if (!sciIsViewerSource(src)) return;

    id user = sciIvarObj(src, "user");
    NSString *pk = sciSVUserPK(user);
    if (!pk.length) return;
    NSString *uname = sciFieldCache(user, @"username") ?: @"";
    NSString *full = sciFieldCache(user, @"full_name") ?: @"";
    NSString *pic = sciFieldCache(user, @"profile_pic_url") ?: @"";

    BOOL nowPinned = [SCIStoryViewerPins togglePK:pk entry:@{
        @"pk": pk, @"username": uname, @"fullName": full, @"avatarURL": pic
    }];

    UIImpactFeedbackGenerator *fb = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [fb impactOccurred];
    SCINotifySuccess(SCI_NOTIF_PIN_STORY_VIEWER,
        nowPinned ? SCILocalized(@"Viewer pinned") : SCILocalized(@"Viewer unpinned"),
        uname.length ? [@"@" stringByAppendingString:uname] : nil);

    sciSVRefreshPinBadge(cell);
    [self sci_changed];
}

%new
- (UIScrollView *)sci_collectionView {
    id cv = sciIvarObj(self, "_collectionView");
    return [cv isKindOfClass:UIScrollView.class] ? cv : nil;
}

%new
- (NSUInteger)sci_loadedCount {
    id adapter = sciIvarObj(self, "_adapter");
    if (![adapter respondsToSelector:@selector(objects)]) return 0;
    NSArray *objs = ((id (*)(id, SEL))objc_msgSend)(adapter, @selector(objects));
    NSUInteger n = 0;
    for (id o in objs) if (sciIsViewerSource(o)) n++;
    return n;
}

%new
- (BOOL)sci_hasNextPage {
    return sciIvarBOOL(sciIvarObj(self, "_listController"), "_hasNextPage");
}

%new
- (void)sci_jumpToTop {
    UIScrollView *cv = [self sci_collectionView];
    [cv setContentOffset:CGPointMake(0, -cv.adjustedContentInset.top) animated:YES];
}
%new
- (void)sci_jumpToBottom {
    UIScrollView *cv = [self sci_collectionView];
    if (!cv) return;
    CGFloat y = cv.contentSize.height - cv.bounds.size.height + cv.adjustedContentInset.bottom;
    if (y < -cv.adjustedContentInset.top) y = -cv.adjustedContentInset.top;
    [cv setContentOffset:CGPointMake(0, y) animated:YES];
}

%new
- (void)sci_loadAll {
    if ([objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
    if (![self sci_hasNextPage]) {
        SCINotifyInfo(SCI_NOTIF_GENERIC, SCILocalized(@"List fully loaded"), SCILocalized(@"Everyone is already loaded."));
        return;
    }
    objc_setAssociatedObject(self, kLoadingKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kLoadStateKey,
        [@{@"count": @([self sci_loadedCount]), @"stalls": @0, @"iter": @0} mutableCopy],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self sci_changed];
    [self performSelector:@selector(sci_loadAllStep) withObject:nil afterDelay:0.4];
}

%new
- (void)sci_loadAllStep {
    if (![objc_getAssociatedObject(self, kLoadingKey) boolValue]) return;
    NSMutableDictionary *st = objc_getAssociatedObject(self, kLoadStateKey);
    NSUInteger count = [self sci_loadedCount];
    BOOL more = [self sci_hasNextPage];

    NSUInteger last = [st[@"count"] unsignedIntegerValue];
    NSUInteger stalls = (count <= last) ? [st[@"stalls"] unsignedIntegerValue] + 1 : 0;
    NSInteger iter = [st[@"iter"] integerValue];
    st[@"count"] = @(count);
    st[@"stalls"] = @(stalls);

    if (!more || stalls >= 8 || iter >= 80) {
        objc_setAssociatedObject(self, kLoadingKey, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SCINotifySuccess(SCI_NOTIF_GENERIC,
            more ? SCILocalized(@"Loaded more") : SCILocalized(@"List fully loaded"),
            [NSString stringWithFormat:SCILocalized(@"%lu viewers"), (unsigned long)count]);
        [self sci_changed];
        return;
    }
    st[@"iter"] = @(iter + 1);
    [self sci_jumpToBottom];   // displaying the tail item drives the next page fetch
    [self performSelector:@selector(sci_loadAllStep) withObject:nil afterDelay:0.6];
}

- (void)viewDidLoad {
    %orig;
    [self sci_installButton];
}

%end

#pragma mark - pin badge hook

%hook IGStoryViewerCell

- (void)layoutSubviews {
    %orig;
    if ([SCIUtils getBoolPref:@"sci_story_viewer_sort_enabled"]) sciSVRefreshPinBadge(self);
}

- (void)prepareForReuse {
    %orig;
    if ([self respondsToSelector:@selector(avatarView)]) {
        UIView *av = ((id (*)(id, SEL))objc_msgSend)(self, @selector(avatarView));
        [[av viewWithTag:kSVPinBadgeTag] removeFromSuperview];
    }
}

%end

%ctor {
    if ([SCIUtils getBoolPref:@"sci_story_viewer_sort_enabled"]) %init;
}
