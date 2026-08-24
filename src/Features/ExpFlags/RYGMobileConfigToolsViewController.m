#import "RYGMobileConfigToolsViewController.h"
#import "RYGFastMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../Utils.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, RYGMCImportOperation) {
    RYGMCImportOperationNone = 0,
    RYGMCImportOperationNameMapping,
    RYGMCImportOperationOverrides,
};

@interface RYGMobileConfigToolsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, assign) RYGMCImportOperation pendingImportOperation;
@property (nonatomic, assign) RYGMCNameMappingImportMode pendingNameMappingMode;
@end

@implementation RYGMobileConfigToolsViewController

- (instancetype)init { return [super initWithTitle:@"MobileConfig"]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [RYGMobileConfig.shared prepare];
    [self rebuildSections];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self rebuildSections];
}

- (BOOL)requireNativeTargetForOperation:(NSString *)operation {
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSString *path = [mobileConfig ryg_nativeOverridesJSONPath];
    if (path.length) return YES;
    [RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"%@ requires Instagram's active MobileConfig session. getOverridesTablePath has not resolved the current Documents/mobileconfig/<user>.data target yet; no App Group path was guessed.", operation ?: @"This operation"]];
    return NO;
}

- (BOOL)syncNativeOrShowError:(NSString *)operation {
    if (![self requireNativeTargetForOperation:operation]) return NO;
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSString *path = [mobileConfig ryg_nativeOverridesJSONPath];
    if ([mobileConfig ryg_syncPersistedJSONToNativeDataDirectory]) return YES;
    [RYGUtils showErrorHUDWithDescription:[NSString stringWithFormat:@"%@ failed to atomically write and verify %@.", operation ?: @"MobileConfig sync", path ?: @"mc_overrides.json"]];
    return NO;
}

- (void)rebuildSections {
    __weak typeof(self) weakSelf = self;
    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSString *nativePath = [mobileConfig ryg_nativeOverridesJSONPath];
    NSString *mappingPath = [mobileConfig ryg_nativeNameMappingPath];

    RYGSetting *status = [RYGSetting staticCellWithTitle:@"Active MobileConfig target"
                                                subtitle:nativePath.length ? nativePath : @"Waiting for active getOverridesTablePath"
                                                    icon:[RYGSymbol symbolWithName:@"document"]];
    RYGSetting *mappingStatus = [RYGSetting staticCellWithTitle:@"Name catalogue"
                                                       subtitle:mappingPath.length ? mappingPath : @"Imported mapping remains cached until the active .data target is available"
                                                           icon:[RYGSymbol symbolWithName:@"list"]];
    RYGSetting *overrideStatus = [RYGSetting staticCellWithTitle:@"Selected overrides"
                                                        subtitle:[NSString stringWithFormat:@"%lu", (unsigned long)mobileConfig.overrideCount]
                                                            icon:[RYGSymbol symbolWithName:@"sliders"]];

    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"Browser"
                                                     subtitle:@"Native descriptor table + imported id_name_mapping names"
                                                         icon:[RYGSymbol symbolWithName:@"sliders"]
                                               viewController:[RYGFastMobileConfigBrowserViewController new]];

    RYGSetting *importNames = [RYGSetting buttonCellWithTitle:@"Import id_name_mapping.json"
                                                     subtitle:@"Replace or merge; active App Group copy becomes authoritative"
                                                         icon:[RYGSymbol symbolWithName:@"download"]
                                                       action:^{ [weakSelf chooseNameImportMode]; }];
    RYGSetting *exportNames = [RYGSetting buttonCellWithTitle:@"Export id_name_mapping.json"
                                                     subtitle:@"Export current catalogue without mutating native state"
                                                         icon:[RYGSymbol symbolWithName:@"share"]
                                                       action:^{ [weakSelf exportNameMapping]; }];

    RYGSetting *importOverrides = [RYGSetting buttonCellWithTitle:@"Import mc_overrides.json"
                                                         subtitle:@"Parse canonical config/parameter semantics and apply exact active-unit PIDs"
                                                             icon:[RYGSymbol symbolWithName:@"download"]
                                                           action:^{ [weakSelf presentJSONPicker:RYGMCImportOperationOverrides]; }];
    RYGSetting *exportOverrides = [RYGSetting buttonCellWithTitle:@"Export mc_overrides.json"
                                                         subtitle:@"Export current override document without rewriting the App Group"
                                                             icon:[RYGSymbol symbolWithName:@"share"]
                                                           action:^{ [weakSelf exportOverrides]; }];
    RYGSetting *applyOverrides = [RYGSetting buttonCellWithTitle:@"Apply active overrides"
                                                        subtitle:@"Write StartupConfigs + atomically verify native mc_overrides.json"
                                                            icon:[RYGSymbol symbolWithName:@"arrow.clockwise"]
                                                          action:^{
        if (![weakSelf requireNativeTargetForOperation:@"Apply active overrides"]) return;
        [mobileConfig reapplyOverridesToNativeTable];
        if (![weakSelf syncNativeOrShowError:@"Apply active overrides"]) return;
        NSString *path = [mobileConfig ryg_nativeOverridesJSONPath];
        [RYGUtils showToastForDuration:1.5 title:@"Overrides applied + verified" subtitle:path.lastPathComponent ?: @"mc_overrides.json"];
        [weakSelf rebuildSections];
    }];
    RYGSetting *clearOverrides = [RYGSetting buttonCellWithTitle:@"Clear overrides"
                                                        subtitle:@"Remove selected values from native table and document"
                                                            icon:[RYGSymbol symbolWithName:@"trash"]
                                                          action:^{ [weakSelf confirmClearOverrides]; }];
    clearOverrides.titleColor = UIColor.systemRedColor;

    NSString *footer = nativePath.length
        ? [NSString stringWithFormat:@"Native authority: %@\nNo App Group UUID or account leaf is synthesized by RyukGram.", nativePath]
        : @"Native target unresolved. The browser can still display imported names, but native writes remain disabled until Instagram exposes its active session path.";

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:@"Status" footer:nil rows:@[status, mappingStatus, overrideStatus]],
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[browser]],
        [RYGSettingsViewController sectionWithHeader:@"Names" footer:nil rows:@[importNames, exportNames]],
        [RYGSettingsViewController sectionWithHeader:@"Overrides" footer:footer rows:@[importOverrides, exportOverrides, applyOverrides, clearOverrides]],
    ]];
}

- (void)chooseNameImportMode {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Import id_name_mapping.json" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Replace" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        weakSelf.pendingNameMappingMode = RYGMCNameMappingImportModeReplace;
        [weakSelf presentJSONPicker:RYGMCImportOperationNameMapping];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Merge" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        weakSelf.pendingNameMappingMode = RYGMCNameMappingImportModeMerge;
        [weakSelf presentJSONPicker:RYGMCImportOperationNameMapping];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        sheet.popoverPresentationController.sourceView = self.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), 80.0, 1.0, 1.0);
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentJSONPicker:(RYGMCImportOperation)operation {
    self.pendingImportOperation = operation;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    self.pendingImportOperation = RYGMCImportOperationNone;
}

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
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:readError.localizedDescription ?: @"Could not read JSON"];
        return;
    }

    RYGMobileConfig *mobileConfig = RYGMobileConfig.shared;
    NSError *error = nil;
    if (operation == RYGMCImportOperationNameMapping) {
        if (![mobileConfig ryg_importNameMappingData:data mode:self.pendingNameMappingMode error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Mapping import failed"];
            return;
        }
        [mobileConfig reloadFromRuntime];
        if ([self requireNativeTargetForOperation:@"Mapping import"] && ![self syncNativeOrShowError:@"Mapping import"]) return;
        NSUInteger configs = 0, params = 0;
        for (RYGMCConfig *config in mobileConfig.allConfigs) {
            if (config.name.length) configs++;
            for (RYGMCParam *param in config.params) if (param.name.length) params++;
        }
        [RYGUtils showToastForDuration:1.5
                                title:self.pendingNameMappingMode == RYGMCNameMappingImportModeReplace ? @"Mapping replaced" : @"Mapping merged"
                             subtitle:[NSString stringWithFormat:@"%lu configs · %lu params", (unsigned long)configs, (unsigned long)params]];
        [self rebuildSections];
        return;
    }

    if (operation == RYGMCImportOperationOverrides) {
        if (![self requireNativeTargetForOperation:@"Override import"]) return;
        NSUInteger applied = 0;
        if (![mobileConfig ryg_importAndApplyOverridesData:data appliedCount:&applied error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Override import failed"];
            return;
        }
        if (![self syncNativeOrShowError:@"Override import"]) return;
        [RYGUtils showToastForDuration:1.5 title:@"Overrides imported + verified" subtitle:[NSString stringWithFormat:@"%lu applied", (unsigned long)applied]];
        [self rebuildSections];
    }
}

- (void)shareData:(NSData *)data fileName:(NSString *)fileName {
    if (!data.length) return;
    NSURL *url = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:fileName];
    NSError *error = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not create export"];
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
    NSData *data = [RYGMobileConfig.shared ryg_exportNameMappingData:&error];
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No mapping available"];
        return;
    }
    [self shareData:data fileName:@"id_name_mapping.json"];
}

- (void)exportOverrides {
    NSError *error = nil;
    NSData *data = [RYGMobileConfig.shared ryg_exportOverridesData:&error];
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No overrides available"];
        return;
    }
    [self shareData:data fileName:@"mc_overrides.json"];
}

- (void)confirmClearOverrides {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear overrides?" message:@"This removes the selected native MobileConfig overrides for the active account." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        if (![weakSelf requireNativeTargetForOperation:@"Clear overrides"]) return;
        [RYGMobileConfig.shared resetAllOverrides];
        if (![weakSelf syncNativeOrShowError:@"Clear overrides"]) return;
        [weakSelf rebuildSections];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
