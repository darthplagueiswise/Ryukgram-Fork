#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperFeatureViewController.h"
#import "RYGRuntimeBrowserViewController.h"
#import "../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGDeveloperHubViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation RYGDeveloperHubViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Developer";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.rows = @[
        @{@"title":@"IGWordMark", @"subtitle":@"1A / 1B preview plus live wordmark gates", @"icon":@"textformat", @"keywords":@[@"wordmark", @"igds_wordmark", @"BCNWordmark"], @"wordmark":@YES},
        @{@"title":@"Easy Gating Internal", @"subtitle":@"Employee, internal, dogfood, metamate and IG-only BOOL gates", @"icon":@"person.badge.key", @"keywords":@[@"employee", @"internal", @"dogfood", @"dogfooding", @"metamate", @"igonly", @"ig_only"], @"apply":@YES},
        @{@"title":@"MobileConfig", @"subtitle":@"Live table, id_name_mapping.json and mc_overrides.json", @"icon":@"slider.horizontal.3", @"special":@"mobileconfig"},
        @{@"title":@"Prism UI", @"subtitle":@"IGDS Prism runtime and MobileConfig options", @"icon":@"diamond.inset.filled", @"keywords":@[@"prism", @"igdsprism", @"isPrismEnabled", @"isRevertedPrismColorEnabled"], @"apply":@YES},
        @{@"title":@"Liquid Glass", @"subtitle":@"IGLiquidGlass, IGDSGlassButton and interactive glass gates", @"icon":@"circle.hexagongrid.fill", @"keywords":@[@"liquidglass", @"liquid_glass", @"igdsglass", @"glassbutton", @"IGLiquidGlassInteractiveTabBar", @"lucent"], @"apply":@YES},
        @{@"title":@"Stories — Tray & Grid", @"subtitle":@"Portable Story Tray, Story Tray and Story Grid", @"icon":@"square.grid.2x2", @"keywords":@[@"storytray", @"story_tray", @"storiestray", @"storygrid", @"story_grid", @"portableStoryTray"], @"apply":@YES},
        @{@"title":@"Liquid Glass Throwback", @"subtitle":@"Throwback feed and alternate header-related gates", @"icon":@"arrow.counterclockwise.circle", @"keywords":@[@"throwback", @"feed_timeline_throwback", @"IGThrowbackFeed", @"header"], @"apply":@YES},
        @{@"title":@"IG-only / Internal-only", @"subtitle":@"Hidden IG-only and internal-only surfaces", @"icon":@"eye.slash", @"keywords":@[@"igonly", @"ig_only", @"internalonly", @"internal_only", @"isInternalOnly", @"IGPartnerAnalyticsIsIGOnly"], @"apply":@YES},
        @{@"title":@"Bug Report", @"subtitle":@"Logged-out, Dogfooding Assistant, internal settings and sandbox gates", @"icon":@"ladybug.fill", @"keywords":@[@"bugreport", @"bug_report", @"dogfoodingassistant", @"dogfooding_assistant", @"loggedout", @"logged_out", @"sandbox", @"rageshake"], @"apply":@YES},
        @{@"title":@"Hidden Settings Rows", @"subtitle":@"Visibility gates for internal/settings/menu/row surfaces", @"icon":@"list.bullet.rectangle", @"keywords":@[@"settings", @"settingsrow", @"menurow", @"hiddenrow", @"shouldhide", @"shouldshow", @"visible", @"internalsettings"], @"apply":@YES},
        @{@"title":@"Direct Dogfooding Settings", @"subtitle":@"IGDogfoodingSettings, sessions and direct dogfood gates", @"icon":@"pawprint.fill", @"keywords":@[@"IGDogfoodingSettings", @"dogfoodingsettings", @"dogfoodingsessions", @"dogfood", @"dogfooding", @"direct"], @"apply":@YES},
        @{@"title":@"MetaLocalExperiment", @"subtitle":@"Meta local experiment runtime surface", @"icon":@"testtube.2", @"keywords":@[@"MetaLocalExperiment", @"localexperiment", @"experimentlogger"], @"apply":@YES},
        @{@"title":@"Runtime Browser · Live", @"subtitle":@"Select executable/framework; observe native BOOL values and hook them", @"icon":@"waveform.path.ecg.rectangle", @"special":@"runtime"},
    ];
    RYGLiquidGlassApplyToViewController(self);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"Every feature surface is generated from the currently loaded Instagram executable/frameworks and the live MobileConfig table. No pre-rendered runtime symbol table is shipped."; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *entry = self.rows[indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = entry[@"title"];
    cell.detailTextLabel.text = entry[@"subtitle"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:entry[@"icon"]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = self.rows[indexPath.row];
    NSString *special = entry[@"special"];
    UIViewController *controller = nil;
    if ([special isEqualToString:@"mobileconfig"]) controller = [RYGMobileConfigToolsViewController new];
    else if ([special isEqualToString:@"runtime"]) controller = [RYGRuntimeBrowserViewController new];
    else controller = [[RYGDeveloperFeatureViewController alloc] initWithTitle:entry[@"title"] keywords:entry[@"keywords"] ?: @[] wordmarkPreview:[entry[@"wordmark"] boolValue] allowsRecommendedApply:[entry[@"apply"] boolValue]];
    if (controller) [self.navigationController pushViewController:controller animated:YES];
}

@end
