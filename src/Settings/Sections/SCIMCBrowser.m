// SCIMCBrowser.m — RyukGram-Fork
#import "SCIMCBrowser.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

#pragma mark - Parsing helpers

static NSString *SCITrim(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSInteger SCIConfigIDFromKey(NSString *key) {
    if (![key isKindOfClass:NSString.class]) return NSNotFound;
    NSRange colon = [key rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0) return NSNotFound;
    NSString *prefix = SCITrim([key substringToIndex:colon.location]);
    NSScanner *scanner = [NSScanner scannerWithString:prefix];
    NSInteger value = 0;
    if (![scanner scanInteger:&value] || !scanner.isAtEnd) return NSNotFound;
    return value;
}

// Accepts both internal forms:
//   "<idx>: : <value>"
//   "<idx>: <param_name>: <value>"
// The value may itself contain additional colons.
static BOOL SCIParseOverrideLine(NSString *line,
                                 NSInteger *indexOut,
                                 NSString **nameOut,
                                 NSString **valueOut) {
    if (![line isKindOfClass:NSString.class]) return NO;

    NSRange first = [line rangeOfString:@":"];
    if (first.location == NSNotFound) return NO;

    NSUInteger secondStart = NSMaxRange(first);
    if (secondStart >= line.length) return NO;
    NSRange second = [line rangeOfString:@":"
                                options:0
                                  range:NSMakeRange(secondStart, line.length - secondStart)];
    if (second.location == NSNotFound) return NO;

    NSString *indexText = SCITrim([line substringToIndex:first.location]);
    NSScanner *scanner = [NSScanner scannerWithString:indexText];
    NSInteger index = 0;
    if (![scanner scanInteger:&index] || !scanner.isAtEnd) return NO;

    NSString *paramName = SCITrim([line substringWithRange:NSMakeRange(secondStart,
        second.location - secondStart)]);
    NSString *value = SCITrim([line substringFromIndex:NSMaxRange(second)]);

    if (indexOut) *indexOut = index;
    if (nameOut) *nameOut = paramName;
    if (valueOut) *valueOut = value;
    return YES;
}

#pragma mark - Store

@interface SCIMCOverrideStore () {
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *_overrides;
    NSMutableDictionary<NSNumber *, NSString *> *_names;
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSString *> *> *_params;
    NSArray<NSNumber *> *_sortedIDs;
    NSArray *_qeOverrides;
}
@end

@implementation SCIMCOverrideStore

+ (instancetype)shared {
    static SCIMCOverrideStore *store;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        store = [SCIMCOverrideStore new];
        [store reload];
    });
    return store;
}

- (NSURL *)mobileconfigDir {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = nil;
    NSArray<NSString *> *candidates = @[
        SCI_APPGROUP,
        @"group.com.instagram.instagram",
        @"group.com.burbn.instagram"
    ];

    for (NSString *groupID in candidates) {
        NSURL *candidate = [fm containerURLForSecurityApplicationGroupIdentifier:groupID];
        if (candidate) {
            base = candidate;
            break;
        }
    }

    if (!base) {
        NSURL *documents = [[fm URLsForDirectory:NSDocumentDirectory
                                        inDomains:NSUserDomainMask] firstObject];
        base = documents.URLByDeletingLastPathComponent;
    }

    NSURL *dir = [[base URLByAppendingPathComponent:@"Documents"]
        URLByAppendingPathComponent:@"mobileconfig"];
    [fm createDirectoryAtURL:dir
 withIntermediateDirectories:YES
                  attributes:nil
                       error:nil];
    return dir;
}

- (BOOL)writeMappingData:(NSData *)data error:(NSError **)error {
    if (![data isKindOfClass:NSData.class] || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCIMC"
                                         code:400
                                     userInfo:@{NSLocalizedDescriptionKey: @"mapping data is empty"}];
        }
        return NO;
    }

    NSURL *destination = [self.mobileconfigDir URLByAppendingPathComponent:@"id_name_mapping.json"];
    return [data writeToURL:destination options:NSDataWritingAtomic error:error];
}

- (BOOL)deployBundledMappingOverwrite:(NSError **)error {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *path = [bundle pathForResource:@"id_name_mapping" ofType:@"json"];
    if (!path) {
        path = [bundle pathForResource:@"id_name_mapping"
                                ofType:@"json"
                           inDirectory:@"mobileconfig"];
    }

    if (!path) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCIMC"
                                         code:404
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"bundled id_name_mapping.json not found"}];
        }
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"SCIMC"
                                         code:422
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         @"bundled id_name_mapping.json could not be read"}];
        }
        return NO;
    }
    return [self writeMappingData:data error:error];
}

- (void)bootstrapMappingIfNeeded {
    NSURL *mappingURL = [self.mobileconfigDir URLByAppendingPathComponent:@"id_name_mapping.json"];
    NSNumber *size = nil;
    [mappingURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (!size || size.longLongValue < 10 * 1024) {
        [self deployBundledMappingOverwrite:nil];
    }
}

- (NSString *)canonicalKeyForConfig:(NSInteger)configID {
    NSString *configName = _names[@(configID)];
    if (configName.length > 0) {
        return [NSString stringWithFormat:@"%ld:%@", (long)configID, configName];
    }
    return [NSString stringWithFormat:@"%ld:", (long)configID];
}

- (NSArray<NSString *> *)keysForConfig:(NSInteger)configID {
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSString *canonical = [self canonicalKeyForConfig:configID];
    if (_overrides[canonical]) [matches addObject:canonical];

    NSArray<NSString *> *allKeys = [_overrides.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in allKeys) {
        if ([key isEqualToString:canonical]) continue;
        if (SCIConfigIDFromKey(key) == configID) [matches addObject:key];
    }
    return matches;
}

- (void)reload {
    _overrides = [NSMutableDictionary dictionary];
    _names = [NSMutableDictionary dictionary];
    _params = [NSMutableDictionary dictionary];
    _qeOverrides = @[];

    [self bootstrapMappingIfNeeded];
    NSURL *dir = self.mobileconfigDir;

    NSData *mappingData = [NSData dataWithContentsOfURL:
        [dir URLByAppendingPathComponent:@"id_name_mapping.json"]];
    if (mappingData) {
        id object = [NSJSONSerialization JSONObjectWithData:mappingData options:0 error:nil];
        if ([object isKindOfClass:NSArray.class]) {
            for (id rawEntry in (NSArray *)object) {
                if (![rawEntry isKindOfClass:NSString.class]) continue;
                NSArray<NSString *> *parts = [(NSString *)rawEntry componentsSeparatedByString:@":"];
                if (parts.count < 2) continue;

                NSString *configText = SCITrim(parts[0]);
                NSInteger configID = configText.integerValue;
                if (configID <= 0) continue;

                NSString *configName = SCITrim(parts[1]);
                if (configName.length > 0) _names[@(configID)] = configName;

                NSMutableDictionary<NSNumber *, NSString *> *paramMap = [NSMutableDictionary dictionary];
                for (NSUInteger index = 2; index + 1 < parts.count; index += 2) {
                    NSInteger paramIndex = SCITrim(parts[index]).integerValue;
                    NSString *paramName = SCITrim(parts[index + 1]);
                    if (paramName.length > 0) paramMap[@(paramIndex)] = paramName;
                }
                _params[@(configID)] = paramMap;
            }
        }
    }

    NSData *overrideData = [NSData dataWithContentsOfURL:
        [dir URLByAppendingPathComponent:@"mc_overrides.json"]];
    if (overrideData) {
        id object = [NSJSONSerialization JSONObjectWithData:overrideData options:0 error:nil];
        if ([object isKindOfClass:NSDictionary.class]) {
            NSDictionary *dictionary = (NSDictionary *)object;
            id qe = dictionary[@"_qe_overrides_"];
            if ([qe isKindOfClass:NSArray.class]) _qeOverrides = [qe copy];

            [dictionary enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
                (void)stop;
                if (![rawKey isKindOfClass:NSString.class] ||
                    [(NSString *)rawKey isEqualToString:@"_qe_overrides_"] ||
                    ![rawValue isKindOfClass:NSArray.class]) {
                    return;
                }

                NSMutableArray<NSString *> *lines = [NSMutableArray array];
                for (id line in (NSArray *)rawValue) {
                    if ([line isKindOfClass:NSString.class]) [lines addObject:line];
                }
                _overrides[(NSString *)rawKey] = lines;
            }];
        }
    }

    NSMutableSet<NSNumber *> *allIDs = [NSMutableSet setWithArray:_names.allKeys];
    for (NSString *key in _overrides) {
        NSInteger configID = SCIConfigIDFromKey(key);
        if (configID != NSNotFound && configID > 0) [allIDs addObject:@(configID)];
    }
    _sortedIDs = [allIDs.allObjects sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSNumber *> *)configIDs {
    return _sortedIDs ?: @[];
}

- (NSString *)nameForConfig:(NSInteger)configID {
    NSString *name = _names[@(configID)];
    return name.length > 0 ? name : [NSString stringWithFormat:@"config %ld", (long)configID];
}

- (NSDictionary<NSNumber *, NSString *> *)paramsForConfig:(NSInteger)configID {
    return _params[@(configID)] ?: @{};
}

- (NSArray<NSNumber *> *)configIDsMatching:(NSString *)query {
    if (query.length == 0) return self.configIDs;

    NSString *needle = query.lowercaseString;
    NSMutableArray<NSNumber *> *matches = [NSMutableArray array];
    for (NSNumber *configNumber in _sortedIDs) {
        NSInteger configID = configNumber.integerValue;
        if ([[self nameForConfig:configID].lowercaseString containsString:needle] ||
            [configNumber.stringValue containsString:needle]) {
            [matches addObject:configNumber];
            continue;
        }

        NSDictionary<NSNumber *, NSString *> *params = _params[configNumber];
        for (NSString *paramName in params.allValues) {
            if ([paramName.lowercaseString containsString:needle]) {
                [matches addObject:configNumber];
                break;
            }
        }
    }
    return matches;
}

- (nullable NSString *)overrideValueForConfig:(NSInteger)configID param:(NSInteger)paramIndex {
    for (NSString *key in [self keysForConfig:configID]) {
        NSArray<NSString *> *lines = _overrides[key];
        for (NSString *line in lines) {
            NSInteger parsedIndex = 0;
            NSString *value = nil;
            if (SCIParseOverrideLine(line, &parsedIndex, NULL, &value) && parsedIndex == paramIndex) {
                return value;
            }
        }
    }
    return nil;
}

- (void)setOverrideValue:(nullable NSString *)value
               forConfig:(NSInteger)configID
                   param:(NSInteger)paramIndex {
    NSMutableDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *merged =
        [NSMutableDictionary dictionary];

    for (NSString *key in [self keysForConfig:configID]) {
        for (NSString *line in _overrides[key]) {
            NSInteger existingIndex = 0;
            NSString *existingName = nil;
            NSString *existingValue = nil;
            if (!SCIParseOverrideLine(line, &existingIndex, &existingName, &existingValue)) continue;
            merged[@(existingIndex)] = @{
                @"name": existingName ?: @"",
                @"value": existingValue ?: @""
            };
        }
    }

    if (value) {
        NSString *mappedName = _params[@(configID)][@(paramIndex)] ?: @"";
        merged[@(paramIndex)] = @{ @"name": mappedName, @"value": value };
    } else {
        [merged removeObjectForKey:@(paramIndex)];
    }

    for (NSString *key in [[self keysForConfig:configID] copy]) {
        [_overrides removeObjectForKey:key];
    }

    if (merged.count == 0) return;

    NSArray<NSNumber *> *indices = [merged.allKeys sortedArrayUsingComparator:
        ^NSComparisonResult(NSNumber *left, NSNumber *right) {
            return [right compare:left];
        }];

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:indices.count];
    for (NSNumber *number in indices) {
        NSDictionary<NSString *, NSString *> *entry = merged[number];
        NSString *paramName = _params[@(configID)][number];
        if (paramName.length == 0) paramName = entry[@"name"] ?: @"";
        NSString *entryValue = entry[@"value"] ?: @"";
        [lines addObject:[NSString stringWithFormat:@"%ld: %@: %@",
            (long)number.integerValue, paramName, entryValue]];
    }
    _overrides[[self canonicalKeyForConfig:configID]] = lines;
}

- (BOOL)save:(NSError **)error {
    NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *> *configs =
        [NSMutableDictionary dictionary];

    NSArray<NSString *> *keys = [_overrides.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        NSInteger configID = SCIConfigIDFromKey(key);
        if (configID == NSNotFound || configID <= 0) continue;

        NSMutableDictionary *params = configs[@(configID)];
        if (!params) {
            params = [NSMutableDictionary dictionary];
            configs[@(configID)] = params;
        }

        for (NSString *line in _overrides[key]) {
            NSInteger paramIndex = 0;
            NSString *paramName = nil;
            NSString *paramValue = nil;
            if (!SCIParseOverrideLine(line, &paramIndex, &paramName, &paramValue)) continue;
            params[@(paramIndex)] = @{
                @"name": paramName ?: @"",
                @"value": paramValue ?: @""
            };
        }
    }

    NSMutableDictionary<NSString *, NSArray<NSString *> *> *output = [NSMutableDictionary dictionary];
    NSArray<NSNumber *> *configIDs = [configs.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *configNumber in configIDs) {
        NSInteger configID = configNumber.integerValue;
        NSDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *params = configs[configNumber];
        NSArray<NSNumber *> *indices = [params.allKeys sortedArrayUsingComparator:
            ^NSComparisonResult(NSNumber *left, NSNumber *right) {
                return [right compare:left];
            }];

        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithCapacity:indices.count];
        for (NSNumber *indexNumber in indices) {
            NSDictionary<NSString *, NSString *> *entry = params[indexNumber];
            NSString *paramName = _params[configNumber][indexNumber];
            if (paramName.length == 0) paramName = entry[@"name"] ?: @"";
            NSString *paramValue = entry[@"value"] ?: @"";
            [lines addObject:[NSString stringWithFormat:@"%ld: %@: %@",
                (long)indexNumber.integerValue, paramName, paramValue]];
        }
        output[[self canonicalKeyForConfig:configID]] = lines;
    }
    output[@"_qe_overrides_"] = _qeOverrides ?: @[];

    NSData *data = [NSJSONSerialization dataWithJSONObject:output options:0 error:error];
    if (!data) return NO;

    NSURL *destination = [self.mobileconfigDir URLByAppendingPathComponent:@"mc_overrides.json"];
    BOOL written = [data writeToURL:destination options:NSDataWritingAtomic error:error];
    if (written) [self reload];
    return written;
}

- (void)applyPreset:(NSDictionary<NSString *, NSArray<NSString *> *> *)preset {
    [preset enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray<NSString *> *lines, BOOL *stop) {
        (void)stop;
        NSInteger configID = SCIConfigIDFromKey(key);
        if (configID == NSNotFound) configID = key.integerValue;
        if (configID <= 0) return;

        for (NSString *line in lines) {
            NSInteger paramIndex = 0;
            NSString *value = nil;
            if (!SCIParseOverrideLine(line, &paramIndex, NULL, &value)) continue;
            [self setOverrideValue:value forConfig:configID param:paramIndex];
        }
    }];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)internalUnlockPreset {
    return @{
        @"36377:": @[@"13: : true"],
        @"49223:": @[@"39: : true"],
        @"50769:": @[@"41: : true"],
        @"55291:": @[@"23: : true"],
        @"56474:": @[@"1: : true", @"0: : true"],
        @"57176:": @[@"0: : true"],
        @"58377:": @[@"14: : true"],
        @"59913:": @[@"0: : true"],
        @"61771:": @[@"4: : true"],
        @"62183:": @[@"36: : true"],
        @"69239:": @[@"66: : true"],
        @"74642:": @[@"8: : true"],
        @"75335:": @[@"9: : true", @"6: : true"],
        @"75726:": @[@"6: : true"],
        @"77305:": @[@"6: : true"],
        @"77429:": @[@"12: : true", @"8: : true"],
        @"77493:": @[@"3: : true"],
        @"78944:": @[@"9: : true"],
        @"78970:": @[@"22: : true"],
        @"80734:": @[@"23: : true"],
        @"80778:": @[@"22: : true"],
        @"81940:": @[@"70: : true"],
        @"82560:": @[@"14: : true"],
        @"82840:": @[@"4: : true"],
        @"82950:": @[@"78: : true", @"8: : true"],
        @"83598:": @[@"30: : true"],
        @"84046:": @[@"5: : true"],
        @"85119:": @[@"8: : true"],
        @"85292:": @[@"2: : true"],
        @"87707:": @[@"30: : true"],
        @"90017:": @[@"4: : true"],
        @"90631:": @[@"3: : true", @"2: : true", @"0: : true"],
        @"91290:": @[@"15: : true"],
        @"91689:": @[@"0: : true"],
        @"92764:": @[@"0: : true"],
        @"93536:": @[@"6: : true"],
        @"94098:": @[@"3: : true"],
        @"95994:": @[@"1: : true"],
        @"96260:": @[@"1: : true"],
        @"97127:": @[@"0: : true"],
        @"97242:": @[@"40: : true"],
        @"97656:": @[@"4: : true"],
        @"99456:": @[@"0: : true"],
        @"101583:": @[@"1: : true", @"0: : true"],
        @"103620:": @[@"7: : true"],
        @"104898:": @[@"4: : true"],
        @"105366:": @[@"0: : true"],
        @"105830:": @[@"1: : true"],
        @"107003:": @[@"13: : true"],
        @"108555:": @[@"10: : true"],
        @"109075:": @[@"2: : true", @"0: : true"],
        @"109193:": @[@"14: : true"],
        @"117208:": @[@"2: : true"],
        @"117484:": @[@"1: : true"],
        @"118965:": @[@"0: : true"],
        @"123645:": @[@"1: : true"]
    };
}

@end

#pragma mark - Root browser

@implementation SCIMCBrowserListController {
    NSString *_query;
    UISearchBar *_search;
}

- (NSString *)title {
    return @"MobileConfig Overrides";
}

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

    NSMutableArray *specifiers = [NSMutableArray array];
    SCIMCOverrideStore *store = SCIMCOverrideStore.shared;

    PSSpecifier *presetGroup = [PSSpecifier emptyGroupSpecifier];
    [presetGroup setProperty:@"Presets" forKey:@"footerText"];
    [specifiers addObject:presetGroup];

    PSSpecifier *preset = [PSSpecifier preferenceSpecifierNamed:
        @"Enable Internal / Dogfood / Dev / QE / IGPlus"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    [preset setProperty:@YES forKey:@"enabled"];
    preset->action = @selector(applyInternalPreset:);
    [specifiers addObject:preset];

    PSSpecifier *export = [PSSpecifier preferenceSpecifierNamed:
        @"Export → mobileconfig/mc_overrides.json"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    export->action = @selector(exportNow:);
    [specifiers addObject:export];

    PSSpecifier *deploy = [PSSpecifier preferenceSpecifierNamed:
        @"Deploy / overwrite id_name_mapping.json"
        target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    deploy->action = @selector(deployMapping:);
    [specifiers addObject:deploy];

    NSArray<NSNumber *> *configIDs = [store configIDsMatching:_query];
    PSSpecifier *configsGroup = [PSSpecifier emptyGroupSpecifier];
    [configsGroup setProperty:[NSString stringWithFormat:@"%lu configs",
        (unsigned long)configIDs.count] forKey:@"footerText"];
    [specifiers addObject:configsGroup];

    for (NSNumber *configNumber in configIDs) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:
            [store nameForConfig:configNumber.integerValue]
            target:self
            set:NULL
            get:NULL
            detail:SCIMCConfigDetailController.class
            cell:PSLinkCell
            edit:Nil];
        [row setProperty:configNumber forKey:@"sci_cid"];
        [row setProperty:configNumber.stringValue forKey:@"subtitle"];
        [specifiers addObject:row];
    }

    _specifiers = specifiers;
    return _specifiers;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    (void)searchBar;
    _query = text;
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)applyInternalPreset:(PSSpecifier *)specifier {
    (void)specifier;
    SCIMCOverrideStore *store = SCIMCOverrideStore.shared;
    [store applyPreset:store.internalUnlockPreset];

    NSError *error = nil;
    BOOL success = [store save:&error];
    [self alert:success
        ? @"Internal preset applied and exported. Restart Instagram."
        : [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription]];
}

- (void)exportNow:(PSSpecifier *)specifier {
    (void)specifier;
    NSError *error = nil;
    BOOL success = [SCIMCOverrideStore.shared save:&error];
    [self alert:success
        ? @"Exported to mobileconfig/mc_overrides.json. Restart Instagram."
        : [NSString stringWithFormat:@"Save failed: %@", error.localizedDescription]];
}

- (void)deployMapping:(PSSpecifier *)specifier {
    (void)specifier;
    NSError *error = nil;
    BOOL success = [SCIMCOverrideStore.shared deployBundledMappingOverwrite:&error];
    [SCIMCOverrideStore.shared reload];
    _specifiers = nil;
    [self reloadSpecifiers];
    [self alert:success
        ? @"id_name_mapping.json written to mobileconfig/. Names refreshed."
        : [NSString stringWithFormat:@"Deploy failed: %@", error.localizedDescription]];
}

- (void)alert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MobileConfig Overrides"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
        style:UIAlertActionStyleDefault
        handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Per-config detail

@implementation SCIMCConfigDetailController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNumber *configNumber = [self.specifier propertyForKey:@"sci_cid"];
    _configID = configNumber.integerValue;
    self.title = [SCIMCOverrideStore.shared nameForConfig:_configID];
}

- (id)specifiers {
    if (_specifiers) return _specifiers;

    SCIMCOverrideStore *store = SCIMCOverrideStore.shared;
    NSNumber *specifierConfig = [self.specifier propertyForKey:@"sci_cid"];
    NSInteger configID = specifierConfig ? specifierConfig.integerValue : _configID;
    _configID = configID;

    NSMutableArray *specifiers = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
    [group setProperty:[NSString stringWithFormat:
        @"config %ld — toggle a param to override it to true", (long)configID]
        forKey:@"footerText"];
    [specifiers addObject:group];

    NSDictionary<NSNumber *, NSString *> *params = [store paramsForConfig:configID];
    NSArray<NSNumber *> *indices = [params.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *indexNumber in indices) {
        NSString *label = [NSString stringWithFormat:@"%@  (%@)",
            params[indexNumber], indexNumber];
        PSSpecifier *toggle = [PSSpecifier preferenceSpecifierNamed:label
            target:self
            set:@selector(setSwitch:specifier:)
            get:@selector(getSwitch:)
            detail:Nil
            cell:PSSwitchCell
            edit:Nil];
        [toggle setProperty:@(configID) forKey:@"sci_cid"];
        [toggle setProperty:indexNumber forKey:@"sci_idx"];
        [specifiers addObject:toggle];
    }

    _specifiers = specifiers;
    return _specifiers;
}

- (id)getSwitch:(PSSpecifier *)specifier {
    NSInteger configID = [[specifier propertyForKey:@"sci_cid"] integerValue];
    NSInteger paramIndex = [[specifier propertyForKey:@"sci_idx"] integerValue];
    NSString *value = [SCIMCOverrideStore.shared overrideValueForConfig:configID param:paramIndex];
    return @([value isEqualToString:@"true"]);
}

- (void)setSwitch:(id)value specifier:(PSSpecifier *)specifier {
    NSInteger configID = [[specifier propertyForKey:@"sci_cid"] integerValue];
    NSInteger paramIndex = [[specifier propertyForKey:@"sci_idx"] integerValue];
    BOOL enabled = [value boolValue];
    [SCIMCOverrideStore.shared setOverrideValue:(enabled ? @"true" : nil)
                                      forConfig:configID
                                          param:paramIndex];
    [SCIMCOverrideStore.shared save:nil];
}

@end
