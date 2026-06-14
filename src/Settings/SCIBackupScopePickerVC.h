#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Category picker. The model hands a flat list of row descriptors + a raw-JSON
// string; this VC renders checkboxes, drills into rows with detailSections, and
// commits the chosen bitmask (bits are opaque NSInteger, defined model-side).
// Descriptor keys: bit, title, subtitle, symbol, color, detailSections (optional).
// With showsImportMode a Replace/Merge selector is shown; the chosen mode comes
// back through onContinue's `merge`.
@interface SCIBackupScopePickerVC : UIViewController

@property (nonatomic, copy) NSString *continueTitle;
@property (nonatomic, copy, nullable) NSString *headerMessage;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, assign) NSInteger initialSelection;
@property (nonatomic, assign) BOOL showsImportMode;
@property (nonatomic, copy, nullable) NSString *rawJSON;
@property (nonatomic, copy) void (^onContinue)(NSInteger chosen, BOOL merge);

@end

NS_ASSUME_NONNULL_END
