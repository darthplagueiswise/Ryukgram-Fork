#import "RYGMobileConfigToolsViewController.h"
#import "RYGMobileConfigViewController.h"
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Imports may have happened before Instagram exposed its context manager.
    // Every time the native tools screen becomes active, flush the persisted
    // canonical files into the manager-resolved <user>.data unit if available.
    [RYGMobileConfig.shared ryg_syncPersistedJSONToNativeDataDirectory];
}

- (void)rebuildSections {
    __weak typeof(self) weakSelf = self;

    // Keep the original RyukGram MobileConfig list/detail UI as the primary
    // browser. Its BOOL editor is the native UISwitch-based control the tweak
    // historically used; the newer experimental browser must not replace it.
    RYGSetting *browser = [RYGSetting navigationCellWithTitle:@"Browser"
                                                     subtitle:@""
                                                         icon:[RYGSymbol symbolWithName:@"sliders"]
                                               viewController:[RYGMobileConfigViewController new]];

    RYGSetting *importNames = [RYGSetting buttonCellWithTitle:@"Import id_name_mapping.json"
                                                     subtitle:@""
                                                         icon:[RYGSymbol symbolWithName:@"download"]
                                                       action:^{ [weakSelf chooseNameImportMode]; }];
    RYGSetting *exportNames = [RYGSetting buttonCellWithTitle:@"Export id_name_mapping.json"
                                                     subtitle:@""
                                                         icon:[RYGSymbol symbolWithName:@"share"]
                                                       action:^{ [weakSelf exportNameMapping]; }];

    RYGSetting *importOverrides = [RYGSetting buttonCellWithTitle:@"Import mc_overrides.json"
                                                         subtitle:@""
                                                             icon:[RYGSymbol symbolWithName:@"download"]
                                                           action:^{ [weakSelf presentJSONPicker:RYGMCImportOperationOverrides]; }];
    RYGSetting *exportOverrides = [RYGSetting buttonCellWithTitle:@"Export mc_overrides.json"
                                                         subtitle:@""
                                                             icon:[RYGSymbol symbolWithName:@"share"]
                                                           action:^{ [weakSelf exportOverrides]; }];
    RYGSetting *applyOverrides = [RYGSetting buttonCellWithTitle:@"Apply active overrides"
                                                        subtitle:@""
                                                            icon:[RYGSymbol symbolWithName:@"arrow.clockwise"]
                                                          action:^{
        [RYGMobileConfig.shared reapplyOverridesToNativeTable];
        [RYGMobileConfig.shared ryg_syncPersistedJSONToNativeDataDirectory];
        [RYGUtils showToastForDuration:1.0 title:@"Overrides applied" subtitle:nil];
    }];
    RYGSetting *clearOverrides = [RYGSetting buttonCellWithTitle:@"Clear overrides"
                                                        subtitle:@""
                                                            icon:[RYGSymbol symbolWithName:@"trash"]
                                                          action:^{ [weakSelf confirmClearOverrides]; }];
    clearOverrides.titleColor = UIColor.systemRedColor;

    [self applySettingSections:@[
        [RYGSettingsViewController sectionWithHeader:nil footer:nil rows:@[browser]],
        [RYGSettingsViewController sectionWithHeader:@"Names" footer:nil rows:@[importNames, exportNames]],
        [RYGSettingsViewController sectionWithHeader:@"Overrides" footer:nil rows:@[importOverrides, exportOverrides, applyOverrides, clearOverrides]],
    ]];
}

- (void)chooseNameImportMode {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Import id_name_mapping.json"
                                                                    message:nil
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
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
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
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
        [mobileConfig ryg_syncPersistedJSONToNativeDataDirectory];
        NSUInteger configs = 0, params = 0;
        for (RYGMCConfig *config in mobileConfig.allConfigs) {
            if (config.name.length) configs++;
            for (RYGMCParam *param in config.params) if (param.name.length) params++;
        }
        [RYGUtils showToastForDuration:1.5
                                title:self.pendingNameMappingMode == RYGMCNameMappingImportModeReplace ? @"Mapping replaced" : @"Mapping merged"
                             subtitle:[NSString stringWithFormat:@"%lu configs · %lu params", (unsigned long)configs, (unsigned long)params]];
        return;
    }

    if (operation == RYGMCImportOperationOverrides) {
        NSUInteger applied = 0;
        if (![mobileConfig ryg_importAndApplyOverridesData:data appliedCount:&applied error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Override import failed"];
            return;
        }
        [mobileConfig ryg_syncPersistedJSONToNativeDataDirectory];
        [RYGUtils showToastForDuration:1.2 title:@"Overrides imported" subtitle:[NSString stringWithFormat:@"%lu applied", (unsigned long)applied]];
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
    [RYGMobileConfig.shared ryg_syncPersistedJSONToNativeDataDirectory];
    NSError *error = nil;
    NSData *data = [RYGMobileConfig.shared ryg_exportNameMappingData:&error];
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No mapping available"];
        return;
    }
    [self shareData:data fileName:@"id_name_mapping.json"];
}

- (void)exportOverrides {
    [RYGMobileConfig.shared ryg_syncPersistedJSONToNativeDataDirectory];
    NSError *error = nil;
    NSData *data = [RYGMobileConfig.shared ryg_exportOverridesData:&error];
    if (!data.length) {
        [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"No overrides available"];
        return;
    }
    [self shareData:data fileName:@"mc_overrides.json"];
}

- (void)confirmClearOverrides {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear overrides?" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [RYGMobileConfig.shared resetAllOverrides];
        [RYGMobileConfig.shared ryg_syncPersistedJSONToNativeDataDirectory];
        [weakSelf rebuildSections];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end