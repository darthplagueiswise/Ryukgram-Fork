// SCIMCBrowser.m — RyukGram-Fork
#import "SCIMCBrowser.h"
#import <Preferences/PSSpecifier.h>

#pragma mark - Store

@interface SCIMCOverrideStore () {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_overrides; // "<cid>:" -> ["<idx>: : val"]
    NSMutableDictionary<NSNumber *, NSString *> *_names;                        // cid -> config name
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSString *> *> *_params; // cid -> {idx->name}
    NSArray<NSNumber *> *_sortedIDs;
}
@end

@implementation SCIMCOverrideStore

+ (instancetype)shared {
    static SCIMCOverrideStore *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [SCIMCOverrideStore new]; [s reload]; });
    return s;
}

// Resolve <AppGroup>/Documents/mobileconfig/, creating it if needed.
- (NSURL *)mobileconfigDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = nil;
    NSArray *candidates = @[ SCI_APPGROUP, @"group.com.instagram.instagram", @"group.com.burbn.instagram" ];
    for (NSString *g in candidates) {
        NSURL *c = [fm containerURLForSecurityApplicationGroupIdentifier:g];
        if (c) { base = c; break; }
    }
    if (!base) // fallback: app's own Documents
        base = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject].URLByDeletingLastPathComponent;
    NSURL *dir = [[base URLByAppendingPathComponent:@"Documents"] URLByAppendingPathComponent:@"mobileconfig"];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

// Write/overwrite id_name_mapping.json in the mobileconfig dir.
- (BOOL)writeMappingData:(NSData *)data error:(NSError **)error {
    NSURL *dst = [self.mobileconfigDir URLByAppendingPathComponent:@"id_name_mapping.json"];
    return [data writeToURL:dst options:NSDataWritingAtomic error:error];
}

// Copy bundled mapping (packaged with the tweak) into place, overwriting.
- (BOOL)deployBundledMappingOverwrite:(NSError **)error {
    NSString *p = [[NSBundle mainBundle] pathForResource:@"id_name_mapping" ofType:@"json"];
    if (!p) // also try a mobileconfig subdir inside the bundle
        p = [[NSBundle mainBundle] pathForResource:@"id_name_mapping" ofType:@"json" inDirectory:@"mobileconfig"];
    if (!p) { if (error) *error = [NSError errorWithDomain:@"SCIMC" code:404
        userInfo:@{NSLocalizedDescriptionKey:@"bundled id_name_mapping.json not found"}]; return NO; }
    NSData *d = [NSData dataWithContentsOfFile:p];
    return d ? [self writeMappingData:d error:error] : NO;
}

// If the mapping is missing or a dummy (<10KB, mirrors Piko's size guard), seed it
// from the tweak bundle so names show up on first run.
- (void)bootstrapMappingIfNeeded {
    NSURL *m = [self.mobileconfigDir URLByAppendingPathComponent:@"id_name_mapping.json"];
    NSNumber *size = nil; [m getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (!size || size.longLongValue < 10 * 1024)
        [self deployBundledMappingOverwrite:nil];
}

- (void)reload {
    _overrides = [NSMutableDictionary dictionary];
    _names = [NSMutableDictionary dictionary];
    _params = [NSMutableDictionary dictionary];

    [self bootstrapMappingIfNeeded];
    NSURL *dir = self.mobileconfigDir;

    // 1) current overrides
    NSData *od = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"mc_overrides.json"]];
    if (od) {
        id j = [NSJSONSerialization JSONObjectWithData:od options:0 error:nil];
        if ([j isKindOfClass:NSDictionary.class]) {
            [(NSDictionary *)j enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
                if ([k isEqualToString:@"_qe_overrides_"]) return;
                if ([v isKindOfClass:NSArray.class])
                    _overrides[k] = [(NSArray *)v mutableCopy];
            }];
        }
    }

    // 2) id-name mapping: JSON array of "cid:cfgname:idx:pname:idx:pname:..."
    NSData *md = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:@"id_name_mapping.json"]];
    if (md) {
        id j = [NSJSONSerialization JSONObjectWithData:md options:0 error:nil];
        if ([j isKindOfClass:NSArray.class]) {
            for (NSString *entry in (NSArray *)j) {
                if (![entry isKindOfClass:NSString.class]) continue;
                NSArray<NSString *> *p = [entry componentsSeparatedByString:@":"];
                if (p.count < 2) continue;
                NSInteger cid = p[0].integerValue;
                _names[@(cid)] = p[1];
                NSMutableDictionary *pm = [NSMutableDictionary dictionary];
                for (NSUInteger i = 2; i + 1 < p.count; i += 2)
                    pm[@(p[i].integerValue)] = p[i + 1];
                _params[@(cid)] = pm;
            }
        }
    }
    _sortedIDs = [_names.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSNumber *> *)configIDs { return _sortedIDs ?: @[]; }
- (NSString *)nameForConfig:(NSInteger)cid { return _names[@(cid)] ?: [NSString stringWithFormat:@"config %ld", (long)cid]; }
- (NSDictionary *)paramsForConfig:(NSInteger)cid { return _params[@(cid)] ?: @{}; }

- (NSArray<NSNumber *> *)configIDsMatching:(NSString *)q {
    if (q.length == 0) return self.configIDs;
    NSString *lq = q.lowercaseString;
    NSMutableArray *out = [NSMutableArray array];
    for (NSNumber *cid in _sortedIDs) {
        if ([[self nameForConfig:cid.integerValue].lowercaseString containsString:lq] ||
            [cid.stringValue containsString:lq]) { [out addObject:cid]; continue; }
        for (NSString *pn in [_params[cid] allValues])
            if ([pn.lowercaseString containsString:lq]) { [out addObject:cid]; break; }
    }
    return out;
}

// override list line format:  "<idx>: : <value>"
- (nullable NSString *)overrideValueForConfig:(NSInteger)cid param:(NSInteger)idx {
    NSArray *list = _overrides[[NSString stringWithFormat:@"%ld:", (long)cid]];
    for (NSString *line in list) {
        NSArray *seg = [line componentsSeparatedByString:@":"];
        if (seg.count >= 3 && seg[0].integerValue == idx && [seg[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].integerValue == idx)
            return [seg[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
    return nil;
}

- (void)setOverrideValue:(nullable NSString *)value forConfig:(NSInteger)cid param:(NSInteger)idx {
    NSString *key = [NSString stringWithFormat:@"%ld:", (long)cid];
    NSMutableArray *list = _overrides[key];
    if (!list) { list = [NSMutableArray array]; _overrides[key] = list; }
    // remove existing line for idx
    NSMutableArray *keep = [NSMutableArray array];
    for (NSString *line in list) {
        NSArray *seg = [line componentsSeparatedByString:@":"];
        NSInteger li = seg.count ? [seg[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].integerValue : -1;
        if (li != idx) [keep addObject:line];
    }
    if (value) [keep addObject:[NSString stringWithFormat:@"%ld: : %@", (long)idx, value]];
    // keep descending by index (matches the user's file style)
    [keep sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ia = [a componentsSeparatedByString:@":"][0].integerValue;
        NSInteger ib = [b componentsSeparatedByString:@":"][0].integerValue;
        return (ia < ib) ? NSOrderedDescending : (ia > ib ? NSOrderedAscending : NSOrderedSame);
    }];
    if (keep.count) _overrides[key] = keep; else [_overrides removeObjectForKey:key];
}

- (BOOL)save:(NSError **)error {
    // Build ordered dict; append _qe_overrides_ last, matching the app's file.
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [_overrides enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSArray *v, BOOL *s){ out[k] = v; }];
    out[@"_qe_overrides_"] = @[];
    NSData *data = [NSJSONSerialization dataWithJSONObject:out options:0 error:error];
    if (!data) return NO;
    NSURL *dst = [self.mobileconfigDir URLByAppendingPathComponent:@"mc_overrides.json"];
    return [data writeToURL:dst options:NSDataWritingAtomic error:error];
}

- (void)applyPreset:(NSDictionary<NSString *, NSArray<NSString *> *> *)preset {
    [preset enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<NSString *> *lines, BOOL *stop) {
        NSInteger cid = key.integerValue;
        for (NSString *line in lines) {
            NSArray *seg = [line componentsSeparatedByString:@":"];
            if (seg.count < 3) continue;
            NSInteger idx = seg[0].integerValue;
            NSString *val = [seg[2] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            [self setOverrideValue:val forConfig:cid param:idx];
        }
    }];
}

// The internal/dogfood/dev/qe/igplus delta (v439-validated). Kept inline so the
// browser has a one-tap "unlock internal" even before a mapping is present.
- (NSDictionary *)internalUnlockPreset {
    return @{
      @"36377:":@[@"13: : true"], @"49223:":@[@"39: : true"], @"50769:":@[@"41: : true"],
      @"55291:":@[@"23: : true"], @"56474:":@[@"1: : true",@"0: : true"], @"58377:":@[@"14: : true"],
      @"59913:":@[@"0: : true"], @"61771:":@[@"4: : true"], @"62183:":@[@"36: : true"],
      @"69239:":@[@"66: : true"], @"74642:":@[@"8: : true"], @"75335:":@[@"9: : true",@"6: : true"],
      @"75726:":@[@"6: : true"], @"77305:":@[@"6: : true"], @"77429:":@[@"12: : true",@"8: : true"],
      @"77493:":@[@"3: : true"], @"78944:":@[@"9: : true"], @"78970:":@[@"22: : true"],
      @"80734:":@[@"23: : true"], @"80778:":@[@"22: : true"], @"81940:":@[@"70: : true"],
      @"82560:":@[@"14: : true"], @"82840:":@[@"4: : true"], @"82950:":@[@"78: : true",@"8: : true"],
      @"83598:":@[@"30: : true"], @"84046:":@[@"5: : true"], @"85119:":@[@"8: : true"],
      @"85292:":@[@"2: : true"], @"87707:":@[@"30: : true"], @"90017:":@[@"4: : true"],
      @"90631:":@[@"3: : true",@"2: : true",@"0: : true"], @"91290:":@[@"15: : true"],
      @"91689:":@[@"0: : true"], @"92764:":@[@"0: : true"], @"93536:":@[@"6: : true"],
      @"94098:":@[@"3: : true"], @"95994:":@[@"1: : true"], @"96260:":@[@"1: : true"],
      @"97127:":@[@"0: : true"], @"97242:":@[@"40: : true"], @"97656:":@[@"4: : true"],
      @"99456:":@[@"0: : true"], @"101583:":@[@"1: : true"], @"103620:":@[@"7: : true"],
      @"104898:":@[@"4: : true"], @"105366:":@[@"0: : true"], @"105830:":@[@"1: : true"],
      @"107003:":@[@"13: : true"], @"108555:":@[@"10: : true"], @"109075:":@[@"2: : true",@"0: : true"],
      @"109193:":@[@"14: : true"], @"117208:":@[@"2: : true"], @"117484:":@[@"1: : true"],
      @"118965:":@[@"0: : true"], @"123645:":@[@"1: : true"],
    };
}
@end

#pragma mark - Root browser

@implementation SCIMCBrowserListController {
    NSString *_query;
    UISearchBar *_search;
}

- (NSString *)title { return @"MobileConfig Overrides"; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [[SCIMCOverrideStore shared] reload];
    _search = [[UISearchBar alloc] init];
    _search.placeholder = @"Search config or param name";
    _search.delegate = (id<UISearchBarDelegate>)self;
    [_search sizeToFit];
    self.table.tableHeaderView = _search;
}

- (id)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *sp = [NSMutableArray array];
    SCIMCOverrideStore *store = SCIMCOverrideStore.shared;

    PSSpecifier *g0 = [PSSpecifier emptyGroupSpecifier]; [g0 setProperty:@"Presets" forKey:@"footerText"]; [sp addObject:g0];

    PSSpecifier *preset = [PSSpecifier preferenceSpecifierNamed:@"Enable Internal / Dogfood / Dev / QE / IGPlus"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    [preset setProperty:@YES forKey:@"enabled"]; preset->action = @selector(applyInternalPreset:);
    [sp addObject:preset];

    PSSpecifier *exp = [PSSpecifier preferenceSpecifierNamed:@"Export → mobileconfig/mc_overrides.json"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    exp->action = @selector(exportNow:); [sp addObject:exp];

    PSSpecifier *dep = [PSSpecifier preferenceSpecifierNamed:@"Deploy / overwrite id_name_mapping.json"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    dep->action = @selector(deployMapping:); [sp addObject:dep];

    NSArray<NSNumber *> *ids = [store configIDsMatching:_query];
    PSSpecifier *g1 = [PSSpecifier emptyGroupSpecifier];
    [g1 setProperty:[NSString stringWithFormat:@"%lu configs", (unsigned long)ids.count] forKey:@"footerText"];
    [sp addObject:g1];

    for (NSNumber *cid in ids) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:[store nameForConfig:cid.integerValue]
            target:self set:NULL get:NULL detail:SCIMCConfigDetailController.class cell:PSLinkCell edit:Nil];
        [row setProperty:cid forKey:@"sci_cid"];
        [row setProperty:cid.stringValue forKey:@"subtitle"];
        [sp addObject:row];
    }
    _specifiers = sp;
    return _specifiers;
}

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)text {
    _query = text; _specifiers = nil; [self reloadSpecifiers];
}

- (void)applyInternalPreset:(PSSpecifier *)s {
    SCIMCOverrideStore *st = SCIMCOverrideStore.shared;
    [st applyPreset:[st internalUnlockPreset]];
    NSError *e = nil; BOOL ok = [st save:&e];
    [self alert:ok ? @"Internal preset applied and exported. Restart Instagram." :
        [NSString stringWithFormat:@"Save failed: %@", e.localizedDescription]];
}

- (void)exportNow:(PSSpecifier *)s {
    NSError *e = nil; BOOL ok = [SCIMCOverrideStore.shared save:&e];
    [self alert:ok ? @"Exported to mobileconfig/mc_overrides.json. Restart Instagram." :
        [NSString stringWithFormat:@"Save failed: %@", e.localizedDescription]];
}

- (void)deployMapping:(PSSpecifier *)s {
    NSError *e = nil; BOOL ok = [SCIMCOverrideStore.shared deployBundledMappingOverwrite:&e];
    [SCIMCOverrideStore.shared reload]; _specifiers = nil; [self reloadSpecifiers];
    [self alert:ok ? @"id_name_mapping.json written to mobileconfig/. Names refreshed." :
        [NSString stringWithFormat:@"Deploy failed: %@", e.localizedDescription]];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"MobileConfig Overrides"
        message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
@end

#pragma mark - Per-config detail

@implementation SCIMCConfigDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNumber *cid = [self.specifier propertyForKey:@"sci_cid"];
    _configID = cid.integerValue;
    self.title = [SCIMCOverrideStore.shared nameForConfig:_configID];
}

- (id)specifiers {
    if (_specifiers) return _specifiers;
    SCIMCOverrideStore *store = SCIMCOverrideStore.shared;
    NSInteger cid = [[self.specifier propertyForKey:@"sci_cid"] integerValue] ?: _configID;
    _configID = cid;

    NSMutableArray *sp = [NSMutableArray array];
    PSSpecifier *g = [PSSpecifier emptyGroupSpecifier];
    [g setProperty:[NSString stringWithFormat:@"config %ld — toggle a param to override it to true", (long)cid] forKey:@"footerText"];
    [sp addObject:g];

    NSDictionary<NSNumber *, NSString *> *params = [store paramsForConfig:cid];
    NSArray<NSNumber *> *idxs = [params.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *idx in idxs) {
        NSString *label = [NSString stringWithFormat:@"%@  (%@)", params[idx], idx];
        PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:label
            target:self set:@selector(setSwitch:specifier:) get:@selector(getSwitch:)
            detail:Nil cell:PSSwitchCell edit:Nil];
        [sw setProperty:@(cid) forKey:@"sci_cid"];
        [sw setProperty:idx   forKey:@"sci_idx"];
        [sp addObject:sw];
    }
    _specifiers = sp;
    return _specifiers;
}

- (id)getSwitch:(PSSpecifier *)s {
    NSInteger cid = [[s propertyForKey:@"sci_cid"] integerValue];
    NSInteger idx = [[s propertyForKey:@"sci_idx"] integerValue];
    NSString *v = [SCIMCOverrideStore.shared overrideValueForConfig:cid param:idx];
    return @([v isEqualToString:@"true"]);
}

- (void)setSwitch:(id)value specifier:(PSSpecifier *)s {
    NSInteger cid = [[s propertyForKey:@"sci_cid"] integerValue];
    NSInteger idx = [[s propertyForKey:@"sci_idx"] integerValue];
    BOOL on = [value boolValue];
    [SCIMCOverrideStore.shared setOverrideValue:(on ? @"true" : nil) forConfig:cid param:idx];
    [SCIMCOverrideStore.shared save:nil];   // persist immediately to app-group
}
@end
