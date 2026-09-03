#import "RYGMobileConfigBackup.h"
#import "RYGMobileConfig.h"
#import "../../RYGTempFiles.h"
#import "../../Utils.h"

static NSString *const kRYGMCBackupMagic = @"ryukgram_mobileconfig";

@interface _RYGMCBackupPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^onPicked)(NSURL *url);
@property (nonatomic, copy) void (^onExported)(void);
@property (nonatomic, strong) _RYGMCBackupPicker *pin;
@end

@implementation _RYGMCBackupPicker

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (self.onExported) self.onExported();
    else if (self.onPicked && urls.firstObject) self.onPicked(urls.firstObject);
    self.pin = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { self.pin = nil; }

@end

@implementation RYGMobileConfigBackup

+ (NSString *)timestamp {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyyMMdd-HHmmss";
    return [f stringFromDate:[NSDate date]];
}

+ (void)presentExportFrom:(UIViewController *)presenter {
    NSArray<NSDictionary *> *entries = [[RYGMobileConfig shared] exportEntries];
    if (!entries.count) {
        RYGNotifyInfo(RYG_NOTIF_BACKUP, RYGLocalized(@"Nothing to export"), nil);
        return;
    }

    NSDictionary *envelope = @{
        kRYGMCBackupMagic: @YES,
        @"version": @1,
        @"exported_at": @((long long)[[NSDate date] timeIntervalSince1970]),
        @"ig_version": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
        @"entries": entries,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:envelope
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    NSString *name = [NSString stringWithFormat:@"RyukGram-mobileconfig-%@.json", [self timestamp]];
    NSURL *out = [RYGTempFiles claimNamedFile:name ttl:900 tag:@"mcbak"];
    if (!data || ![data writeToURL:out options:NSDataWritingAtomic error:nil]) {
        [RYGTempFiles releaseURL:out];
        RYGNotifyError(RYG_NOTIF_BACKUP, RYGLocalized(@"Backup failed"), RYGLocalized(@"Could not write backup file."));
        return;
    }

    _RYGMCBackupPicker *helper = [_RYGMCBackupPicker new];
    helper.pin = helper;
    helper.onExported = ^{
        RYGNotifySuccess(RYG_NOTIF_BACKUP, RYGLocalized(@"Backup exported"), nil);
    };
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[out]];
    p.delegate = helper;
    [presenter presentViewController:p animated:YES completion:nil];
}

+ (void)presentImportFrom:(UIViewController *)presenter completion:(void (^)(void))completion {
    _RYGMCBackupPicker *helper = [_RYGMCBackupPicker new];
    helper.pin = helper;
    helper.onPicked = ^(NSURL *url) {
        BOOL access = [url startAccessingSecurityScopedResource];
        NSData *data = [NSData dataWithContentsOfURL:url];
        if (access) [url stopAccessingSecurityScopedResource];
        [self handleImportData:data from:presenter completion:completion];
    };
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.json", @"public.text", @"public.data"] inMode:UIDocumentPickerModeImport];
    p.allowsMultipleSelection = NO;
    p.delegate = helper;
    [presenter presentViewController:p animated:YES completion:nil];
}

+ (void)handleImportData:(NSData *)data from:(UIViewController *)presenter completion:(void (^)(void))completion {
    id parsed = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *root = [parsed isKindOfClass:NSDictionary.class] ? parsed : nil;
    NSArray *entries = [root[@"entries"] isKindOfClass:NSArray.class] ? root[@"entries"] : nil;
    if (![root[kRYGMCBackupMagic] boolValue] || !entries.count) {
        RYGNotifyError(RYG_NOTIF_BACKUP, RYGLocalized(@"Import failed"), RYGLocalized(@"File is not a valid RyukGram backup."));
        return;
    }

    void (^apply)(BOOL) = ^(BOOL replace) {
        NSUInteger applied = 0, skipped = 0;
        [[RYGMobileConfig shared] importEntries:entries replace:replace applied:&applied skipped:&skipped];
        if (completion) completion();
        RYGNotifySuccess(RYG_NOTIF_BACKUP, RYGLocalized(@"Import complete"),
                         [NSString stringWithFormat:RYGLocalized(@"%lu applied · %lu skipped"),
                          (unsigned long)applied, (unsigned long)skipped]);
    };

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:RYGLocalized(@"Import overrides")
                         message:[NSString stringWithFormat:RYGLocalized(@"This file holds %lu entry(s). Merge keeps what you already changed, replace clears your current overrides first."), (unsigned long)entries.count]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Merge") style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *_) { apply(NO); }]];
    [a addAction:[UIAlertAction actionWithTitle:RYGLocalized(@"Replace") style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *_) { apply(YES); }]];
    [presenter presentViewController:a animated:YES completion:nil];
}

@end
