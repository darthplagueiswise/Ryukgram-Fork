#import "SCIIGDSLauncherConfigViewController.h"
#import <objc/runtime.h>
#import "../Utils.h"

@interface IGDSSection : NSObject
@property (copy) NSString *header, *footer;
@property (copy) NSArray<NSDictionary *> *rows;
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
	SCIUIKit26ConfigureViewController(self);
	SCIUIKit26ConfigureTableView(self.tableView);
	self.tableView.estimatedRowHeight = 60;
	[self buildSections];
}

- (void)buildSections {
	IGDSSection *master = [IGDSSection new];
	master.header = @"Master";
	master.footer = @"Ativa todos os grupos simultaneamente. Se a tela foi aberta após um launch sem nenhum IGDS ativo, o primeiro apply acontece no próximo relaunch.";
	master.rows = @[
		@{@"title":@"★ Ativar tudo (IGDSLauncherConfig)", @"key":@"sci_igds_launcher_all", @"restart":@YES},
	];

	IGDSSection *lg = [IGDSSection new];
	lg.header = @"Liquid Glass";
	lg.footer = @"isLiquidGlass* + canUseInternalLiquidGlassDebugger + isContextMenuMigrationEnabled";
	lg.rows = @[
		@{@"title":@"Liquid Glass (IGDSLauncherConfig)", @"key":@"sci_igds_liquidglass", @"restart":@YES},
	];

	IGDSSection *prism = [IGDSSection new];
	prism.header = @"Prism UI";
	prism.footer = @"isPrism* + isIGBPrism* — novo sistema de design do Instagram.";
	prism.rows = @[
		@{@"title":@"Prism UI", @"key":@"sci_igds_prism", @"restart":@YES},
	];

	IGDSSection *lgDetail = [IGDSSection new];
	lgDetail.header = @"LiquidGlass — detalhado";
	lgDetail.footer = @"Cada método individualmente.";
	lgDetail.rows = @[
		@{@"title":@"InAppNotification",         @"key":@"sci_igds_lg_inappnotif",   @"restart":@YES},
		@{@"title":@"Toast",                     @"key":@"sci_igds_lg_toast",         @"restart":@YES},
		@{@"title":@"ToastPeek",                 @"key":@"sci_igds_lg_toastpeek",     @"restart":@YES},
		@{@"title":@"IconBarButton",             @"key":@"sci_igds_lg_iconbarbtn",    @"restart":@YES},
		@{@"title":@"NavContentStylePinning",    @"key":@"sci_igds_lg_navstylepin",   @"restart":@YES},
		@{@"title":@"EaseInOutBlur",             @"key":@"sci_igds_lg_easeinout",     @"restart":@YES},
		@{@"title":@"CGContextBlur",             @"key":@"sci_igds_lg_cgblur",        @"restart":@YES},
		@{@"title":@"OptimizeGlyphRendering",    @"key":@"sci_igds_lg_glyphopt",      @"restart":@YES},
		@{@"title":@"InternalDebugger",          @"key":@"sci_igds_lg_debugger",      @"restart":@YES},
	];

	IGDSSection *nav = [IGDSSection new];
	nav.header = @"Navegação & Transições";
	nav.footer = nil;
	nav.rows = @[
		@{@"title":@"NavPushRoundedCorners",     @"key":@"sci_igds_nav_rounded",      @"restart":@YES},
		@{@"title":@"TransitionZoom",            @"key":@"sci_igds_nav_tzoom",        @"restart":@YES},
		@{@"title":@"ContextMenuMigration",      @"key":@"sci_igds_nav_ctxmenu",      @"restart":@YES},
		@{@"title":@"NativeBottomsheet",         @"key":@"sci_igds_nav_bottomsheet",  @"restart":@YES},
	];

	_sections = @[master, lg, prism, lgDetail, nav];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return (NSInteger)_sections[s].rows.count; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return _sections[s].header; }
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s { return _sections[s].footer; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"IGDS"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"IGDS"];
	SCIUIKit26ConfigureTableCell(c);
	NSDictionary *row = _sections[ip.section].rows[ip.row];
	c.textLabel.text = row[@"title"];
	c.textLabel.textColor = UIColor.labelColor;
	c.selectionStyle = UITableViewCellSelectionStyleNone;
	UISwitch *sw = [[UISwitch alloc] init];
	sw.on = [SCIUtils getBoolPref:row[@"key"]];
	sw.onTintColor = [SCIUtils SCIColor_Primary];
	[sw removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
	objc_setAssociatedObject(sw, "igdsKey", row[@"key"], OBJC_ASSOCIATION_COPY);
	[sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
	c.accessoryView = sw;
	return c;
}

- (void)swChanged:(UISwitch *)sw {
	NSString *key = objc_getAssociatedObject(sw, "igdsKey");
	[SCIUtils setPref:@(sw.isOn) forKey:key];
}

@end
