#import "RYGMobileConfigToolsViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigViewController.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, RYGMCImportOperation) {
    RYGMCImportOperationNone = 0,
    RYGMCImportOperationNameMapping,
    RYGMCImportOperationOverrides,
};

@interface RYGMobileConfigToolsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, assign) RYGMCImportOperation pendingImportOperation;
@end

@implementation RYGMobileConfigToolsViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MobileConfig";
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.tableView.backgroundColor = [RYGPopupChrome backgroundColor];
    RYGLiquidGlassApplyToViewController(self);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : (section == 1 ? 2 : 3); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"Live MobileConfig" : (section == 1 ? @"id_name_mapping.json" : @"mc_overrides.json"); }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    if (section == 0) {
        NSString *path = [mc ryg_nativeDataDirectory];
        return path.length ? [NSString stringWithFormat:@"Active native data directory\n%@", path] : @"The directory is resolved from Instagram's live getOverridesTablePath. It is never guessed from a user id.";
    }
    if (section == 1) return @"Import writes the validated mapping into the currently active *.data directory and reloads the live catalog.";
    return @"Import applies each value immediately through Instagram's native overrides table and also writes the native JSON representation into the active *.data directory.";
}

- (UITableViewCell *)cellWithTitle:(NSString *)title subtitle:(NSString *)subtitle image:(NSString *)image {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.detailTextLabel.text = subtitle;
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:image];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) return [self cellWithTitle:@"Open live MobileConfig browser" subtitle:@"Runtime configs, live values and overrides" image:@"slider.horizontal.3"];
    if (indexPath.section == 0) return [self cellWithTitle:@"Reapply active overrides" subtitle:@"Write RyukGram's current override set back to the native table" image:@"arrow.clockwise.circle"];
    if (indexPath.section == 1 && indexPath.row == 0) return [self cellWithTitle:@"Import id_name_mapping.json" subtitle:@"Validate, install and reload names" image:@"square.and.arrow.down"];
    if (indexPath.section == 1) return [self cellWithTitle:@"Export id_name_mapping.json" subtitle:@"Share the active native mapping" image:@"square.and.arrow.up"];
    if (indexPath.row == 0) return [self cellWithTitle:@"Import & apply mc_overrides.json" subtitle:@"Apply immediately and persist in the active *.data directory" image:@"bolt.horizontal.circle"];
    if (indexPath.row == 1) return [self cellWithTitle:@"Export mc_overrides.json" subtitle:@"Share current overrides in Instagram's config/param JSON syntax" image:@"square.and.arrow.up"];
    return [self cellWithTitle:@"Clear RyukGram overrides" subtitle:@"Remove every current override and return to native values" image:@"arrow.uturn.backward.circle"];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    if (indexPath.section == 0 && indexPath.row == 0) { [self.navigationController pushViewController:[RYGMobileConfigViewController new] animated:YES]; return; }
    if (indexPath.section == 0) { [mc reapplyOverridesToNativeTable]; [RYGUtils showToastForDuration:1.4 title:@"Reapplied" subtitle:[NSString stringWithFormat:@"%lu overrides", (unsigned long)mc.overrideCount]]; return; }
    if (indexPath.section == 1 && indexPath.row == 0) { [self presentJSONPickerForOperation:RYGMCImportOperationNameMapping]; return; }
    if (indexPath.section == 1) { [self exportNameMapping]; return; }
    if (indexPath.row == 0) { [self presentJSONPickerForOperation:RYGMCImportOperationOverrides]; return; }
    if (indexPath.row == 1) { [self exportOverrides]; return; }
    [self confirmClearOverrides];
}

- (void)presentJSONPickerForOperation:(RYGMCImportOperation)operation {
    self.pendingImportOperation = operation;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    RYGMCImportOperation operation = self.pendingImportOperation;
    self.pendingImportOperation = RYGMCImportOperationNone;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:nil];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!data.length) { [RYGUtils showErrorHUDWithDescription:@"Could not read the selected JSON file."]; return; }
    NSError *error = nil;
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    if (operation == RYGMCImportOperationNameMapping) {
        if (![mc ryg_importNameMappingData:data error:&error]) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Import failed"]; return; }
        [RYGUtils showToastForDuration:1.5 title:@"Imported" subtitle:@"id_name_mapping.json reloaded"];
    } else if (operation == RYGMCImportOperationOverrides) {
        NSUInteger count = 0;
        if (![mc ryg_importAndApplyOverridesData:data appliedCount:&count error:&error]) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Import failed"]; return; }
        [RYGUtils showToastForDuration:1.7 title:@"Applied" subtitle:[NSString stringWithFormat:@"%lu MobileConfig values", (unsigned long)count]];
    }
    [self.tableView reloadData];
}

- (void)shareData:(NSData *)data fileName:(NSString *)fileName {
    if (!data.length) return;
    NSURL *url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:fileName];
    if (![data writeToURL:url options:NSDataWritingAtomic error:nil]) { [RYGUtils showErrorHUDWithDescription:@"Could not create the export file."]; return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) { activity.popoverPresentationController.sourceView = self.view; activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0); }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)exportNameMapping {
    NSError *error = nil;
    NSData *data = [[RYGMobileConfig shared] ryg_exportNameMappingData:&error];
    if (!data) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Nothing to export"]; return; }
    [self shareData:data fileName:@"id_name_mapping.json"];
}

- (void)exportOverrides {
    NSError *error = nil;
    NSData *data = [[RYGMobileConfig shared] ryg_exportOverridesData:&error];
    if (!data) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Nothing to export"]; return; }
    [self shareData:data fileName:@"mc_overrides.json"];
}

- (void)confirmClearOverrides {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear MobileConfig overrides?" message:@"Every RyukGram MobileConfig override will return to Instagram's native value." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [[RYGMobileConfig shared] resetAllOverrides]; [self.tableView reloadData]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
