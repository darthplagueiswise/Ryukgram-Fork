// SCICSymbolBrowserViewController.m
#import "SCICSymbolBrowserViewController.h"
#import "../Features/Gating/SCICSymbolEngine.h"
#import "../Utils.h"

@interface SCICSymbolBrowserViewController () <UISearchResultsUpdating>
@end

@implementation SCICSymbolBrowserViewController {
    UISearchController *_searchController;
    NSTimer *_refreshTimer;
    NSString *_query;
}

- (instancetype)init {
    self = [super initWithTitle:@"FBShared C Symbols"];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _query = @"";

    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search FBShared exports, EasyGating, MobileConfig…";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;

    [self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(__unused NSTimer *t) {
        [self rebuild];
    }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_refreshTimer invalidate];
    _refreshTimer = nil;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    _query = searchController.searchBar.text ?: @"";
    [self rebuild];
}

- (NSString *)subtitleForImport:(SCICImport *)item {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    [parts addObject:item.imageName ?: @"?"];
    [parts addObject:item.resolvable ? @"resolvable" : @"unresolved"];
    if (!item.boolLike) [parts addObject:@"not bool-like"];
    if (item.forceBlacklisted) [parts addObject:@"force blocked"];
    if (item.hookInstalled) [parts addObject:@"hooked"];
    if (item.observedCallCount) [parts addObject:[NSString stringWithFormat:@"%lu hits", (unsigned long)item.observedCallCount]];
    NSNumber *observed = item.observedValue;
    if (observed) [parts addObject:[NSString stringWithFormat:@"real=%@", observed.boolValue ? @"YES" : @"NO"]];
    NSNumber *forced = item.override;
    if (forced) [parts addObject:[NSString stringWithFormat:@"forced=%@", forced.boolValue ? @"YES" : @"NO"]];
    return [parts componentsJoinedByString:@" • "];
}

- (void)rebuild {
    NSMutableArray<SCIBaseSettingsSection *> *sections = [NSMutableArray array];

    NSArray<SCICImport *> *hits = [SCICSymbolEngine searchImports:_query limit:200];
    NSString *masterFooter = [NSString stringWithFormat:@"FBShared exports: %lu. Showing %lu. Browser enumera os símbolos exportados do FBSharedFramework carregado em runtime; fishhook intercepta consumidores/imports desse símbolo, não chamadas diretas internas do próprio FBShared. Observe chama orig e captura valor real; Force é bloqueado para MCI/MCDDasm/IGDirect crashers.", (unsigned long)[SCICSymbolEngine totalImportCount], (unsigned long)hits.count];

    NSMutableArray<SCIBaseSettingsRow *> *master = [NSMutableArray array];
    [master addObject:[SCIBaseSettingsRow switchRowWithTitle:@"Enable C-symbol launch hooks"
        subtitle:@"Permite reinstalar observe/force persistido no %ctor. O toque na tela instala o hook selecionado também."
        value:^BOOL{ return [SCIUtils getBoolPref:@"sci_c_symbol_force_enabled"]; }
        action:^(BOOL on, UIViewController *vc){ [SCIUtils setPref:@(on) forKey:@"sci_c_symbol_force_enabled"]; }]];

    [master addObject:[SCIBaseSettingsRow switchRowWithTitle:@"Force internal/employee safe readers"
        subtitle:@"Força apenas readers internos curados. Não força MCI/MCDDasm hot path."
        value:^BOOL{
            for (NSString *name in [SCICSymbolEngine internalGateSymbolNames]) {
                if (![SCICSymbolEngine overrideForSymbolName:name]) return NO;
            }
            return [SCICSymbolEngine internalGateSymbolNames].count > 0;
        }
        action:^(BOOL on, UIViewController *vc){ [SCICSymbolEngine forceInternalReadersEnabled:on]; }]];

    [sections addObject:[SCIBaseSettingsSection sectionWithHeader:@"FBShared C symbol browser" footer:masterFooter rows:master]];

    for (SCICImport *item in hits) {
        NSString *name = item.symbolName;
        NSMutableArray<SCIBaseSettingsRow *> *rows = [NSMutableArray array];

        [rows addObject:[SCIBaseSettingsRow switchRowWithTitle:@"Observe only"
            subtitle:@"Hook via fishhook nos consumidores do símbolo, chama original, registra hits/valor real e retorna o real."
            value:^BOOL{ return [SCICSymbolEngine isObserving:name]; }
            action:^(BOOL on, UIViewController *vc){
                BOOL ok = [SCICSymbolEngine setObserve:on forSymbolName:name];
                if (!ok) [SCIUtils showToastForDuration:1.6 title:@"Symbol not safe/resolvable for observe"];
            }]];

        NSString *forceSubtitle = item.forceBlacklisted ? @"Bloqueado: MCI/MCDDasm/IGDirect hot path causa abort/crash." : @"Explícito: retorna YES depois de chamar orig. Use só em bool reader validado.";
        [rows addObject:[SCIBaseSettingsRow switchRowWithTitle:@"Force return YES"
            subtitle:forceSubtitle
            value:^BOOL{ NSNumber *o = [SCICSymbolEngine overrideForSymbolName:name]; return o.boolValue; }
            action:^(BOOL on, UIViewController *vc){
                BOOL ok = [SCICSymbolEngine setForce:(on ? @YES : nil) forSymbolName:name];
                if (!ok) [SCIUtils showToastForDuration:1.6 title:@"Force blocked for this symbol"];
            }]];

        SCIBaseSettingsRow *diag = [SCIBaseSettingsRow rowWithTitle:name subtitle:[self subtitleForImport:item] action:nil];
        diag.dynamicSubtitle = ^NSString *{ return [self subtitleForImport:item]; };
        [rows addObject:diag];

        [sections addObject:[SCIBaseSettingsSection sectionWithHeader:name footer:nil rows:rows]];
    }

    self.sections = sections;
    [self reloadSettings];
}

@end
