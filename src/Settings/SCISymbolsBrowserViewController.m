// SCISymbolsBrowserViewController.m
#import "SCISymbolsBrowserViewController.h"
#import "../Utils.h"
#import "../Features/Gating/SCICSymbolStub.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <objc/runtime.h>

@interface SCICSymbolEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *image;
@property (nonatomic, copy) NSString *section;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *abi;
@property (nonatomic, copy) NSString *hookPlan;
@property (nonatomic, assign) BOOL function;
@property (nonatomic, assign) BOOL data;
@property (nonatomic, assign) BOOL swiftLike;
@property (nonatomic, assign) BOOL resolvable;
@property (nonatomic, assign) uintptr_t address;
@end
@implementation SCICSymbolEntry @end

static NSString *SCICModeTitle(SCICSymbolsBrowserMode mode) {
    switch (mode) {
        case SCICSymbolsBrowserModeDataParams: return @"DATA / Params";
        case SCICSymbolsBrowserModeSwiftDisassembly: return @"Swift / Disassembly";
        case SCICSymbolsBrowserModeCFunctions:
        default: return @"C Functions / ABI";
    }
}

static NSString *scic_section_label(const struct section_64 *sec) {
    if (!sec) return @"unknown";
    char seg[17] = {0}; char sect[17] = {0};
    memcpy(seg, sec->segname, 16); memcpy(sect, sec->sectname, 16);
    return [NSString stringWithFormat:@"%s,%s", seg, sect];
}

static void scic_collect_sections(const struct mach_header_64 *mh, NSMutableArray<NSValue *> *sections, const struct symtab_command **symtab, const struct segment_command_64 **linkedit) {
    const uint8_t *p = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, SEG_LINKEDIT, 16) == 0) *linkedit = seg;
            const struct section_64 *sec = (const struct section_64 *)(seg + 1);
            for (uint32_t j = 0; j < seg->nsects; j++) [sections addObject:[NSValue valueWithPointer:&sec[j]]];
        } else if (lc->cmd == LC_SYMTAB) {
            *symtab = (const struct symtab_command *)lc;
        }
        p += lc->cmdsize;
    }
}

static BOOL SCICIsImageWanted(NSString *path) {
    return [path.lastPathComponent isEqualToString:@"Instagram"] || [path containsString:@"/FBSharedFramework"];
}

static NSString *SCICImageShortName(NSString *path) {
    if ([path containsString:@"/FBSharedFramework"]) return @"FBSharedFramework";
    if ([path.lastPathComponent isEqualToString:@"Instagram"]) return @"Instagram";
    return path.lastPathComponent ?: @"Image";
}

static BOOL SCICNameLooksSwiftOrCXX(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return NO;
    return [name hasPrefix:@"$s"] || [name hasPrefix:@"$S"] || [name hasPrefix:@"_T"] || [name hasPrefix:@"_Z"] || [name hasPrefix:@"__Z"] || [name containsString:@"Swift"];
}

static NSString *SCICABIForName(NSString *name, BOOL function, NSString *section) {
    if (!function) {
        if ([name hasPrefix:@"ig_"] || [name hasPrefix:@"xav_"] || [name hasPrefix:@"mc_team_"]) return @"DATA param descriptor; force via typed MobileConfig reader after xref/capture";
        if ([name containsString:@"MapSchema"] || [name containsString:@"MapFields"] || [name hasPrefix:@"IGAPI"]) return @"DATA schema/field map; no function ABI";
        if ([name hasPrefix:@"k"] || [name containsString:@"Key"] || [name containsString:@"Name"]) return @"DATA NSString/constant key; hook consumer, not symbol";
        return @"DATA/constant; not callable";
    }
    if ([name isEqualToString:@"IGMobileConfigBooleanValueForInternalUse"]) return @"BOOL reader: (id/param, BOOL default, void *ctx) -> BOOL w0";
    if ([name isEqualToString:@"IGMobileConfigIntegerValueForInternalUse"]) return @"integer reader: returns x0/w0; typed int64/int override only";
    if ([name isEqualToString:@"IGMobileConfigStringValueForInternalUse"]) return @"string reader: returns object/pointer in x0; ABI-specific, no BOOL stub";
    if ([name containsString:@"EasyGatingGetBoolean"]) return @"BOOL reader: gate id/context -> BOOL w0";
    if ([name containsString:@"EasyGatingGetInt32"]) return @"int32 reader: returns w0";
    if ([name containsString:@"EasyGatingGetInt64"]) return @"int64 reader: returns x0";
    if ([name containsString:@"EasyGatingGetDouble"]) return @"double reader: returns d0/v0";
    if ([name containsString:@"EasyGatingCopyString"]) return @"string/copy reader: returns pointer/object in x0; ownership-sensitive";
    if ([name isEqualToString:@"TALEventsGetIdToNameMappingForEventId"]) return @"event id -> name mapping; string/pointer return, observe/typed only";
    if ([name isEqualToString:@"MCIDatabaseTableToProcedureNameMapRegisterMappings"]) return @"registration/action; observe/log only, no return stub";
    if ([name hasPrefix:@"IGMobileConfigSetConfigOverrides"] || [name hasPrefix:@"IGMobileConfigForceUpdateConfigs"] || [name hasPrefix:@"IGMobileConfigTryUpdateConfigs"]) return @"MobileConfig action; call only with valid args/table, no return-YES";
    if (SCICNameLooksSwiftOrCXX(name)) return @"Swift/C++ direct symbol; disassemble/xref first, sideload hook not assumed";
    return @"unknown function ABI; classify before hook";
}

static NSString *SCICHookPlanForName(NSString *name, BOOL function, NSString *section) {
    if (!function) {
        if ([name hasPrefix:@"ig_"] || [name hasPrefix:@"xav_"] || [name hasPrefix:@"mc_team_"]) return @"Param hook: xref/capture descriptor, then force via IGMobileConfigBoolean/Integer/String reader";
        return @"No direct hook. Copy symbol and find consumer/xrefs.";
    }
    if ([SCICSymbolStub isForceableSymbol:name]) return @"Hardstub BOOL allowed: mov w0,#1; ret via fishhook";
    if ([name containsString:@"GetInt32"] || [name containsString:@"IntegerValue"] || [name containsString:@"GetInt64"]) return @"Typed numeric hook: return w0/x0; use value-specific replacement, not BOOL stub";
    if ([name containsString:@"GetDouble"]) return @"Typed double hook: return d0; use fmov/typed replacement";
    if ([name containsString:@"String"] || [name containsString:@"CopyString"] || [name isEqualToString:@"TALEventsGetIdToNameMappingForEventId"]) return @"Typed string hook: resolve ownership/CF/ObjC before forcing; observe safe";
    if ([name containsString:@"SetConfigOverrides"] || [name containsString:@"ForceUpdate"] || [name containsString:@"TryUpdate"] || [name containsString:@"RegisterMappings"]) return @"Action hook/button only with real args; never return-YES";
    return @"List/diagnose until ABI/callers are known";
}

static NSArray<NSString *> *SCICDefaultFiltersForMode(SCICSymbolsBrowserMode mode) {
    if (mode == SCICSymbolsBrowserModeDataParams) return @[@"ig_is_employee", @"ig_user_session", @"xav_switcher", @"mc_team", @"MapFields", @"MapSchema", @"OpenSettings", @"DeveloperAccount", @"FeatureFlags"];
    if (mode == SCICSymbolsBrowserModeSwiftDisassembly) return @[@"$s", @"_Tt", @"ConsumerSubs", @"MobileConfig", @"Dogfood", @"Eligibility", @"FeatureFlags"];
    return @[@"MobileConfig", @"EasyGating", @"MSGC", @"MCI", @"TALEvents", @"RegisterMappings", @"UpdateConfigs", @"SetConfigOverrides", @"InternalApps", @"Minos"];
}

static void SCICEnumerateImageSymbolsAtIndex(uint32_t imageIndex, NSMutableArray<SCICSymbolEntry *> *out) {
    const char *imageName = _dyld_get_image_name(imageIndex);
    if (!imageName) return;
    NSString *path = [NSString stringWithUTF8String:imageName];
    if (!SCICIsImageWanted(path)) return;
    const struct mach_header *raw = _dyld_get_image_header(imageIndex);
    if (!raw || raw->magic != MH_MAGIC_64) return;
    const struct mach_header_64 *mh = (const struct mach_header_64 *)raw;
    intptr_t slide = _dyld_get_image_vmaddr_slide(imageIndex);
    NSMutableArray<NSValue *> *sections = [NSMutableArray array];
    const struct symtab_command *symtab = NULL;
    const struct segment_command_64 *linkedit = NULL;
    scic_collect_sections(mh, sections, &symtab, &linkedit);
    if (!symtab || !linkedit) return;
    uintptr_t linkeditBase = (uintptr_t)slide + (uintptr_t)linkedit->vmaddr - (uintptr_t)linkedit->fileoff;
    const struct nlist_64 *nl = (const struct nlist_64 *)(linkeditBase + symtab->symoff);
    const char *strtab = (const char *)(linkeditBase + symtab->stroff);
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        uint8_t type = nl[i].n_type;
        if (type & N_STAB) continue;
        if ((type & N_TYPE) != N_SECT) continue;
        if (nl[i].n_un.n_strx == 0) continue;
        const char *rawName = strtab + nl[i].n_un.n_strx;
        if (!rawName || rawName[0] != '_') continue;
        NSString *name = [NSString stringWithUTF8String:rawName + 1];
        if (!name.length || [seen containsObject:name]) continue;
        if ([name hasPrefix:@"OBJC_"] || [name hasPrefix:@"\001"]) continue;
        [seen addObject:name];
        const struct section_64 *sec = NULL;
        uint8_t sectIndex = nl[i].n_sect;
        if (sectIndex > 0 && sectIndex <= sections.count) sec = [sections[sectIndex - 1] pointerValue];
        NSString *section = scic_section_label(sec);
        BOOL isText = sec && strncmp(sec->segname, "__TEXT", 16) == 0 && strncmp(sec->sectname, "__text", 16) == 0;
        SCICSymbolEntry *e = [SCICSymbolEntry new];
        e.name = name;
        e.image = SCICImageShortName(path);
        e.section = section;
        e.function = isText;
        e.data = !isText;
        e.swiftLike = SCICNameLooksSwiftOrCXX(name);
        e.address = (uintptr_t)nl[i].n_value + (uintptr_t)slide;
        e.kind = isText ? (e.swiftLike ? @"Swift/C++ function" : @"C/function") : @"DATA/const";
        e.abi = SCICABIForName(name, isText, section);
        e.hookPlan = SCICHookPlanForName(name, isText, section);
        e.resolvable = (dlsym(RTLD_DEFAULT, name.UTF8String) != NULL || dlsym(RTLD_DEFAULT, [[@"_" stringByAppendingString:name] UTF8String]) != NULL);
        [out addObject:e];
    }
}

static NSArray<SCICSymbolEntry *> *SCICEnumerateInstagramAndFBSharedSymbols(void) {
    NSMutableArray *out = [NSMutableArray array];
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) SCICEnumerateImageSymbolsAtIndex(i, out);
    [out sortUsingComparator:^NSComparisonResult(SCICSymbolEntry *a, SCICSymbolEntry *b) {
        NSComparisonResult r = [a.image compare:b.image options:NSCaseInsensitiveSearch];
        return r == NSOrderedSame ? [a.name compare:b.name options:NSCaseInsensitiveSearch] : r;
    }];
    return out.copy;
}

static char kSCICSymbolRowPayloadKey;

@interface SCISymbolsBrowserViewController () <UISearchResultsUpdating>
@end

@implementation SCISymbolsBrowserViewController {
    SCICSymbolsBrowserMode _mode;
    NSArray<SCICSymbolEntry *> *_allSymbols;
    NSString *_query;
    UIActivityIndicatorView *_spinner;
}

- (instancetype)init { return [self initWithMode:SCICSymbolsBrowserModeCFunctions]; }
- (instancetype)initWithMode:(SCICSymbolsBrowserMode)mode {
    self = [super initWithTitle:SCICModeTitle(mode)];
    if (self) { _mode = mode; self.reduceTopInset = NO; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchResultsUpdater = self;
    sc.obscuresBackgroundDuringPresentation = NO;
    sc.searchBar.placeholder = @"Search symbols, ABI, section…";
    SCIUIKit26ConfigureSearchBar(sc.searchBar);
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _spinner.center = self.view.center;
    _spinner.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:_spinner];
    [_spinner startAnimating];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *symbols = SCICEnumerateInstagramAndFBSharedSymbols();
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_allSymbols = symbols;
            [self->_spinner stopAnimating];
            [self rebuildSections];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    _query = searchController.searchBar.text ?: @"";
    [self rebuildSections];
}

- (NSArray<NSString *> *)queryTokens {
    NSString *q = [[_query ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!q.length) return @[];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *t in [q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if (t.length) [tokens addObject:t];
    return tokens.copy;
}

- (BOOL)entryMatchesMode:(SCICSymbolEntry *)e {
    if (_mode == SCICSymbolsBrowserModeCFunctions) return e.function && !e.swiftLike;
    if (_mode == SCICSymbolsBrowserModeDataParams) return e.data;
    return e.function && e.swiftLike;
}

- (BOOL)entry:(SCICSymbolEntry *)e matchesTokens:(NSArray<NSString *> *)tokens {
    NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@", e.name?:@"", e.image?:@"", e.section?:@"", e.kind?:@"", e.abi?:@"", e.hookPlan?:@""].lowercaseString;
    for (NSString *t in tokens) if (![hay containsString:t]) return NO;
    return YES;
}

- (BOOL)entryMatchesDefaultFilters:(SCICSymbolEntry *)e {
    if ([SCICSymbolStub forceForSymbol:e.name] != nil || [SCICSymbolStub hookInstalledForSymbol:e.name]) return YES;
    for (NSString *f in SCICDefaultFiltersForMode(_mode)) if ([e.name.lowercaseString containsString:f.lowercaseString] || [e.abi.lowercaseString containsString:f.lowercaseString]) return YES;
    return NO;
}

- (NSString *)subtitleForEntry:(SCICSymbolEntry *)e {
    NSMutableArray *bits = [NSMutableArray array];
    [bits addObject:e.image ?: @"Image"];
    [bits addObject:e.section ?: @"section?"];
    [bits addObject:e.kind ?: @"kind?"];
    if (e.resolvable) [bits addObject:@"dlsym OK"];
    if (e.function && [SCICSymbolStub isForceableSymbol:e.name]) [bits addObject:@"BOOL hardstub allowed"];
    else [bits addObject:e.abi ?: @"ABI unknown"];
    return [bits componentsJoinedByString:@" · "];
}

- (NSString *)detailForEntry:(SCICSymbolEntry *)e {
    return [NSString stringWithFormat:@"%@\n\nImage: %@\nSection: %@\nAddress: 0x%llx\nKind: %@\nResolvable: %@\n\nABI: %@\n\nHook plan: %@", e.name?:@"", e.image?:@"", e.section?:@"", (unsigned long long)e.address, e.kind?:@"", e.resolvable?@"YES":@"NO", e.abi?:@"", e.hookPlan?:@""];
}

- (void)presentActionsForEntry:(SCICSymbolEntry *)entry {
    if (!entry) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:entry.name message:[self detailForEntry:entry] preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    if (entry.function && [SCICSymbolStub isForceableSymbol:entry.name]) {
        [a addAction:[UIAlertAction actionWithTitle:@"Force BOOL YES (hardstub)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act){ [SCICSymbolStub setForce:@YES forSymbol:entry.name]; [weakSelf rebuildSections]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Clear force" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *act){ [SCICSymbolStub setForce:nil forSymbol:entry.name]; [weakSelf rebuildSections]; }]];
    } else {
        UIAlertAction *blocked = [UIAlertAction actionWithTitle:@"No BOOL stub: see ABI/Hook plan" style:UIAlertActionStyleDefault handler:nil];
        blocked.enabled = NO;
        [a addAction:blocked];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act){ UIPasteboard.generalPasteboard.string = entry.name ?: @""; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy ABI report" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *act){ UIPasteboard.generalPasteboard.string = [weakSelf detailForEntry:entry]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *pop = a.popoverPresentationController;
    pop.sourceView = self.view;
    pop.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds)-40, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)rebuildSections {
    if (!_allSymbols) return;
    NSArray *tokens = [self queryTokens];
    NSMutableArray *igRows = [NSMutableArray array];
    NSMutableArray *fbRows = [NSMutableArray array];
    NSUInteger limit = tokens.count ? 700 : 300;
    NSUInteger shown = 0;
    for (SCICSymbolEntry *e in _allSymbols) {
        if (![self entryMatchesMode:e]) continue;
        if (tokens.count) { if (![self entry:e matchesTokens:tokens]) continue; }
        else if (![self entryMatchesDefaultFilters:e]) continue;
        if (shown++ >= limit) break;
        SCIBaseSettingsRow *row = [SCIBaseSettingsRow rowWithTitle:e.name subtitle:nil action:^(__unused UIViewController *vc){ [self presentActionsForEntry:e]; }];
        row.dynamicSubtitle = ^NSString *{ return [self subtitleForEntry:e]; };
        objc_setAssociatedObject(row, &kSCICSymbolRowPayloadKey, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([e.image isEqualToString:@"Instagram"]) [igRows addObject:row]; else [fbRows addObject:row];
    }
    NSString *footer = @"Modes are separated: C functions, DATA/param descriptors, and Swift/direct-dispatch symbols. ObjC method browsing remains in the Instagram/FBShared ObjC browsers. Only validated BOOL functions get hardstub toggles; typed int/double/string/action symbols show ABI plan instead of fake BOOL switches.";
    if (!igRows.count) [igRows addObject:[SCIBaseSettingsRow rowWithTitle:@"No Instagram symbols" subtitle:@"Search another term or switch browser mode." action:nil]];
    if (!fbRows.count) [fbRows addObject:[SCIBaseSettingsRow rowWithTitle:@"No FBShared symbols" subtitle:@"Search another term or switch browser mode." action:nil]];
    self.sections = @[
        [SCIBaseSettingsSection sectionWithHeader:@"Instagram executable" footer:nil rows:igRows],
        [SCIBaseSettingsSection sectionWithHeader:@"FBSharedFramework" footer:footer rows:fbRows],
    ];
    [self reloadSettings];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    UIListContentConfiguration *cfg = (UIListContentConfiguration *)cell.contentConfiguration;
    cfg.textProperties.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    cfg.textProperties.numberOfLines = 2;
    cfg.secondaryTextProperties.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    cfg.secondaryTextProperties.numberOfLines = 4;
    cell.contentConfiguration = cfg;
    return cell;
}

@end
