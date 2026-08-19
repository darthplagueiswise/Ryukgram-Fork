#import "RYGMobileConfigToolsViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "RYGMobileConfigViewController.h"
#import "../../Utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, RYGMCImportOperation) {
    RYGMCImportOperationNone = 0,
    RYGMCImportOperationNameMapping,
    RYGMCImportOperationOverrides,
};

static void RYGMCResolvedNameCounts(RYGMobileConfig *mc, NSUInteger *configCount, NSUInteger *paramCount) {
    NSUInteger configs = 0;
    NSUInteger params = 0;
    for (RYGMCConfig *config in mc.allConfigs) {
        if (config.name.length) configs++;
        for (RYGMCParam *param in config.params) if (param.name.length) params++;
    }
    if (configCount) *configCount = configs;
    if (paramCount) *paramCount = params;
}

@interface RYGMobileConfigToolsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, assign) RYGMCImportOperation pendingImportOperation;
@end

@implementation RYGMobileConfigToolsViewController

- (instancetype)init { return [super initWithTitle:@"MobileConfig"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [[RYGMobileConfig shared] prepare];
    [self rebuildSections];
}

- (void)rebuildSections {
    __weak typeof(self) weakSelf = self;
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    NSString *path = [mc ryg_nativeDataDirectory];

    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"Open live MobileConfig browser"
                                                     subtitle:@"Full config/parameter IDs, native values, runtime-seen state and overrides"
                                                         icon:[RYGSymbol symbolWithName:@"sliders"]
                                               viewController:[RYGMobileConfigViewController new]];
    RYGSetting *reapply = [RYGSetting buttonCellWithTitle:@"Reapply active overrides"
                                                 subtitle:@"Retry every RyukGram value against Instagram's currently captured native overrides tables"
                                                     icon:[RYGSymbol symbolWithName:@"arrow_cw"]
                                                   action:^{
        RYGMobileConfig *strongMC = [RYGMobileConfig shared];
        [strongMC reapplyOverridesToNativeTable];
        [RYGUtils showToastForDuration:1.4 title:@"Reapply issued"
                             subtitle:[NSString stringWithFormat:@"%lu override%@", (unsigned long)strongMC.overrideCount, strongMC.overrideCount == 1 ? @"" : @"s"]];
        [weakSelf rebuildSections];
    }];

    RYGSetting *importMapping = [RYGSetting buttonCellWithTitle:@"Import id_name_mapping.json"
                                                       subtitle:@"Validate and cache immediately; mirror into the active *.data directory when Instagram exposes it"
                                                           icon:[RYGSymbol symbolWithName:@"download"]
                                                         action:^{ [weakSelf presentJSONPickerForOperation:RYGMCImportOperationNameMapping]; }];
    RYGSetting *exportMapping = [RYGSetting buttonCellWithTitle:@"Export id_name_mapping.json"
                                                       subtitle:@"Share the imported/resolved mapping even when the native *.data directory is not available yet"
                                                           icon:[RYGSymbol symbolWithName:@"share"]
                                                         action:^{ [weakSelf exportNameMapping]; }];

    RYGSetting *importOverrides = [RYGSetting buttonCellWithTitle:@"Import & apply mc_overrides.json"
                                                         subtitle:@"Parse the native config:param grammar, apply through MobileConfig and persist the canonical JSON"
                                                             icon:[RYGSymbol symbolWithName:@"circle_check"]
                                                           action:^{ [weakSelf presentJSONPickerForOperation:RYGMCImportOperationOverrides]; }];
    RYGSetting *exportOverrides = [RYGSetting buttonCellWithTitle:@"Export mc_overrides.json"
                                                         subtitle:@"Share the canonical JSON generated from RyukGram's current override set"
                                                             icon:[RYGSymbol symbolWithName:@"share"]
                                                           action:^{ [weakSelf exportOverrides]; }];
    RYGSetting *clearOverrides = [RYGSetting buttonCellWithTitle:@"Clear RyukGram overrides"
                                                        subtitle:@"Remove native-table values, runtime forcing and the canonical persisted set"
                                                            icon:[RYGSymbol symbolWithName:@"history"]
                                                          action:^{ [weakSelf confirmClearOverrides]; }];
    clearOverrides.titleColor = UIColor.systemRedColor;

    NSString *runtimeFooter = path.length
        ? [NSString stringWithFormat:@"Resolved native data directory\n%@", path]
        : @"The runtime manager and the disk path are independent. This page never invents a user-id path; it waits for an actual Documents/mobileconfig/*.data directory.";

    NSArray *sections = @[
        [RYGSettingsViewController sectionWithHeader:@"Live MobileConfig"
                                              footer:runtimeFooter
                                                rows:@[browser, reapply]],
        [RYGSettingsViewController sectionWithHeader:@"id_name_mapping.json"
                                              footer:@"The mapping is useful immediately from RyukGram's cache. When the native *.data directory appears, the same canonical file is mirrored there automatically."
                                                rows:@[importMapping, exportMapping]],
        [RYGSettingsViewController sectionWithHeader:@"mc_overrides.json"
                                              footer:@"Runtime application uses Instagram's native FBMobileConfigOverridesTable when captured. JSON persistence is a separate step targeting the actual active *.data directory."
                                                rows:@[importOverrides, exportOverrides, clearOverrides]],
    ];
    [self applySettingSections:sections];
}

- (void)presentJSONPickerForOperation:(RYGMCImportOperation)operation {
    self.pendingImportOperation = operation;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { self.pendingImportOperation = RYGMCImportOperationNone; }

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    RYGMCImportOperation operation = self.pendingImportOperation;
    self.pendingImportOperation = RYGMCImportOperationNone;
    if (!url) return;

    BOOL access = [url startAccessingSecurityScopedResource];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:readError.localizedDescription ?: @"Could not read the selected JSON file."];
        return;
    }

    NSError *error = nil;
    RYGMobileConfig *mc = [RYGMobileConfig shared];
    if (operation == RYGMCImportOperationNameMapping) {
        if (![mc ryg_importNameMappingData:data error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Import failed"];
            return;
        }
        NSUInteger namedConfigs = 0, namedParams = 0;
        RYGMCResolvedNameCounts(mc, &namedConfigs, &namedParams);
        NSString *nativePath = [mc ryg_nativeNameMappingPath];
        NSString *storage = nativePath.length ? @"mirrored to native *.data" : @"cached; native mirror pending";
        [RYGUtils showToastForDuration:2.0
                                title:@"Mapping applied"
                             subtitle:[NSString stringWithFormat:@"%lu config names · %lu param names · %@",
                                       (unsigned long)namedConfigs, (unsigned long)namedParams, storage]];
    } else if (operation == RYGMCImportOperationOverrides) {
        NSUInteger count = 0;
        if (![mc ryg_importAndApplyOverridesData:data appliedCount:&count error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Import failed"];
            return;
        }
        [RYGUtils showToastForDuration:1.7 title:@"Overrides imported"
                             subtitle:[NSString stringWithFormat:@"%lu value%@ parsed/applied", (unsigned long)count, count == 1 ? @"" : @"s"]];
    }
    [self rebuildSections];
}

- (void)shareData:(NSData *)data fileName:(NSString *)fileName {
    if (!data.length) return;
    NSURL *url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:fileName];
    NSError *error = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not create the export file."];
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)exportNameMapping {
    NSError *error = nil;
    NSData *data = [[RYGMobileConfig shared] ryg_exportNameMappingData:&error];
    if (!data) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Nothing to export"];
        return;
    }
    [self shareData:data fileName:@"id_name_mapping.json"];
}

- (void)exportOverrides {
    NSError *error = nil;
    NSData *data = [[RYGMobileConfig shared] ryg_exportOverridesData:&error];
    if (!data) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Nothing to export"];
        return;
    }
    [self shareData:data fileName:@"mc_overrides.json"];
}

- (void)confirmClearOverrides {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear MobileConfig overrides?"
                                                                    message:@"Every RyukGram MobileConfig override will return to Instagram's original value and the canonical JSON will be regenerated."
                                                             preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[RYGMobileConfig shared] resetAllOverrides];
        [weakSelf rebuildSections];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end