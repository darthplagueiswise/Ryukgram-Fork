#import "SCIIGDSLauncherConfigViewController.h"
#import <objc/runtime.h>

extern void SCIIGDSEnsureHooksInstalled(void) __attribute__((weak_import));

static BOOL SCIIGDSApplyHooksIfAvailable(void) {
    if (SCIIGDSEnsureHooksInstalled) {
        SCIIGDSEnsureHooksInstalled();
        return YES;
    }
    return NO;
}

// Section model
@interface IGDSSection : NSObject
@property (copy) NSString *header, *footer;
@property (copy) NSArray<NSDictionary *> *rows; // each: @{title, key, restart}
@end
@implementation IGDSSection @end

@implementation SCIIGDSLauncherConfigViewController {
    NSArray<IGDSSection *> *_sections;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"IGDSLauncherConfig";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.estimatedRowHeight = 60;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Aplicar"
               style:UIBarButtonItemStyleDone
              target:self
              action:@selector(applyTapped)];
    [self buildSections];
}

- (void)applyTapped {
    BOOL applied = SCIIGDSApplyHooksIfAvailable();
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"IGDSLauncherConfig"
                                                             message:(applied ? @"Hooks reaplicados." : @"Hook IGDS não está linkado nesta build.")
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
    [self.tableView reloadData];
}

- (void)buildSections {
    // ── Master ──
    IGDSSection *master = [IGDSSection new];
    master.header = @"Master";
    master.footer = @"Ativa todos os grupos simultaneamente. canSupportLauncher e isEligibleForLaunch já são forçados pelo hook base.";
    master.rows = @[
        @{@"title":@"★ Ativar tudo (IGDSLauncherConfig)", @"key":@"sci_igds_launcher_all", @"restart":@NO},
    ];

    // ── Liquid Glass ──
    IGDSSection *lg = [IGDSSection new];
    lg.header = @"Liquid Glass";
    lg.footer = @"isLiquidGlass* + canUseInternalLiquidGlassDebugger + isContextMenuMigrationEnabled";
    lg.rows = @[
        @{@"title":@"Liquid Glass (IGDSLauncherConfig)", @"key":@"sci_igds_liquidglass", @"restart":@NO},
    ];

    // ── Prism ──
    IGDSSection *prism = [IGDSSection new];
    prism.header = @"Prism UI";
    prism.footer = @"isPrism* + isIGBPrism* — novo sistema de design do Instagram.";
    prism.rows = @[
        @{@"title":@"Prism UI", @"key":@"sci_igds_prism", @"restart":@NO},
    ];

    // ── Individual LiquidGlass ──
    IGDSSection *lgDetail = [IGDSSection new];
    lgDetail.header = @"LiquidGlass — detalhado";
    lgDetail.footer = @"Cada método individualmente.";
    lgDetail.rows = @[
        @{@"title":@"InAppNotification",         @"key":@"sci_igds_lg_inappnotif",   @"restart":@NO},
        @{@"title":@"Toast",                     @"key":@"sci_igds_lg_toast",         @"restart":@NO},
        @{@"title":@"ToastPeek",                 @"key":@"sci_igds_lg_toastpeek",     @"restart":@NO},
        @{@"title":@"IconBarButton",             @"key":@"sci_igds_lg_iconbarbtn",    @"restart":@NO},
        @{@"title":@"NavContentStylePinning",    @"key":@"sci_igds_lg_navstylepin",   @"restart":@NO},
        @{@"title":@"EaseInOutBlur",             @"key":@"sci_igds_lg_easeinout",     @"restart":@NO},
        @{@"title":@"CGContextBlur",             @"key":@"sci_igds_lg_cgblur",        @"restart":@NO},
        @{@"title":@"OptimizeGlyphRendering",    @"key":@"sci_igds_lg_glyphopt",      @"restart":@NO},
        @{@"title":@"InternalDebugger",          @"key":@"sci_igds_lg_debugger",      @"restart":@NO},
    ];

    // ── Nav & Transitions ──
    IGDSSection *nav = [IGDSSection new];
    nav.header = @"Navegação & Transições";
    nav.footer = nil;
    nav.rows = @[
        @{@"title":@"NavPushRoundedCorners",     @"key":@"sci_igds_nav_rounded",      @"restart":@NO},
        @{@"title":@"TransitionZoom",            @"key":@"sci_igds_nav_tzoom",        @"restart":@NO},
        @{@"title":@"ContextMenuMigration",      @"key":@"sci_igds_nav_ctxmenu",      @"restart":@NO},
        @{@"title":@"NativeBottomsheet",         @"key":@"sci_igds_nav_bottomsheet",  @"restart":@NO},
    ];

    _sections = @[master, lg, prism, lgDetail, nav];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s].header; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return _sections[s].footer; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"IGDS"] ?:
        [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IGDS"];
    NSDictionary *row = _sections[ip.section].rows[ip.row];
    c.textLabel.text = row[@"title"];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:row[@"key"]];
    [sw removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
    objc_setAssociatedObject(sw, "igdsKey", row[@"key"], OBJC_ASSOCIATION_COPY);
    [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    c.accessoryView = sw;
    return c;
}

- (void)swChanged:(UISwitch *)sw {
    NSString *key = objc_getAssociatedObject(sw, "igdsKey");
    [[NSUserDefaults standardUserDefaults] setBool:sw.isOn forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
    SCIIGDSApplyHooksIfAvailable();
}

@end
