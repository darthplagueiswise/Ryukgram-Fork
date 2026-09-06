#import "RYGRuntimeSurfaceBrowserViewController.h"
#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueEditor.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <string.h>
#include <stdlib.h>

static NSString *const RYGRuntimeLiveReceiverDidChangeNotification = @"RYGRuntimeLiveReceiverDidChangeNotification";
static const void *kRYGSurfaceEntryKey = &kRYGSurfaceEntryKey;
static const void *kRYGSurfaceLongPressKey = &kRYGSurfaceLongPressKey;
static const void *kRYGBottomSearchItemKey = &kRYGBottomSearchItemKey;

typedef NS_ENUM(NSInteger, RYGLiveScope) {
    RYGLiveScopeAll = 0,
    RYGLiveScopeBoolean,
    RYGLiveScopeNumeric,
    RYGLiveScopeObject,
    RYGLiveScopeOverrides,
};

#pragma mark - WAT live receiver observation, consolidated

@interface RYGLiveReceiverProbe : NSObject
@property(nonatomic, copy) NSString *uid;
@property(nonatomic, copy) NSString *className;
@property(nonatomic, assign) SEL selector;
@property(nonatomic, assign) IMP original;
@property(nonatomic, assign) char typeCode;
@end
@implementation RYGLiveReceiverProbe @end

static NSMutableDictionary<NSString *, RYGLiveReceiverProbe *> *gRYGReceiverProbes;
static NSMapTable<NSString *, id> *gRYGReceiverByUID;
static NSMapTable<NSString *, id> *gRYGReceiverByClass;
static NSObject *gRYGReceiverLock;

static void RYGReceiverEnsureState(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRYGReceiverProbes = [NSMutableDictionary dictionary];
        gRYGReceiverByUID = [NSMapTable strongToWeakObjectsMapTable];
        gRYGReceiverByClass = [NSMapTable strongToWeakObjectsMapTable];
        gRYGReceiverLock = [NSObject new];
    });
}

static NSString *RYGReceiverUID(NSString *className, NSString *selectorName) {
    if (!className.length || !selectorName.length) return @"";
    return [NSString stringWithFormat:@"%@|instance|%@", className, selectorName];
}

static const char *RYGSkipQualifiers(const char *type) {
    if (!type) return "";
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGProbeTypeSupported(char type) {
    return strchr("BcCsSiIlLqQfd@", type) != NULL;
}

static void RYGReceiverObserve(RYGLiveReceiverProbe *probe, id receiver) {
    if (!probe || !receiver) return;
    RYGReceiverEnsureState();
    BOOL changed = NO;
    @synchronized (gRYGReceiverLock) {
        id old = [gRYGReceiverByUID objectForKey:probe.uid];
        changed = old != receiver;
        [gRYGReceiverByUID setObject:receiver forKey:probe.uid];
        if (probe.className.length) [gRYGReceiverByClass setObject:receiver forKey:probe.className];
    }
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:RYGRuntimeLiveReceiverDidChangeNotification
                                                               object:nil
                                                             userInfo:@{ @"uid": probe.uid ?: @"" }];
        });
    }
}

static IMP RYGReceiverReplacement(RYGLiveReceiverProbe *probe) {
    switch (probe.typeCode) {
        case 'B': return imp_implementationWithBlock(^BOOL(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((BOOL(*)(id,SEL))probe.original)(r,probe.selector) : NO; });
        case 'c': return imp_implementationWithBlock(^signed char(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((signed char(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'C': return imp_implementationWithBlock(^unsigned char(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((unsigned char(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 's': return imp_implementationWithBlock(^short(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((short(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'S': return imp_implementationWithBlock(^unsigned short(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((unsigned short(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'i': return imp_implementationWithBlock(^int(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((int(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'I': return imp_implementationWithBlock(^unsigned int(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((unsigned int(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'l': return imp_implementationWithBlock(^long(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((long(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'L': return imp_implementationWithBlock(^unsigned long(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((unsigned long(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'q': return imp_implementationWithBlock(^long long(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((long long(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'Q': return imp_implementationWithBlock(^unsigned long long(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((unsigned long long(*)(id,SEL))probe.original)(r,probe.selector) : 0; });
        case 'f': return imp_implementationWithBlock(^float(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((float(*)(id,SEL))probe.original)(r,probe.selector) : 0.0f; });
        case 'd': return imp_implementationWithBlock(^double(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((double(*)(id,SEL))probe.original)(r,probe.selector) : 0.0; });
        case '@': return imp_implementationWithBlock(^id(id r){ RYGReceiverObserve(probe,r); return probe.original ? ((id(*)(id,SEL))probe.original)(r,probe.selector) : nil; });
        default: return NULL;
    }
}

static void RYGInstallReceiverProbe(RYGRuntimeEntry *entry) {
    if (!entry || entry.classMethod || !entry.className.length || !entry.selectorName.length ||
        !RYGRuntimeValueSelectorIsSafeGetter(entry.selectorName)) return;

    NSString *uid = RYGReceiverUID(entry.className, entry.selectorName);
    if (!uid.length) return;
    RYGReceiverEnsureState();
    @synchronized (gRYGReceiverLock) {
        if (gRYGReceiverProbes[uid]) return;
    }

    Class cls = NSClassFromString(entry.className) ?: objc_getClass(entry.className.UTF8String);
    SEL selector = NSSelectorFromString(entry.selectorName);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 2) return;

    char raw[64] = {0};
    method_getReturnType(method, raw, sizeof(raw));
    char type = RYGSkipQualifiers(raw)[0];
    if (!RYGProbeTypeSupported(type)) return;

    RYGLiveReceiverProbe *probe = [RYGLiveReceiverProbe new];
    probe.uid = uid;
    probe.className = entry.className;
    probe.selector = selector;
    probe.typeCode = type;
    IMP replacement = RYGReceiverReplacement(probe);
    if (!replacement) return;

    IMP original = NULL;
    MSHookMessageEx(cls, selector, replacement, &original);
    if (!original || original == replacement) return;
    probe.original = original;
    @synchronized (gRYGReceiverLock) {
        gRYGReceiverProbes[uid] = probe;
    }
}

static id RYGObservedReceiver(RYGRuntimeEntry *entry) {
    if (!entry || entry.classMethod) return nil;
    RYGReceiverEnsureState();
    NSString *uid = RYGReceiverUID(entry.className, entry.selectorName);
    @synchronized (gRYGReceiverLock) {
        id receiver = uid.length ? [gRYGReceiverByUID objectForKey:uid] : nil;
        if (!receiver && entry.className.length) receiver = [gRYGReceiverByClass objectForKey:entry.className];
        Class cls = NSClassFromString(entry.className) ?: objc_getClass(entry.className.UTF8String);
        SEL selector = NSSelectorFromString(entry.selectorName);
        if (receiver && cls && [receiver isKindOfClass:cls] && [receiver respondsToSelector:selector]) return receiver;
    }
    return nil;
}

#pragma mark - Conservative receiver resolution

static BOOL RYGExactReceiver(id object, Class cls, SEL selector) {
    return object && cls && [object isKindOfClass:cls] && [object respondsToSelector:selector];
}

static id RYGFindInViewTree(UIView *view, Class cls, SEL selector) {
    if (!view) return nil;
    if (RYGExactReceiver(view, cls, selector)) return view;
    for (UIView *subview in view.subviews) {
        id found = RYGFindInViewTree(subview, cls, selector);
        if (found) return found;
    }
    return nil;
}

static id RYGFindInControllerTree(UIViewController *controller, Class cls, SEL selector) {
    if (!controller) return nil;
    if (RYGExactReceiver(controller, cls, selector)) return controller;
    id found = RYGFindInViewTree(controller.viewIfLoaded, cls, selector);
    if (found) return found;
    if (controller.presentedViewController && (found = RYGFindInControllerTree(controller.presentedViewController, cls, selector))) return found;
    if ([controller isKindOfClass:UINavigationController.class] &&
        (found = RYGFindInControllerTree(((UINavigationController *)controller).visibleViewController, cls, selector))) return found;
    if ([controller isKindOfClass:UITabBarController.class] &&
        (found = RYGFindInControllerTree(((UITabBarController *)controller).selectedViewController, cls, selector))) return found;
    for (UIViewController *child in controller.childViewControllers) {
        found = RYGFindInControllerTree(child, cls, selector);
        if (found) return found;
    }
    return nil;
}

static id RYGSharedReceiver(Class cls, SEL selector) {
    if (!cls) return nil;
    for (NSString *name in @[@"shared", @"sharedInstance", @"current", @"defaultInstance",
                               @"defaultManager", @"manager", @"provider", @"properties",
                               @"instance", @"getInstance"]) {
        SEL factory = NSSelectorFromString(name);
        Method method = class_getClassMethod(cls, factory);
        if (!method || method_getNumberOfArguments(method) != 2) continue;
        char raw[32] = {0};
        method_getReturnType(method, raw, sizeof(raw));
        if (RYGSkipQualifiers(raw)[0] != '@') continue;
        @try {
            id value = ((id(*)(id,SEL))objc_msgSend)((id)cls, factory);
            if (RYGExactReceiver(value, cls, selector)) return value;
        } @catch (__unused NSException *exception) {}
    }
    return nil;
}

#pragma mark - Browser

@interface RYGRuntimeSurfaceBrowserViewController () <UISearchResultsUpdating, UISearchBarDelegate, UITextFieldDelegate>
@property(nonatomic, strong) RYGRuntimeSurfaceSpec *spec;
@property(nonatomic, copy) NSString *initialQuery;
@property(nonatomic, copy) NSArray<RYGRuntimeEntry *> *allEntries;
@property(nonatomic, copy) NSArray<NSString *> *sectionKeys;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<RYGRuntimeEntry *> *> *sections;
@property(nonatomic, strong) UISearchController *search;
@property(nonatomic, strong) NSMapTable<NSString *, id> *receiverCache;
@property(nonatomic, assign) BOOL didScan;
@property(nonatomic, assign) BOOL scanning;
@property(nonatomic, assign) NSUInteger scanGeneration;
@property(nonatomic, assign) NSUInteger filterGeneration;
@end

@implementation RYGRuntimeSurfaceBrowserViewController

- (instancetype)initWithSpec:(RYGRuntimeSurfaceSpec *)spec initialQuery:(NSString *)initialQuery {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _spec = spec;
        _initialQuery = [initialQuery copy] ?: @"";
        _allEntries = @[];
        _sectionKeys = @[];
        _sections = @{};
        _receiverCache = [NSMapTable strongToWeakObjectsMapTable];
        self.title = spec.title ?: @"Runtime";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title ?: @"Runtime");
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = 54.0;
    self.tableView.estimatedRowHeight = 54.0;

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.hidesNavigationBarDuringPresentation = NO;
    search.searchBar.delegate = self;
    search.searchBar.placeholder = @"Image, family, class, selector or type";
    search.searchBar.scopeButtonTitles = @[@"All", @"BOOL", @"Numbers", @"Objects", @"Overrides"];
    search.searchBar.selectedScopeButtonIndex = RYGLiveScopeAll;
    search.searchBar.text = self.initialQuery;
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
    self.search = search;

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                              target:self
                                                                              action:@selector(scanNow)];
    UIBarButtonItem *apply = [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                                              style:UIBarButtonItemStyleDone
                                                             target:self
                                                             action:@selector(applyAllOverrides)];
    self.navigationItem.rightBarButtonItems = @[apply, refresh];

    UIRefreshControl *pull = [UIRefreshControl new];
    [pull addTarget:self action:@selector(scanNow) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = pull;

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(receiverChanged:)
                                               name:RYGRuntimeLiveReceiverDidChangeNotification
                                             object:nil];
    RYGLiquidGlassApplyToViewController(self);
    [self configureMorphingSearch];
}

- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self configureMorphingSearch];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self configureMorphingSearch];
    if (@available(iOS 26.0, *)) [self.navigationController setToolbarHidden:NO animated:animated];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (@available(iOS 26.0, *)) [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didScan) [self scanNow];
}

- (void)configureMorphingSearch {
    if (!self.search) return;
    if (@available(iOS 26.0, *)) {
        SEL allowToolbar = NSSelectorFromString(@"setSearchBarPlacementAllowsToolbarIntegration:");
        if ([self.navigationItem respondsToSelector:allowToolbar]) {
            ((void(*)(id,SEL,BOOL))objc_msgSend)(self.navigationItem, allowToolbar, YES);
        }
        SEL placementSelector = NSSelectorFromString(@"searchBarPlacementBarButtonItem");
        UIBarButtonItem *placement = nil;
        if ([self.navigationItem respondsToSelector:placementSelector]) {
            placement = ((id(*)(id,SEL))objc_msgSend)(self.navigationItem, placementSelector);
        }
        if (placement) {
            UIBarButtonItem *stored = objc_getAssociatedObject(self, kRYGBottomSearchItemKey);
            if (stored != placement || self.toolbarItems.count != 2) {
                UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
                self.toolbarItems = @[placement, flex];
                objc_setAssociatedObject(self, kRYGBottomSearchItemKey, placement, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

- (void)receiverChanged:(NSNotification *)note {
    (void)note;
    NSArray<NSIndexPath *> *visible = self.tableView.indexPathsForVisibleRows ?: @[];
    if (visible.count) [self.tableView reloadRowsAtIndexPaths:visible withRowAnimation:UITableViewRowAnimationNone];
}

- (void)scanNow {
    if (self.scanning) return;
    self.scanning = YES;
    self.didScan = YES;
    NSUInteger generation = ++self.scanGeneration;
    self.title = @"Reading loaded runtime…";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.navigationItem.rightBarButtonItems.firstObject.enabled = NO;
    RYGRuntimeSurfaceSpec *spec = self.spec;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<RYGRuntimeEntry *> *entries = [RYGRuntimeScanner scanSurface:spec] ?: @[];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.scanGeneration) return;
            self.scanning = NO;
            self.navigationItem.rightBarButtonItems.firstObject.enabled = YES;
            [self.refreshControl endRefreshing];
            self.allEntries = entries;
            [self.receiverCache removeAllObjects];
            [self scheduleFilterWithDelay:0.0];
        });
    });
}

static NSArray<NSString *> *RYGFilterGroups(NSString *query) {
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *part in [(query ?: @"").lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length) [groups addObject:part];
    }
    return groups.copy;
}

static BOOL RYGEntryMatchesGroups(NSString *haystack, NSArray<NSString *> *groups) {
    if (!groups.count) return YES;
    NSString *lower = haystack.lowercaseString ?: @"";
    NSString *compact = [[lower componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    for (NSString *group in groups) {
        BOOL hit = NO;
        for (NSString *token in [group componentsSeparatedByString:@"|"]) {
            if (!token.length) continue;
            NSString *compactToken = [[token componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
            if ([lower containsString:token] || (compactToken.length && [compact containsString:compactToken])) { hit = YES; break; }
        }
        if (!hit) return NO;
    }
    return YES;
}

static BOOL RYGScopeMatches(RYGRuntimeEntry *entry, RYGLiveScope scope) {
    switch (scope) {
        case RYGLiveScopeBoolean: return RYGRuntimeValueTypeIsBoolean(entry.typeCode);
        case RYGLiveScopeNumeric: return RYGRuntimeValueTypeIsSignedInteger(entry.typeCode) || RYGRuntimeValueTypeIsUnsignedInteger(entry.typeCode) || RYGRuntimeValueTypeIsFloatingPoint(entry.typeCode);
        case RYGLiveScopeObject: return RYGRuntimeValueTypeIsObject(entry.typeCode);
        case RYGLiveScopeOverrides: return RYGRuntimeValueHasOverride(entry.className, entry.selectorName, entry.classMethod);
        default: return YES;
    }
}

static NSString *RYGSectionForEntryWithSpec(RYGRuntimeEntry *entry, RYGRuntimeSurfaceSpec *spec) {
    if (spec.runtimeFamilyKey.length) {
        return [NSString stringWithFormat:@"%@ — %@",
                entry.imageName.length ? entry.imageName : @"Runtime",
                entry.className.length ? entry.className : @"Unknown"];
    }
    if (spec.runtimeImagePath.length) {
        return entry.runtimeFamily.length ? entry.runtimeFamily : (entry.className.length ? entry.className : @"Other Runtime");
    }
    return entry.runtimeSubcategory.length ? entry.runtimeSubcategory : (entry.className.length ? entry.className : @"Other Runtime");
}

- (void)scheduleFilterWithDelay:(NSTimeInterval)delay {
    NSString *query = [self.search.searchBar.text copy] ?: @"";
    NSInteger scope = self.search.searchBar.selectedScopeButtonIndex;
    NSArray<RYGRuntimeEntry *> *all = [self.allEntries copy] ?: @[];
    RYGRuntimeSurfaceSpec *spec = self.spec;
    NSUInteger generation = ++self.filterGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.filterGeneration) return;
        NSArray<NSString *> *groups = RYGFilterGroups(query);
        NSMutableDictionary<NSString *, NSMutableArray<RYGRuntimeEntry *> *> *buckets = [NSMutableDictionary dictionary];
        NSUInteger filteredCount = 0;
        NSUInteger active = 0;
        for (RYGRuntimeEntry *entry in all) {
            if (!RYGScopeMatches(entry, (RYGLiveScope)scope)) continue;
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@",
                entry.imageName ?: @"", entry.imagePath ?: @"", entry.runtimeFamily ?: @"",
                entry.runtimeSubcategory ?: @"", entry.className ?: @"", entry.selectorName ?: @"",
                entry.typeName ?: @"", entry.classMethod ? @"class" : @"instance"];
            if (!RYGEntryMatchesGroups(haystack, groups)) continue;
            NSString *section = RYGSectionForEntryWithSpec(entry, spec);
            if (!buckets[section]) buckets[section] = [NSMutableArray array];
            [buckets[section] addObject:entry];
            filteredCount++;
            if (RYGRuntimeValueHasOverride(entry.className, entry.selectorName, entry.classMethod)) active++;
        }
        NSArray<NSString *> *keys = [buckets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || generation != self.filterGeneration) return;
            self.sectionKeys = keys ?: @[];
            self.sections = buckets ?: @{};
            NSString *base = [NSString stringWithFormat:@"%@ (%lu)", spec.title ?: @"Runtime", (unsigned long)filteredCount];
            self.title = active ? [base stringByAppendingFormat:@" · %lu active", (unsigned long)active] : base;
            self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
            [self.tableView reloadData];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
    [self scheduleFilterWithDelay:0.11];
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    (void)searchBar; (void)selectedScope;
    [self scheduleFilterWithDelay:0.0];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return (NSInteger)self.sectionKeys.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.sectionKeys.count) return 0;
    return (NSInteger)self.sections[self.sectionKeys[(NSUInteger)section]].count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section < 0 || section >= (NSInteger)self.sectionKeys.count) return nil;
    NSString *key = self.sectionKeys[(NSUInteger)section];
    return [NSString stringWithFormat:@"%@ (%lu)", key, (unsigned long)self.sections[key].count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section != (NSInteger)self.sectionKeys.count - 1) return nil;
    return @"Loaded-runtime snapshot. BOOL, signed/unsigned integers, float/double and Foundation object getters keep their exact Objective-C return ABI. Overrides persist first; failed installs remain pending for Apply/retry.";
}

- (RYGRuntimeEntry *)entryAtIndexPath:(NSIndexPath *)indexPath {
    if (!indexPath || indexPath.section >= (NSInteger)self.sectionKeys.count) return nil;
    NSArray *rows = self.sections[self.sectionKeys[(NSUInteger)indexPath.section]];
    if (indexPath.row >= (NSInteger)rows.count) return nil;
    return rows[(NSUInteger)indexPath.row];
}

- (id)receiverForEntry:(RYGRuntimeEntry *)entry {
    if (!entry || entry.classMethod) return nil;
    Class cls = NSClassFromString(entry.className) ?: objc_getClass(entry.className.UTF8String);
    SEL selector = NSSelectorFromString(entry.selectorName);
    if (!cls || !selector) return nil;

    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", entry.className ?: @"", entry.selectorName ?: @""];
    id cached = [self.receiverCache objectForKey:cacheKey];
    if (RYGExactReceiver(cached, cls, selector)) return cached;

    id receiver = RYGObservedReceiver(entry);
    if (!receiver) receiver = RYGSharedReceiver(cls, selector);
    if (!receiver) {
        UIApplication *application = UIApplication.sharedApplication;
        if (RYGExactReceiver(application.delegate, cls, selector)) receiver = application.delegate;
        if (!receiver) {
            for (UIWindow *window in application.windows) {
                if (RYGExactReceiver(window, cls, selector)) { receiver = window; break; }
                receiver = RYGFindInControllerTree(window.rootViewController, cls, selector);
                if (receiver) break;
            }
        }
    }
    if (receiver) {
        [self.receiverCache setObject:receiver forKey:cacheKey];
        return receiver;
    }

    RYGInstallReceiverProbe(entry);
    return nil;
}

- (NSString *)currentForEntry:(RYGRuntimeEntry *)entry raw:(id *)raw {
    id receiver = entry.classMethod ? nil : [self receiverForEntry:entry];
    if (!entry.classMethod && !receiver) {
        if (raw) *raw = nil;
        return @"awaiting live instance · pass-through probe armed";
    }
    return RYGRuntimeValueRead(entry.className, entry.selectorName, entry.classMethod, receiver, raw);
}

static NSString *RYGCompactValue(id value, NSString *fallback) {
    if (!value) return fallback.length ? fallback : @"nil";
    NSString *text = [value description] ?: @"?";
    text = [[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    if (text.length > 84) text = [[text substringToIndex:84] stringByAppendingString:@"…"];
    return text;
}

- (UITextField *)inlineFieldForEntry:(RYGRuntimeEntry *)entry value:(id)value {
    BOOL floating = RYGRuntimeValueTypeIsFloatingPoint(entry.typeCode);
    BOOL integer = RYGRuntimeValueTypeIsSignedInteger(entry.typeCode) || RYGRuntimeValueTypeIsUnsignedInteger(entry.typeCode);
    CGFloat width = RYGRuntimeValueTypeIsObject(entry.typeCode) ? 108.0 : 100.0;
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, width, 31.0)];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    field.textAlignment = NSTextAlignmentRight;
    field.adjustsFontSizeToFitWidth = YES;
    field.minimumFontSize = 9.5;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.returnKeyType = UIReturnKeyDone;
    field.keyboardType = floating ? UIKeyboardTypeDecimalPad : (integer ? UIKeyboardTypeNumbersAndPunctuation : UIKeyboardTypeDefault);
    field.placeholder = floating ? @"decimal" : (integer ? @"integer" : @"text");
    field.text = value ? [value description] : @"";
    field.delegate = self;
    objc_setAssociatedObject(field, kRYGSurfaceEntryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [field addTarget:self action:@selector(inlineFieldCommit:) forControlEvents:UIControlEventEditingDidEnd];
    return field;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"RYGWATFastTypedRuntimeCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];

    RYGRuntimeEntry *entry = [self entryAtIndexPath:indexPath];
    cell.textLabel.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.textLabel.minimumScaleFactor = 0.62;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:10.25 weight:UIFontWeightRegular];
    cell.detailTextLabel.numberOfLines = 1;
    cell.detailTextLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.minimumScaleFactor = 0.70;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (!entry) return cell;

    id raw = nil;
    NSString *current = [self currentForEntry:entry raw:&raw];
    BOOL overridden = RYGRuntimeValueHasOverride(entry.className, entry.selectorName, entry.classMethod);
    BOOL installed = overridden && RYGRuntimeValueHookIsInstalled(entry.className, entry.selectorName, entry.classMethod);
    id forced = overridden ? RYGRuntimeValueOverride(entry.className, entry.selectorName, entry.classMethod) : nil;
    id effective = overridden ? forced : raw;
    NSString *state = overridden ? (installed ? @"override" : @"pending") : @"original";

    cell.textLabel.text = entry.selectorName ?: entry.displayName ?: @"?";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@ · %@",
        entry.className ?: @"runtime",
        entry.typeName.length ? entry.typeName : entry.typeCode,
        RYGCompactValue(effective, current), state];
    cell.detailTextLabel.textColor = overridden ? (installed ? UIColor.systemCyanColor : UIColor.systemOrangeColor) : UIColor.secondaryLabelColor;

    if (RYGRuntimeValueTypeIsBoolean(entry.typeCode)) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = effective && [effective respondsToSelector:@selector(boolValue)] ? [effective boolValue] : NO;
        toggle.onTintColor = overridden ? (installed ? UIColor.systemCyanColor : UIColor.systemOrangeColor) : UIColor.systemGreenColor;
        toggle.transform = CGAffineTransformMakeTranslation(5.0, 0.0);
        objc_setAssociatedObject(toggle, kRYGSurfaceEntryKey, entry, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(inlineSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (RYGRuntimeValueTypeIsSignedInteger(entry.typeCode) || RYGRuntimeValueTypeIsUnsignedInteger(entry.typeCode) ||
               RYGRuntimeValueTypeIsFloatingPoint(entry.typeCode) ||
               (RYGRuntimeValueTypeIsObject(entry.typeCode) && [effective isKindOfClass:NSString.class] && [(NSString *)effective length] <= 180)) {
        UITextField *field = [self inlineFieldForEntry:entry value:effective];
        field.textColor = overridden ? (installed ? UIColor.systemCyanColor : UIColor.systemOrangeColor) : UIColor.labelColor;
        cell.accessoryView = field;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    UILongPressGestureRecognizer *press = objc_getAssociatedObject(cell, kRYGSurfaceLongPressKey);
    if (!press) {
        press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressRow:)];
        press.minimumPressDuration = 0.45;
        [cell addGestureRecognizer:press];
        objc_setAssociatedObject(cell, kRYGSurfaceLongPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cell;
}

- (void)inlineSwitchChanged:(UISwitch *)sender {
    RYGRuntimeEntry *entry = objc_getAssociatedObject(sender, kRYGSurfaceEntryKey);
    if (!entry) return;
    RYGRuntimeValueSetOverride(entry.className, entry.selectorName, entry.classMethod, entry.typeCode, @(sender.isOn));
    (void)RYGRuntimeValueInstallHook(entry.className, entry.selectorName, entry.classMethod, entry.typeCode);
    UITableViewCell *cell = nil; for (UIView *v = sender; v; v = v.superview) if ([v isKindOfClass:UITableViewCell.class]) { cell = (UITableViewCell *)v; break; }
    NSIndexPath *path = cell ? [self.tableView indexPathForCell:cell] : nil;
    if (path) [self.tableView reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone];
}

static id RYGInlineParsedValue(RYGRuntimeEntry *entry, NSString *text, BOOL *valid) {
    if (valid) *valid = NO;
    if (!entry) return nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (RYGRuntimeValueTypeIsSignedInteger(entry.typeCode)) {
        const char *start = trimmed.UTF8String ?: ""; char *end = NULL; long long value = strtoll(start, &end, 0);
        if (end && end != start && *end == '\0') { if (valid) *valid = YES; return @(value); }
    } else if (RYGRuntimeValueTypeIsUnsignedInteger(entry.typeCode)) {
        if ([trimmed hasPrefix:@"-"]) return nil;
        const char *start = trimmed.UTF8String ?: ""; char *end = NULL; unsigned long long value = strtoull(start, &end, 0);
        if (end && end != start && *end == '\0') { if (valid) *valid = YES; return @(value); }
    } else if (RYGRuntimeValueTypeIsFloatingPoint(entry.typeCode)) {
        NSString *normalized = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];
        const char *start = normalized.UTF8String ?: ""; char *end = NULL; double value = strtod(start, &end);
        if (end && end != start && *end == '\0') { if (valid) *valid = YES; return @(value); }
    } else if (RYGRuntimeValueTypeIsObject(entry.typeCode)) {
        if (valid) *valid = YES;
        return text ?: @"";
    }
    return nil;
}

- (void)inlineFieldCommit:(UITextField *)field {
    RYGRuntimeEntry *entry = objc_getAssociatedObject(field, kRYGSurfaceEntryKey);
    BOOL valid = NO;
    id value = RYGInlineParsedValue(entry, field.text ?: @"", &valid);
    if (!valid || !value) { field.textColor = UIColor.systemRedColor; return; }
    RYGRuntimeValueSetOverride(entry.className, entry.selectorName, entry.classMethod, entry.typeCode, value);
    BOOL installed = RYGRuntimeValueInstallHook(entry.className, entry.selectorName, entry.classMethod, entry.typeCode);
    field.textColor = installed ? UIColor.systemCyanColor : UIColor.systemOrangeColor;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)presentEditorForEntry:(RYGRuntimeEntry *)entry fromView:(UIView *)sourceView {
    if (!entry) return;
    id raw = nil;
    NSString *current = [self currentForEntry:entry raw:&raw];
    __weak typeof(self) weakSelf = self;
    RYGPresentRuntimeValueEditor(self, sourceView,
        entry.className, entry.selectorName, entry.classMethod, entry.typeCode,
        current, raw, ^{
            __strong typeof(weakSelf) self = weakSelf;
            [self scheduleFilterWithDelay:0.0];
        });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self presentEditorForEntry:[self entryAtIndexPath:indexPath] fromView:cell];
}

- (void)longPressRow:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UITableViewCell *cell = (UITableViewCell *)gesture.view;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    if (indexPath) [self presentEditorForEntry:[self entryAtIndexPath:indexPath] fromView:cell];
}

- (void)applyAllOverrides {
    NSUInteger active = 0;
    NSUInteger installed = 0;
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (RYGRuntimeEntry *entry in self.allEntries) {
        NSString *uid = RYGRuntimeValueUID(entry.className, entry.selectorName, entry.classMethod);
        if (!uid.length || [seen containsObject:uid]) continue;
        [seen addObject:uid];
        if (!RYGRuntimeValueHasOverride(entry.className, entry.selectorName, entry.classMethod)) continue;
        active++;
        if (RYGRuntimeValueInstallHook(entry.className, entry.selectorName, entry.classMethod, entry.typeCode)) installed++;
    }
    if (!self.allEntries.count) {
        active = RYGRuntimeValueAllOverrideSpecs().count;
        installed = RYGRuntimeValueReinstallPersistedHooks();
    }
    NSUInteger pending = active >= installed ? active - installed : 0;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Apply Runtime"
                                                                   message:[NSString stringWithFormat:@"Persisted overrides: %lu\nExact hooks installed/reapplied: %lu\nPending/failed: %lu",
                                                                            (unsigned long)active,
                                                                            (unsigned long)installed,
                                                                            (unsigned long)pending]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    [self scheduleFilterWithDelay:0.0];
}

@end
