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

@interface RYGMobileConfigToolsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, assign) RYGMCImportOperation pendingImportOperation;
@end

@implementation RYGMobileConfigToolsViewController

- (instancetype)init {
    return [super initWithTitle:@"MobileConfig"];
}

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
                                                     subtitle:@"Runtime configs, original values and overrides"
                                                         icon:[RYGSymbol symbolWithName:@"sliders"]
                                               viewController:[RYGMobileConfigViewController new]];
    RYGSetting *reapply = [RYGSetting buttonCellWithTitle:@"Reapply active overrides"
                                                 subtitle:@"Write RyukGram's current override set back to Instagram's native table"
                                                     icon:[RYGSymbol symbolWithName:@"arrow_cw"]
                                                   action:^{
        RYGMobileConfig *strongMC = [RYGMobileConfig shared];
        [strongMC reapplyOverridesToNativeTable];
        [RYGUtils showToastForDuration:1.4 title:@"Reapplied" subtitle:[NSString stringWithFormat:@"%lu overrides", (unsigned long)strongMC.overrideCount]];
        [weakSelf rebuildSections];
    }];

    RYGSetting *importMapping = [RYGSetting buttonCellWithTitle:@"Import id_name_mapping.json"
                                                       subtitle:@"Validate, install in the active *.data directory and reload names"
                                                           icon:[RYGSymbol symbolWithName:@"download"]
                                                         action:^{ [weakSelf presentJSONPickerForOperation:RYGMCImportOperationNameMapping]; }];
    RYGSetting *exportMapping = [RYGSetting buttonCellWithTitle:@"Export id_name_mapping.json"
                                                       subtitle:@"Share the mapping currently resolved from Instagram's native data directory"
                                                           icon:[RYGSymbol symbolWithName:@"share"]
                                                         action:^{ [weakSelf exportNameMapping]; }];

    RYGSetting *importOverrides = [RYGSetting buttonCellWithTitle:@"Import & apply mc_overrides.json"
                                                         subtitle:@"Apply immediately and persist using Instagram's config/param JSON grammar"
                                                             icon:[RYGSymbol symbolWithName:@"circle_check"]
                                                           action:^{ [weakSelf presentJSONPickerForOperation:RYGMCImportOperationOverrides]; }];
    RYGSetting *exportOverrides = [RYGSetting buttonCellWithTitle:@"Export mc_overrides.json"
                                                         subtitle:@"Share the currently active RyukGram overrides"
                                                             icon:[RYGSymbol symbolWithName:@"share"]
                                                           action:^{ [weakSelf exportOverrides]; }];
    RYGSetting *clearOverrides = [RYGSetting buttonCellWithTitle:@"Clear RyukGram overrides"
                                                        subtitle:@"Return every RyukGram MobileConfig override to Instagram's original value"
                                                            icon:[RYGSymbol symbolWithName:@"history"]
                                                          action:^{ [weakSelf confirmClearOverrides]; }];
    clearOverrides.titleColor = UIColor.systemRedColor;

    NSString *runtimeFooter = path.length
        ? [NSString stringWithFormat:@"Active native data directory\n%@", path]
        : @"The active directory is resolved from Instagram's live getOverridesTablePath. No user-id path is guessed.";

    NSArray *sections = @[
        [RYGSettingsViewController sectionWithHeader:@"Live MobileConfig"
                                              footer:runtimeFooter
                                                rows:@[browser, reapply]],
        [RYGSettingsViewController sectionWithHeader:@"id_name_mapping.json"
                                              footer:@"Import and export use the mapping inside the currently active native *.data directory."
                                                rows:@[importMapping, exportMapping]],
        [RYGSettingsViewController sectionWithHeader:@"mc_overrides.json"
                                              footer:@"Imports are applied through Instagram's native override table and persisted in the active *.data directory."
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

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    self.pendingImportOperation = RYGMCImportOperationNone;
}

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
        [RYGUtils showToastForDuration:1.5 title:@"Imported" subtitle:@"id_name_mapping.json reloaded"];
    } else if (operation == RYGMCImportOperationOverrides) {
        NSUInteger count = 0;
        if (![mc ryg_importAndApplyOverridesData:data appliedCount:&count error:&error]) {
            [RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Import failed"];
            return;
        }
        [RYGUtils showToastForDuration:1.7 title:@"Applied" subtitle:[NSString stringWithFormat:@"%lu MobileConfig values", (unsigned long)count]];
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
                                                                    message:@"Every RyukGram MobileConfig override will return to Instagram's original value."
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
