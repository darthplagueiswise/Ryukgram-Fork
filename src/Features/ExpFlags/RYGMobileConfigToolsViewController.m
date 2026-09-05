#import "RYGMobileConfigToolsViewController.h"
#import "RYGFastMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../Utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, RYGMCImportOperation) {
    RYGMCImportOperationNone = 0,
    RYGMCImportOperationOverrides,
    RYGMCImportOperationNameMapping,
};

@interface RYGMobileConfigToolsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, assign) RYGMCImportOperation pendingImportOperation;
@end

@implementation RYGMobileConfigToolsViewController

- (instancetype)init { return [super initWithTitle:@"MobileConfig Runtime"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [RYGMobileConfig.shared prepare];
    [self rebuildSections];
}

- (void)rebuildSections {
    __weak typeof(self) weakSelf = self;
    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"MobileConfig Runtime Browser"
                                                     subtitle:@"id_name_mapping ∪ current iOS runtime table · typed edits only when runtime-linked"
                                                         icon:[RYGSymbol symbolWithName:@"sliders"]
                                               viewController:[RYGFastMobileConfigBrowserViewController new]];

    RYGSetting *importNames = [RYGSetting buttonCellWithTitle:@"Import id_name_mapping.json"
                                                     subtitle:@"Choose Merge or Replace after selecting a canonical mapping file"
                                                         icon:[RYGSymbol symbolWithName:@"download"]
                                                       action:^{ [weakSelf presentJSONPicker:RYGMCImportOperationNameMapping]; }];
    RYGSetting *exportNames = [RYGSetting buttonCellWithTitle:@"Export id_name_mapping.json"
                                                     subtitle:@"Exports the effective native + imported name catalogue"
                                                         icon:[RYGSymbol symbolWithName:@"share"]
                                                       action:^{ [weakSelf exportNameMapping]; }];

    RYGSetting *importOverrides = [RYGSetting buttonCellWithTitle:@"Import mc_overrides.json / runtime snapshot"
                                                         subtitle:@"Known runtime-linked rows are type-checked; unknown native rows remain preserved in the canonical document"
                                                             icon:[RYGSymbol symbolWithName:@"download"]
                                                           action:^{ [weakSelf presentJSONPicker:RYGMCImportOperationOverrides]; }];
    RYGSetting *exportOverrides = [RYGSetting buttonCellWithTitle:@"Export active mc_overrides.json"
                                                         subtitle:@"Native file is the baseline; unknown and QE rows survive round-trip"
                                                             icon:[RYGSymbol symbolWithName:@"share"]
                                                           action:^{ [weakSelf exportOverrides]; }];
    RYGSetting *exportSnapshot = [RYGSetting buttonCellWithTitle:@"Export typed runtime snapshot"
                                                        subtitle:@"Every runtime PID, native type, effective value and explicit RyukGram override"
                                                            icon:[RYGSymbol symbolWithName:@"share"]
                                                          action:^{ [weakSelf exportRuntimeSnapshot]; }];
    RYGSetting *applyOverrides = [RYGSetting buttonCellWithTitle:@"Apply active typed overrides"
                                                        subtitle:@"Replays only runtime-linked BOOL / INT64 / STRING / DOUBLE overrides"
                                                            icon:[RYGSymbol symbolWithName:@"arrow.clockwise"]
                                                          action:^{
        RYGMobileConfig *mc = RYGMobileConfig.shared;
        [mc reapplyOverridesToNativeTable];
        [RYGUtils showToastForDuration:1.5 title:@"MobileConfig overrides applied" subtitle:[NSString stringWithFormat:@"%lu active", (unsigned long)mc.overrideCount]];
    }];
    RYGSetting *diagnostics = [RYGSetting buttonCellWithTitle:@"MobileConfig diagnostics"
                                                     subtitle:@"Resolved native paths + runtime-linked / mapping-only counts"
                                                         icon:[RYGSymbol symbolWithName:@"info"]
                                                       action:^{ [weakSelf showDiagnostics]; }];
    RYGSetting *clearOverrides = [RYGSetting buttonCellWithTitle:@"Clear RyukGram typed overrides"
                                                        subtitle:@"Does not delete Instagram's mapping/schema files"
                                                            icon:[RYGSymbol symbolWithName:@"trash"]
                                                          action:^{ [weakSelf confirmClearOverrides]; }];
    clearOverrides.titleColor = UIColor.systemRedColor;

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[browser]],
        [RYGSettingsViewController sectionWithHeader:@"Names"
                                               footer:@"id_name_mapping.json is a discovery/name layer. A row absent from the iOS runtime table remains visible but read-only; importing a mapping never fabricates a PID or ABI."
                                                 rows:@[importNames, exportNames]],
        [RYGSettingsViewController sectionWithHeader:@"Overrides"
                                               footer:@"FBSharedFramework is authoritative for type: 1=BOOL, 2=INT64, 3=STRING, 4=DOUBLE. Export starts from Instagram's native mc_overrides.json when available and preserves unknown rows."
                                                 rows:@[importOverrides, exportOverrides, exportSnapshot, applyOverrides, diagnostics, clearOverrides]],
    ]];
}

- (void)presentJSONPicker:(RYGMCImportOperation)operation {
    self.pendingImportOperation = operation;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { (void)controller; self.pendingImportOperation = RYGMCImportOperationNone; }

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    RYGMCImportOperation operation = self.pendingImportOperation;
    self.pendingImportOperation = RYGMCImportOperationNone;
    if (!url) return;
    BOOL access = [url startAccessingSecurityScopedResource];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&readError];
    if (access) [url stopAccessingSecurityScopedResource];
    if (!data.length) { [RYGUtils showErrorHUDWithDescription:readError.localizedDescription ?: @"Could not read JSON"]; return; }

    if (operation == RYGMCImportOperationNameMapping) {
        [self chooseNameMappingModeForData:data sourceView:self.view];
        return;
    }
    if (operation != RYGMCImportOperationOverrides) return;

    NSError *error = nil; NSUInteger applied = 0;
    BOOL snapshot = [RYGMobileConfig.shared ryg_isRuntimeSnapshotData:data];
    BOOL ok = snapshot
        ? [RYGMobileConfig.shared ryg_importRuntimeSnapshotOverridesData:data appliedCount:&applied error:&error]
        : [RYGMobileConfig.shared ryg_importAndApplyOverridesData:data appliedCount:&applied error:&error];
    if (!ok) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"MobileConfig override import failed"]; return; }
    [RYGUtils showToastForDuration:1.5
                             title:snapshot ? @"Runtime snapshot imported" : @"mc_overrides imported"
                          subtitle:[NSString stringWithFormat:@"%lu typed runtime row(s) applied", (unsigned long)applied]];
    [self rebuildSections];
}

- (void)chooseNameMappingModeForData:(NSData *)data sourceView:(UIView *)sourceView {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Import id_name_mapping.json"
                                                                    message:@"Merge keeps existing native/imported names that are absent from this file. Replace makes this import RyukGram's complete mapping overlay."
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    void (^perform)(RYGMCNameMappingImportMode) = ^(RYGMCNameMappingImportMode mode) {
        NSError *error = nil;
        if (![RYGMobileConfig.shared ryg_importNameMappingData:data mode:mode error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"id_name_mapping import failed"];
            return;
        }
        [RYGMobileConfig.shared reloadFromRuntime];
        [RYGUtils showToastForDuration:1.5 title:@"id_name_mapping imported" subtitle:mode == RYGMCNameMappingImportModeMerge ? @"Merged with current catalogue" : @"Replaced RyukGram mapping overlay"];
        [weakSelf rebuildSections];
    };
    [sheet addAction:[UIAlertAction actionWithTitle:@"Merge" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ perform(RYGMCNameMappingImportModeMerge); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){ perform(RYGMCNameMappingImportModeReplace); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = sourceView;
        sheet.popoverPresentationController.sourceRect = sourceView.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)shareData:(NSData *)data fileName:(NSString *)fileName {
    if (!data.length) return;
    NSURL *url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:fileName];
    NSError *error = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not create export"]; return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        activity.popoverPresentationController.sourceView = self.view;
        activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)exportNameMapping {
    NSError *error = nil; NSData *data = [RYGMobileConfig.shared ryg_exportNameMappingData:&error];
    if (!data.length) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No id_name_mapping is available"]; return; }
    [self shareData:data fileName:@"id_name_mapping.json"];
}

- (void)exportOverrides {
    NSError *error = nil; NSData *data = [RYGMobileConfig.shared ryg_exportOverridesData:&error];
    if (!data.length) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No overrides available"]; return; }
    [self shareData:data fileName:@"mc_overrides.json"];
}

- (void)exportRuntimeSnapshot {
    [RYGUtils showToastForDuration:1.0 title:@"Reading runtime configuration" subtitle:@"Export continues in the background"];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil; NSData *data = [RYGMobileConfig.shared ryg_exportRuntimeSnapshotData:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf; if (!self) return;
            if (!data.length) { [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No runtime configuration is available"]; return; }
            [self shareData:data fileName:@"ryukgram_mobileconfig_runtime_snapshot.json"];
        });
    });
}

- (void)showDiagnostics {
    RYGMobileConfig *mc = RYGMobileConfig.shared;
    NSArray<RYGMCConfig *> *configs = [mc allConfigsIncludingMappingOnly];
    NSUInteger linkedConfigs = 0, mappingOnlyConfigs = 0, linkedParams = 0, mappingOnlyParams = 0;
    for (RYGMCConfig *config in configs) {
        if (config.hasRuntimeBacking) linkedConfigs++; else mappingOnlyConfigs++;
        for (RYGMCParam *param in config.params) { if (param.isRuntimeBacked) linkedParams++; else mappingOnlyParams++; }
    }
    NSString *message = [NSString stringWithFormat:
        @"Native data directory:\n%@\n\nid_name_mapping:\n%@\n\nmc_overrides:\n%@\n\nConfigs: %lu runtime linked · %lu mapping only\nParameters: %lu runtime linked · %lu mapping only\nActive RyukGram overrides: %lu",
        [mc ryg_nativeDataDirectory] ?: @"not resolved",
        [mc ryg_nativeNameMappingPath] ?: @"not resolved",
        [mc ryg_nativeOverridesJSONPath] ?: @"not resolved",
        (unsigned long)linkedConfigs, (unsigned long)mappingOnlyConfigs,
        (unsigned long)linkedParams, (unsigned long)mappingOnlyParams,
        (unsigned long)mc.overrideCount];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MobileConfig diagnostics" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmClearOverrides {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear RyukGram overrides?" message:@"Instagram-owned mapping/schema files are not deleted." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [RYGMobileConfig.shared resetAllOverrides]; [weakSelf rebuildSections];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
