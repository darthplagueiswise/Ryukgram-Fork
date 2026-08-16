#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGSettingsBackup : NSObject

+ (void)presentExport;
+ (void)presentImport;
+ (void)presentReset;

// Clearing from the Storage screen runs the very same reset engine, scoped to
// one store (`storageID` matches RYGStorageEntry.identifier) and optionally one
// account. `done` reports whether anything was cleared.
+ (void)presentClearConfirmationForStorageID:(NSString *)storageID
								   accountPK:(nullable NSString *)accountPK
									   label:(NSString *)label
										done:(nullable void (^)(BOOL cleared))done;

+ (void)presentClearAllStorageConfirmationDone:(nullable void (^)(BOOL cleared))done;

@end

NS_ASSUME_NONNULL_END
