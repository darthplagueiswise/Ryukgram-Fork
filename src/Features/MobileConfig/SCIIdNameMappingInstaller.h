#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Copies the bundled, validated mapping to the disk locations consumed by the
// native MobileConfig factory. Existing valid mappings are preserved unless
// overwrite is YES. The native loader observes the file on next construction,
// so callers should restart Instagram after a manual refresh.
NSString *SCIInstallBundledIDNameMapping(BOOL overwrite);

// Downloads the version-pinned mapping maintained in this repository, validates
// the same JSONArray/colon-delimited contract, writes it atomically, then calls
// completion on the main queue. The native MobileConfig implementation remains
// the reader; this function only refreshes the file on disk.
void SCIForceDownloadIDNameMapping(void (^completion)(NSString *result));

NSString *SCIIdNameMappingStatus(void);

NS_ASSUME_NONNULL_END
