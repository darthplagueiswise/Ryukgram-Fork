#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Copies the bundled, validated mapping to the disk locations consumed by the
// native MobileConfig factory. Existing valid mappings are preserved unless
// overwrite is YES. The native loader observes the file on next construction,
// so callers should restart Instagram after a manual refresh.
NSString *SCIInstallBundledIDNameMapping(BOOL overwrite);
NSString *SCIIdNameMappingStatus(void);

NS_ASSUME_NONNULL_END
