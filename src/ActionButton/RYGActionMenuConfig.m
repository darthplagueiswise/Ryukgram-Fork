#import "RYGActionMenuConfig.h"
#import "../Utils.h"

NSString *const RYGActionMenuConfigDidChangeNotification = @"RYGActionMenuConfigDidChangeNotification";

static NSString *const kCfgVersion       = @"v";
static NSString *const kCfgSections      = @"sections";
static NSString *const kCfgDisabled      = @"disabled";
static NSString *const kCfgShowDate      = @"show_date";
static NSString *const kCfgDefaultTap    = @"default_tap";
static NSString *const kCfgDefaultCopy   = @"default_copy_info";
static NSInteger  const kCfgCurrentVer   = 1;

@interface RYGActionMenuConfig ()
@property (nonatomic, assign, readwrite) RYGActionSource source;
@property (nonatomic, strong) NSMutableArray<RYGActionConfigSection *> *sectionsStorage;
@property (nonatomic, strong) NSMutableSet<NSString *> *disabledStorage;
@end

@implementation RYGActionMenuConfig

+ (void)initialize {
    if (self == [RYGActionMenuConfig class]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"RYGLanguageDidChange"
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *_) {
            [RYGActionMenuConfig reloadAll];
        }];
    }
}

// MARK: - Cache

+ (NSMutableDictionary<NSNumber *, RYGActionMenuConfig *> *)cache {
    static NSMutableDictionary *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [NSMutableDictionary dictionary]; });
    return c;
}

+ (instancetype)configForSource:(RYGActionSource)source {
    @synchronized ([self cache]) {
        RYGActionMenuConfig *cfg = [self cache][@(source)];
        if (cfg) return cfg;
        cfg = [[RYGActionMenuConfig alloc] initForSource:source];
        [self cache][@(source)] = cfg;
        return cfg;
    }
}

+ (void)reloadAll {
    @synchronized ([self cache]) { [[self cache] removeAllObjects]; }
}

// MARK: - Init

- (instancetype)initForSource:(RYGActionSource)source {
    self = [super init];
    if (!self) return nil;
    _source = source;
    _sectionsStorage = [NSMutableArray array];
    _disabledStorage = [NSMutableSet set];
    [self load];
    return self;
}

// MARK: - Load

- (void)load {
    NSDictionary *dict = [RYGUtils getDictPref:[RYGActionCatalog prefKeyForSource:_source]];
    BOOL hasStored = ([dict isKindOfClass:[NSDictionary class]] && dict.count > 0);

    NSArray<RYGActionConfigSection *> *defaultSections = [RYGActionCatalog defaultSectionsForSource:_source];

    // Sections
    NSMutableArray<RYGActionConfigSection *> *loaded = [NSMutableArray array];
    if (hasStored) {
        NSArray *raw = dict[kCfgSections];
        if ([raw isKindOfClass:[NSArray class]]) {
            for (id v in raw) {
                RYGActionConfigSection *s = [RYGActionConfigSection sectionFromDictionary:v];
                if (s) [loaded addObject:s];
            }
        }
    }
    if (loaded.count == 0) {
        for (RYGActionConfigSection *s in defaultSections) [loaded addObject:[s copy]];
    } else {
        // Section title + icon are presentation-only — always sourced from the
        // catalog so language switches and copy edits flow through (the stored
        // title was once cached in the user's locale and would otherwise freeze).
        for (RYGActionConfigSection *s in loaded) {
            for (RYGActionConfigSection *def in defaultSections) {
                if ([def.identifier isEqualToString:s.identifier]) {
                    s.title  = def.title;
                    s.iconSF = def.iconSF;
                    break;
                }
            }
        }
    }
    _sectionsStorage = loaded;

    // Disabled set
    NSMutableSet *disabled = [NSMutableSet set];
    if (hasStored) {
        NSArray *raw = dict[kCfgDisabled];
        if ([raw isKindOfClass:[NSArray class]]) {
            for (id v in raw) if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) [disabled addObject:v];
        }
    }

    // Fresh install: seed disabledByDefault descriptors. Stored config wins after.
    if (!hasStored) {
        for (RYGActionDescriptor *desc in [RYGActionCatalog descriptorsForSource:_source]) {
            if (desc.disabledByDefault) [disabled addObject:desc.identifier];
        }
    }
    _disabledStorage = disabled;

    // Show date
    if (hasStored && dict[kCfgShowDate]) {
        _showDate = [dict[kCfgShowDate] boolValue];
    } else {
        NSString *legacy = [RYGActionCatalog legacyDateTogglePrefKeyForSource:_source];
        _showDate = legacy.length ? [RYGUtils getBoolPref:legacy] : NO;
    }

    // Default tap
    if (hasStored && [dict[kCfgDefaultTap] isKindOfClass:[NSString class]] && [dict[kCfgDefaultTap] length]) {
        _defaultTap = [dict[kCfgDefaultTap] copy];
    } else {
        NSString *legacy = [RYGActionCatalog legacyDefaultTapPrefKeyForSource:_source];
        NSString *legacyVal = legacy.length ? [RYGUtils getStringPref:legacy] : nil;
        _defaultTap = legacyVal.length ? [legacyVal copy] : @"menu";
    }

    // Default copy info (profile only)
    if ([dict[kCfgDefaultCopy] isKindOfClass:[NSString class]] && [dict[kCfgDefaultCopy] length]) {
        _defaultCopyInfo = [dict[kCfgDefaultCopy] copy];
    } else {
        _defaultCopyInfo = RYGAID_CopyUsername;
    }

    [self normalize];
}

// MARK: - Normalize

// Every catalog action ends up in exactly one section. Unknown IDs dropped,
// new catalog actions appended to their default section (or last as fallback).
- (void)normalize {
    NSArray<RYGActionDescriptor *> *catalog = [RYGActionCatalog descriptorsForSource:_source];
    NSArray<RYGActionConfigSection *> *defaults = [RYGActionCatalog defaultSectionsForSource:_source];

    NSMutableSet<NSString *> *known = [NSMutableSet set];
    for (RYGActionDescriptor *d in catalog) [known addObject:d.identifier];

    // 1. Remove unknown action IDs from sections + disabled set.
    for (RYGActionConfigSection *s in _sectionsStorage) {
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:s.actionIDs.count];
        for (NSString *aid in s.actionIDs) if ([known containsObject:aid]) [kept addObject:aid];
        s.actionIDs = kept;
    }
    NSMutableSet *cleanedDisabled = [NSMutableSet set];
    for (NSString *aid in _disabledStorage) if ([known containsObject:aid]) [cleanedDisabled addObject:aid];
    _disabledStorage = cleanedDisabled;

    // 2. Drop empty sections that aren't in the default layout (keep default sections
    // even when emptied so reset feels familiar).
    NSMutableSet *defaultSectionIDs = [NSMutableSet set];
    for (RYGActionConfigSection *s in defaults) [defaultSectionIDs addObject:s.identifier];
    NSMutableArray *kept = [NSMutableArray array];
    for (RYGActionConfigSection *s in _sectionsStorage) {
        if (s.actionIDs.count > 0 || [defaultSectionIDs containsObject:s.identifier]) [kept addObject:s];
    }
    _sectionsStorage = kept;

    // 3. Add any default sections missing from the saved config (preserve order — append at end).
    for (RYGActionConfigSection *def in defaults) {
        BOOL found = NO;
        for (RYGActionConfigSection *s in _sectionsStorage) {
            if ([s.identifier isEqualToString:def.identifier]) { found = YES; break; }
        }
        if (!found) [_sectionsStorage addObject:[def copy]];
    }

    // 4. Find action IDs present in the catalog but not assigned to any section. Append
    //    each to its default section (or, if that section is missing, to the last section).
    NSMutableSet *assigned = [NSMutableSet set];
    for (RYGActionConfigSection *s in _sectionsStorage) [assigned addObjectsFromArray:s.actionIDs];

    for (NSString *aid in known) {
        if ([assigned containsObject:aid]) continue;

        NSString *targetSectionID = nil;
        for (RYGActionConfigSection *def in defaults) {
            if ([def.actionIDs containsObject:aid]) { targetSectionID = def.identifier; break; }
        }
        RYGActionConfigSection *target = nil;
        if (targetSectionID) target = [self sectionWithID:targetSectionID];
        if (!target) target = _sectionsStorage.lastObject;
        if (!target) continue;
        [target.actionIDs addObject:aid];
        [assigned addObject:aid];
    }
}

// MARK: - Properties

- (NSArray<RYGActionConfigSection *> *)sections { return [_sectionsStorage copy]; }
- (NSSet<NSString *> *)disabled { return [_disabledStorage copy]; }
- (NSArray<RYGActionConfigSection *> *)mutableSections { return _sectionsStorage; }

// MARK: - Lookup

- (RYGActionConfigSection *)sectionWithID:(NSString *)identifier {
    if (!identifier.length) return nil;
    for (RYGActionConfigSection *s in _sectionsStorage) {
        if ([s.identifier isEqualToString:identifier]) return s;
    }
    return nil;
}

- (RYGActionConfigSection *)sectionContainingActionID:(NSString *)actionID {
    if (!actionID.length) return nil;
    for (RYGActionConfigSection *s in _sectionsStorage) {
        if ([s.actionIDs containsObject:actionID]) return s;
    }
    return nil;
}

- (NSArray<NSString *> *)assignedActionIDs {
    NSMutableArray *out = [NSMutableArray array];
    for (RYGActionConfigSection *s in _sectionsStorage) [out addObjectsFromArray:s.actionIDs];
    return out;
}

- (BOOL)isActionDisabled:(NSString *)actionID {
    return actionID.length && [_disabledStorage containsObject:actionID];
}

- (void)setAction:(NSString *)actionID disabled:(BOOL)disabled {
    if (!actionID.length) return;
    if (disabled) [_disabledStorage addObject:actionID];
    else [_disabledStorage removeObject:actionID];
}

// MARK: - Mutation

- (void)moveSectionFromIndex:(NSInteger)src toIndex:(NSInteger)dst {
    if (src < 0 || src >= (NSInteger)_sectionsStorage.count) return;
    if (dst < 0) dst = 0;
    if (dst >= (NSInteger)_sectionsStorage.count) dst = _sectionsStorage.count - 1;
    if (src == dst) return;
    RYGActionConfigSection *moved = _sectionsStorage[src];
    [_sectionsStorage removeObjectAtIndex:src];
    [_sectionsStorage insertObject:moved atIndex:dst];
}

- (void)moveActionInSection:(RYGActionConfigSection *)section fromIndex:(NSInteger)src toIndex:(NSInteger)dst {
    if (!section) return;
    if (src < 0 || src >= (NSInteger)section.actionIDs.count) return;
    if (dst < 0) dst = 0;
    if (dst >= (NSInteger)section.actionIDs.count) dst = section.actionIDs.count - 1;
    if (src == dst) return;
    NSString *aid = section.actionIDs[src];
    [section.actionIDs removeObjectAtIndex:src];
    [section.actionIDs insertObject:aid atIndex:dst];
}

- (void)moveActionID:(NSString *)actionID toSection:(RYGActionConfigSection *)dstSection index:(NSInteger)dstIndex {
    if (!actionID.length || !dstSection) return;
    RYGActionConfigSection *fromSection = [self sectionContainingActionID:actionID];
    if (!fromSection) return;
    [fromSection.actionIDs removeObject:actionID];
    if (dstIndex < 0) dstIndex = 0;
    if (dstIndex > (NSInteger)dstSection.actionIDs.count) dstIndex = dstSection.actionIDs.count;
    [dstSection.actionIDs insertObject:actionID atIndex:dstIndex];
}

- (void)setSection:(RYGActionConfigSection *)section collapsible:(BOOL)collapsible {
    if (!section) return;
    section.collapsible = collapsible;
}

// MARK: - Save / Reset

- (void)save {
    NSMutableArray *secs = [NSMutableArray arrayWithCapacity:_sectionsStorage.count];
    for (RYGActionConfigSection *s in _sectionsStorage) [secs addObject:[s dictionaryRepresentation]];
    NSDictionary *dict = @{
        kCfgVersion: @(kCfgCurrentVer),
        kCfgSections: secs,
        kCfgDisabled: [_disabledStorage allObjects] ?: @[],
        kCfgShowDate: @(_showDate),
        kCfgDefaultTap: _defaultTap.length ? _defaultTap : @"menu",
        kCfgDefaultCopy: _defaultCopyInfo.length ? _defaultCopyInfo : RYGAID_CopyUsername,
    };
    [RYGUtils setPref:dict forKey:[RYGActionCatalog prefKeyForSource:_source]];
    // Keep legacy keys mirrored for back-compat with code paths still reading them.
    NSString *legacyDate = [RYGActionCatalog legacyDateTogglePrefKeyForSource:_source];
    if (legacyDate) [RYGUtils setPref:@(_showDate) forKey:legacyDate];
    NSString *legacyTap = [RYGActionCatalog legacyDefaultTapPrefKeyForSource:_source];
    if (legacyTap) [RYGUtils setPref:(_defaultTap.length ? _defaultTap : @"menu") forKey:legacyTap];

    [[NSNotificationCenter defaultCenter] postNotificationName:RYGActionMenuConfigDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"source": @(_source)}];
}

- (void)resetToDefaults {
    _sectionsStorage = [NSMutableArray array];
    for (RYGActionConfigSection *s in [RYGActionCatalog defaultSectionsForSource:_source]) {
        [_sectionsStorage addObject:[s copy]];
    }
    [_disabledStorage removeAllObjects];
    _showDate = NO;
    _defaultTap = @"menu";
    _defaultCopyInfo = RYGAID_CopyUsername;
    [self save];
}

@end
