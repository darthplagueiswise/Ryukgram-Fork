// SCIMCBrowser.m — RyukGram-Fork
#import "SCIMCBrowser.h"
#import "../../Localization/SCILocalization.h"
#import "../../Features/Dogfooding/SCIDogfoodObjectRuntime.h"
#import <objc/message.h>

#pragma mark - helpers

// lowercase + strip '_' and whitespace, so "internal settings" matches
// "is_internal_settings_enabled".
static NSString *SCIMCNorm(NSString *s) {
    NSMutableString *m = [s.lowercaseString mutableCopy];
    [m replaceOccurrencesOfString:@"_" withString:@"" options:0 range:NSMakeRange(0, m.length)];
    NSCharacterSet *ws = NSCharacterSet.whitespaceCharacterSet;
    NSMutableString *o = [NSMutableString stringWithCapacity:m.length];
    for (NSUInteger i = 0; i < m.length; i++) {
        unichar c = [m characterAtIndex:i];
        if (![ws characterIsMember:c]) [o appendFormat:@"%C", c];
    }
    return o;
}

#pragma mark - Store

@interface SCIMCOverrideStore () {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_ov;   // "<cid>:<name>" -> lines
    NSMutableDictionary<NSNumber *, NSString *> *_names;
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSString *> *> *_params;
    NSMutableDictionary<NSNumber *, NSString *> *_norm;                   // cid -> normalized haystack
    NSArray<NSNumber *> *_ids;
}
@end

@implementation SCIMCOverrideStore

+ (instancetype)shared {
    static SCIMCOverrideStore *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [SCIMCOverrideStore new]; [s reload]; });
    return s;
}

- (NSArray<NSURL *> *)candidateRoots {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *roots = [NSMutableArray array];
    // IG's per-account data lives in the app's OWN Documents (same base
    // SCIDeviceIdentity/wipeDocuments uses). App-group containers are fallbacks.
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length)
        [roots addObject:[[NSURL fileURLWithPath:docs] URLByAppendingPathComponent:@"mobileconfig"]];
    for (NSString *g in @[@"group.com.burbn.instagram", @"group.com.burbn.family"]) {
        NSURL *c = [fm containerURLForSecurityApplicationGroupIdentifier:g];
        if (c) [roots addObject:[[c URLByAppendingPathComponent:@"Documents"] URLByAppendingPathComponent:@"mobileconfig"]];
    }
    return roots;
}

- (NSURL *)mobileconfigRoot {
    NSURL *r = self.candidateRoots.firstObject;
    if (r) [NSFileManager.defaultManager createDirectoryAtURL:r withIntermediateDirectories:YES attributes:nil error:nil];
    return r;
}

// Resolve <root>/<userid>.data. Uses the live IGUserSession's id; searches every
// candidate root for an existing <uid>.data (so a manually-placed file is found);
// creates <uid>.data in the primary root only if nothing exists yet.
- (NSURL *)userDataDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *uid = [self currentIGUserID];
    NSArray<NSURL *> *roots = self.candidateRoots;

    if (uid.length)
        for (NSURL *root in roots) {
            NSURL *d = [root URLByAppendingPathComponent:[uid stringByAppendingString:@".data"]];
            if ([fm fileExistsAtPath:d.path]) return d;
        }
    // any *.data already holding our files
    for (NSURL *root in roots)
        for (NSURL *u in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil]) {
            if (![u.lastPathComponent hasSuffix:@".data"]) continue;
            if ([fm fileExistsAtPath:[u URLByAppendingPathComponent:@"mc_overrides.json"].path] ||
                [fm fileExistsAtPath:[u URLByAppendingPathComponent:@"id_name_mapping.json"].path])
                return u;
        }
    // any *.data at all (most recently modified)
    for (NSURL *root in roots) {
        NSURL *best = nil; NSDate *bd = nil;
        for (NSURL *u in [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:0 error:nil]) {
            if (![u.lastPathComponent hasSuffix:@".data"]) continue;
            NSDate *d = nil; [u getResourceValue:&d forKey:NSURLContentModificationDateKey error:nil];
            if (!best || (d && [d compare:bd] == NSOrderedDescending)) { best = u; bd = d ?: NSDate.date; }
        }
        if (best) return best;
    }
    NSURL *primary = roots.firstObject;
    NSString *folder = uid.length ? [uid stringByAppendingString:@".data"] : @"shared.data";
    NSURL *d = [primary URLByAppendingPathComponent:folder];
    [fm createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

// Current user id from the live IGUserSession captured by the dogfood runtime.
- (NSString *)currentIGUserID {
    @try {
        Class dr = NSClassFromString(@"SCIDogfoodObjectRuntime");
        id session = nil;
        if ([dr respondsToSelector:@selector(liveInstanceOfClassNameContaining:)])
            session = ((id(*)(id, SEL, id))objc_msgSend)(dr, @selector(liveInstanceOfClassNameContaining:), @"IGUserSession");
        NSArray<NSString *> *keys = @[@"instagramUserID", @"userID", @"loggedInUserId", @"pk"];
        for (NSString *k in keys) {
            @try {
                id v = [session valueForKey:k];
                if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
                if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
            } @catch (__unused id e) {}
        }
        @try {
            id user = [session valueForKey:@"user"] ?: [session valueForKey:@"currentUser"];
            for (NSString *k in keys) {
                @try {
                    id v = [user valueForKey:k];
                    if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
                    if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
                } @catch (__unused id e) {}
            }
        } @catch (__unused id e) {}
    } @catch (__unused NSException *e) {}
    return nil;
}

- (void)reload {
    _ov = [NSMutableDictionary dictionary];
    _names = [NSMutableDictionary dictionary];
    _params = [NSMutableDictionary dictionary];
    _norm = [NSMutableDictionary dictionary];

    NSURL *dir = self.userDataDir;
    NSURL *root = self.mobileconfigRoot;

    // overrides (from the user data dir)
    NSData *od = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"mc_overrides.json"]];
    if (od) {
        id j = [NSJSONSerialization JSONObjectWithData:od options:0 error:nil];
        if ([j isKindOfClass:NSDictionary.class])
            [(NSDictionary *)j enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *st) {
                if ([k isEqualToString:@"_qe_overrides_"]) return;
                if ([v isKindOfClass:NSArray.class]) _ov[k] = [(NSArray *)v mutableCopy];
            }];
    }

    // mapping: user data dir first, then root, then bundle
    NSData *md = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"id_name_mapping.json"]];
    if (!md) md = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:@"id_name_mapping.json"]];
    if (!md) {
        NSString *bp = [SCILocalizationBundle() pathForResource:@"id_name_mapping" ofType:@"json"];
        if (bp) md = [NSData dataWithContentsOfFile:bp];
    }
    // Seed the mapping into the user data dir so Instagram's own internal editor
    // can read names too (only if missing there).
    if (md) {
        NSURL *seed = [dir URLByAppendingPathComponent:@"id_name_mapping.json"];
        if (![NSFileManager.defaultManager fileExistsAtPath:seed.path])
            [md writeToURL:seed options:NSDataWritingAtomic error:nil];
    }
    if (md) {
        id j = [NSJSONSerialization JSONObjectWithData:md options:0 error:nil];
        if ([j isKindOfClass:NSArray.class])
            for (NSString *e in (NSArray *)j) {
                if (![e isKindOfClass:NSString.class]) continue;
                NSArray<NSString *> *p = [e componentsSeparatedByString:@":"];
                if (p.count < 2) continue;
                NSInteger cid = [p[0] integerValue];
                _names[@(cid)] = p[1];
                NSMutableDictionary *pm = [NSMutableDictionary dictionary];
                for (NSUInteger i = 2; i + 1 < p.count; i += 2)
                    pm[@([p[i] integerValue])] = p[i + 1];
                _params[@(cid)] = pm;
            }
    }
    _ids = [_names.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSNumber *> *)configIDs { return _ids ?: @[]; }
- (NSString *)nameForConfig:(NSInteger)cid { return _names[@(cid)] ?: [NSString stringWithFormat:@"config %ld", (long)cid]; }
- (NSDictionary *)paramsForConfig:(NSInteger)cid { return _params[@(cid)] ?: @{}; }
- (NSString *)nameForConfig:(NSInteger)cid param:(NSInteger)idx { return _params[@(cid)][@(idx)] ?: [NSString stringWithFormat:@"param %ld", (long)idx]; }

- (NSString *)normForConfig:(NSNumber *)cid {
    NSString *n = _norm[cid];
    if (n) return n;
    NSMutableString *hay = [NSMutableString stringWithFormat:@"%@ %@", [self nameForConfig:cid.integerValue], cid];
    for (NSString *pn in [_params[cid] allValues]) [hay appendFormat:@" %@", pn];
    n = SCIMCNorm(hay); _norm[cid] = n; return n;
}

- (NSArray<NSNumber *> *)configIDsMatching:(NSString *)q {
    if (q.length == 0) return self.configIDs;
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *t in [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        NSString *nt = SCIMCNorm(t);
        if (nt.length) [tokens addObject:nt];
    }
    if (tokens.count == 0) return self.configIDs;
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    for (NSNumber *cid in _ids) {
        NSString *hay = [self normForConfig:cid];
        BOOL all = YES;
        for (NSString *t in tokens) { if (![hay containsString:t]) { all = NO; break; } }
        if (all) [out addObject:cid];
    }
    return out;
}

- (NSString *)keyForConfig:(NSInteger)cid {
    NSString *nm = _names[@(cid)];
    return nm.length ? [NSString stringWithFormat:@"%ld:%@", (long)cid, nm] : [NSString stringWithFormat:@"%ld:", (long)cid];
}

- (nullable NSString *)stringValueForConfig:(NSInteger)cid param:(NSInteger)idx {
    NSArray *list = _ov[[self keyForConfig:cid]];
    for (NSString *line in list) {
        NSArray<NSString *> *seg = [line componentsSeparatedByString:@":"];
        if (seg.count >= 3 && [[seg[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] integerValue] == idx)
            return [seg.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    return nil;
}

- (SCIMCOverrideState)stateForConfig:(NSInteger)cid param:(NSInteger)idx {
    NSString *v = [self stringValueForConfig:cid param:idx];
    if (!v) return SCIMCOverrideSYS;
    return [v isEqualToString:@"true"] ? SCIMCOverrideON : SCIMCOverrideOFF;
}

- (void)setState:(SCIMCOverrideState)state forConfig:(NSInteger)cid param:(NSInteger)idx {
    NSString *key = [self keyForConfig:cid];
    NSMutableArray *list = _ov[key] ?: [NSMutableArray array];
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *line in list) {
        NSInteger li = [[[line componentsSeparatedByString:@":"][0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] integerValue];
        if (li != idx) [keep addObject:line];
    }
    if (state != SCIMCOverrideSYS) {
        NSString *pn = [self nameForConfig:cid param:idx];
        [keep addObject:[NSString stringWithFormat:@"%ld: %@: %@", (long)idx, pn, state == SCIMCOverrideON ? @"true" : @"false"]];
    }
    // descending by index
    [keep sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ia = [[a componentsSeparatedByString:@":"][0] integerValue];
        NSInteger ib = [[b componentsSeparatedByString:@":"][0] integerValue];
        return ia < ib ? NSOrderedDescending : (ia > ib ? NSOrderedAscending : NSOrderedSame);
    }];
    if (keep.count) _ov[key] = keep; else [_ov removeObjectForKey:key];
}

// Ordered write, _qe_overrides_ last, compact — matches the internal file exactly.
- (BOOL)save:(NSError **)error {
    NSMutableString *json = [NSMutableString stringWithString:@"{"];
    NSArray *keys = [_ov.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [@([a integerValue]) compare:@([b integerValue])];
    }];
    BOOL first = YES;
    for (NSString *k in keys) {
        if (!first) [json appendString:@","];
        first = NO;
        NSData *kd = [NSJSONSerialization dataWithJSONObject:@[k] options:0 error:nil];
        NSString *ks = [[NSString alloc] initWithData:kd encoding:NSUTF8StringEncoding];
        ks = [ks substringWithRange:NSMakeRange(1, ks.length - 2)]; // strip [ ]
        NSData *vd = [NSJSONSerialization dataWithJSONObject:_ov[k] options:0 error:nil];
        NSString *vs = [[NSString alloc] initWithData:vd encoding:NSUTF8StringEncoding];
        [json appendFormat:@"%@:%@", ks, vs];
    }
    if (!first) [json appendString:@","];
    [json appendString:@"\"_qe_overrides_\":[]}"];

    NSURL *dst = [self.userDataDir URLByAppendingPathComponent:@"mc_overrides.json"];
    return [[json dataUsingEncoding:NSUTF8StringEncoding] writeToURL:dst options:NSDataWritingAtomic error:error];
}

- (BOOL)deployBundledMappingOverwrite:(NSError **)error {
    NSString *p = [SCILocalizationBundle() pathForResource:@"id_name_mapping" ofType:@"json"];
    if (!p) {
        if (error) *error = [NSError errorWithDomain:@"SCIMC" code:404 userInfo:@{NSLocalizedDescriptionKey:@"bundled id_name_mapping.json not found"}];
        return NO;
    }
    NSData *d = [NSData dataWithContentsOfFile:p];
    if (!d) return NO;
    BOOL ok = [d writeToURL:[self.userDataDir URLByAppendingPathComponent:@"id_name_mapping.json"] options:NSDataWritingAtomic error:error];
    [self reload];
    return ok;
}

- (void)applyInternalPreset {
    NSDictionary<NSString *, NSNumber *> *preset = @{
        @"56474:0":@(SCIMCOverrideON), @"56474:1":@(SCIMCOverrideON), @"58792:0":@(SCIMCOverrideON),
        @"90775:1":@(SCIMCOverrideON), @"87318:0":@(SCIMCOverrideON), @"57176:0":@(SCIMCOverrideON),
        @"107035:0":@(SCIMCOverrideON), @"107711:0":@(SCIMCOverrideON), @"121139:0":@(SCIMCOverrideON),
        @"121139:1":@(SCIMCOverrideON), @"121139:2":@(SCIMCOverrideON), @"121139:3":@(SCIMCOverrideON),
        @"90631:0":@(SCIMCOverrideON), @"90631:2":@(SCIMCOverrideON), @"90631:3":@(SCIMCOverrideON),
    };
    [preset enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSNumber *st, BOOL *stop) {
        NSArray *p = [k componentsSeparatedByString:@":"];
        [self setState:(SCIMCOverrideState)st.integerValue forConfig:[p[0] integerValue] param:[p[1] integerValue]];
    }];
}
@end

#pragma mark - Root browser (plain UITableView)

@interface SCIMCBrowserListController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *search;
@property (nonatomic, strong) NSArray<NSNumber *> *rows;
@end

@implementation SCIMCBrowserListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig Overrides";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [[SCIMCOverrideStore shared] reload];

    self.search = [UISearchBar new];
    self.search.placeholder = @"Search config / param (e.g. internal settings)";
    self.search.searchBarStyle = UISearchBarStyleMinimal;
    self.search.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.search.autocorrectionType = UITextAutocorrectionTypeNo;
    self.search.returnKeyType = UIReturnKeyDone;
    self.search.delegate = self;
    self.search.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.search];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 48;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;   // dismiss keyboard on scroll
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"c"];
    [self.view addSubview:self.table];

    UIBarButtonItem *preset = [[UIBarButtonItem alloc] initWithTitle:@"Preset" style:UIBarButtonItemStylePlain target:self action:@selector(applyPreset)];
    UIBarButtonItem *deploy = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.down.doc"] style:UIBarButtonItemStylePlain target:self action:@selector(deployMapping)];
    UIBarButtonItem *info = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showInfo)];
    self.navigationItem.rightBarButtonItems = @[preset, deploy, info];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.search.topAnchor constraintEqualToAnchor:g.topAnchor],
        [self.search.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.search.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:self.search.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:g.bottomAnchor],
    ]];
    self.rows = [SCIMCOverrideStore.shared configIDs];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.table reloadData]; }

- (void)showInfo {
    SCIMCOverrideStore *st = SCIMCOverrideStore.shared;
    NSString *uid = [st valueForKey:@"currentIGUserID"] ?: @"(unresolved — open an account screen once)";
    NSURL *dir = st.userDataDir;
    BOOL hasOv = [NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"mc_overrides.json"].path];
    BOOL hasMap = [NSFileManager.defaultManager fileExistsAtPath:[dir URLByAppendingPathComponent:@"id_name_mapping.json"].path];
    NSString *msg = [NSString stringWithFormat:@"user id: %@\n\ndata dir:\n%@\n\nconfigs loaded: %lu\nmc_overrides.json here: %@\nid_name_mapping.json here: %@",
        uid, dir.path, (unsigned long)st.configIDs.count, hasOv ? @"yes" : @"NO", hasMap ? @"yes" : @"NO"];
    [self toast:msg];
}

- (void)applyPreset {
    [SCIMCOverrideStore.shared applyInternalPreset];
    NSError *e = nil; BOOL ok = [SCIMCOverrideStore.shared save:&e];
    [self toast:ok ? @"Internal preset applied. Restart Instagram." : e.localizedDescription];
    [self.table reloadData];
}
- (void)deployMapping {
    NSError *e = nil; BOOL ok = [SCIMCOverrideStore.shared deployBundledMappingOverwrite:&e];
    self.rows = [SCIMCOverrideStore.shared configIDsMatching:self.search.text];
    [self.table reloadData];
    [self toast:ok ? @"Mapping deployed. Names refreshed." : e.localizedDescription];
}
- (void)toast:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

// search: token semantics + keyboard control
- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text {
    self.rows = [SCIMCOverrideStore.shared configIDsMatching:text];
    [self.table reloadData];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }
- (void)searchBarTextDidEndEditing:(UISearchBar *)sb { [sb resignFirstResponder]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    NSInteger cid = self.rows[ip.row].integerValue;
    cell.textLabel.text = [SCIMCOverrideStore.shared nameForConfig:cid];
    cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];   // smaller
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld · %lu params", (long)cid, (unsigned long)[SCIMCOverrideStore.shared paramsForConfig:cid].count];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [self.search resignFirstResponder];
    Class d = NSClassFromString(@"SCIMCConfigDetailController");
    UIViewController *vc = [d new];
    [vc setValue:self.rows[ip.row] forKey:@"cid"];
    [self.navigationController pushViewController:vc animated:YES];
}
@end

#pragma mark - Per-config detail (3-state per param)

@interface SCIMCConfigDetailController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSNumber *cid;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<NSNumber *> *idxs;
@end

@implementation SCIMCConfigDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSInteger cid = self.cid.integerValue;
    self.title = [SCIMCOverrideStore.shared nameForConfig:cid];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.dataSource = self; self.table.delegate = self;
    self.table.rowHeight = 54;
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"p"];
    [self.view addSubview:self.table];
    self.idxs = [[SCIMCOverrideStore.shared paramsForConfig:cid].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.idxs.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"p"];
    NSInteger cid = self.cid.integerValue, idx = self.idxs[ip.row].integerValue;
    cell.textLabel.text = [SCIMCOverrideStore.shared nameForConfig:cid param:idx];
    cell.textLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    cell.textLabel.numberOfLines = 1; cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"param %ld", (long)idx];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"SYS", @"OFF", @"ON"]];
    seg.selectedSegmentIndex = [SCIMCOverrideStore.shared stateForConfig:cid param:idx];
    seg.apportionsSegmentWidthsByContent = YES;
    UIFont *sf = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [seg setTitleTextAttributes:@{NSFontAttributeName:sf} forState:UIControlStateNormal];
    seg.tag = (cid << 16) | (idx & 0xFFFF);
    [seg addTarget:self action:@selector(segChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = seg;
    return cell;
}

- (void)segChanged:(UISegmentedControl *)seg {
    NSInteger cid = seg.tag >> 16, idx = seg.tag & 0xFFFF;
    [SCIMCOverrideStore.shared setState:(SCIMCOverrideState)seg.selectedSegmentIndex forConfig:cid param:idx];
    NSError *e = nil;
    if (![SCIMCOverrideStore.shared save:&e]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Save failed" message:e.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}
@end
