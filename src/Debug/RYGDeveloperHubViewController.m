#import "RYGDeveloperHubViewController.h"
#import "RYGDeveloperGateViewController.h"
#import "RYGDeveloperExactSurfaceViewController.h"
#import "RYGWordmarkViewController.h"
#import "RYGRuntimeBrowserViewController.h"
#import "RYGEasyGatingViewController.h"
#import "RYGMetaLocalExperimentBrowser.h"
#import "../Features/ExpFlags/RYGMobileConfigToolsViewController.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"

@interface RYGDeveloperHubViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation RYGDeveloperHubViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Developer";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.rowHeight = 54.0;

    self.rows = @[
        @{@"title":@"IGWordMark", @"icon":@"textformat", @"route":@"wordmark"},
        @{@"title":@"Easy Gating Internal", @"icon":@"person.badge.key", @"route":@"easygating"},
        @{@"title":@"MobileConfig", @"icon":@"slider.horizontal.3", @"route":@"mobileconfig"},
        @{@"title":@"Prism UI", @"icon":@"diamond.inset.filled", @"route":@"prism"},
        @{@"title":@"Liquid Glass", @"icon":@"circle.hexagongrid.fill", @"route":@"liquidglass"},
        @{@"title":@"Stories · Tray & Grid", @"icon":@"square.grid.2x2", @"route":@"stories"},
        @{@"title":@"IG-only / Internal-only", @"icon":@"eye.slash", @"route":@"internal"},
        @{@"title":@"Bug Report", @"icon":@"ladybug.fill", @"route":@"bugreport"},
        @{@"title":@"Hidden Settings Rows", @"icon":@"list.bullet.rectangle", @"route":@"settings"},
        @{@"title":@"Direct Dogfooding Settings", @"icon":@"pawprint.fill", @"route":@"dogfood"},
        @{@"title":@"MetaLocalExperiment", @"icon":@"testtube.2", @"route":@"metalocal"},
        @{@"title":@"Runtime Browser · Live", @"icon":@"waveform.path.ecg.rectangle", @"route":@"runtime"},
    ];

    RYGLiquidGlassApplyToViewController(self);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *entry = self.rows[(NSUInteger)indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = entry[@"title"];
    cell.textLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    cell.imageView.image = [UIImage systemImageNamed:entry[@"icon"]];
    cell.imageView.tintColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *route = self.rows[(NSUInteger)indexPath.row][@"route"];
    UIViewController *controller = nil;

    if ([route isEqualToString:@"wordmark"]) {
        controller = [RYGWordmarkViewController new];
    } else if ([route isEqualToString:@"easygating"]) {
        controller = [RYGEasyGatingViewController new];
    } else if ([route isEqualToString:@"mobileconfig"]) {
        controller = [RYGMobileConfigToolsViewController new];
    } else if ([route isEqualToString:@"prism"]) {
        controller = [[RYGDeveloperGateViewController alloc] initWithSurface:RYGDeveloperGateSurfacePrism];
    } else if ([route isEqualToString:@"liquidglass"]) {
        controller = [[RYGDeveloperGateViewController alloc] initWithSurface:RYGDeveloperGateSurfaceLiquidGlass];
    } else if ([route isEqualToString:@"stories"]) {
        controller = [[RYGDeveloperExactSurfaceViewController alloc] initWithSurface:RYGDeveloperExactSurfaceStories];
    } else if ([route isEqualToString:@"internal"]) {
        controller = [[RYGDeveloperGateViewController alloc] initWithSurface:RYGDeveloperGateSurfaceInternal];
    } else if ([route isEqualToString:@"bugreport"]) {
        controller = [[RYGDeveloperExactSurfaceViewController alloc] initWithSurface:RYGDeveloperExactSurfaceBugReport];
    } else if ([route isEqualToString:@"settings"]) {
        controller = [[RYGDeveloperExactSurfaceViewController alloc] initWithSurface:RYGDeveloperExactSurfaceSettingsVisibility];
    } else if ([route isEqualToString:@"dogfood"]) {
        controller = [[RYGDeveloperExactSurfaceViewController alloc] initWithSurface:RYGDeveloperExactSurfaceDirectDogfood];
    } else if ([route isEqualToString:@"metalocal"]) {
        [RYGMetaLocalExperimentBrowser presentFromCurrentViewController];
        return;
    } else if ([route isEqualToString:@"runtime"]) {
        controller = [RYGRuntimeBrowserViewController new];
    }

    if (controller) [self.navigationController pushViewController:controller animated:YES];
}

@end