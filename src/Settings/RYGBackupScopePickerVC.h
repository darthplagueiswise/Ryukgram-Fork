#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Scope picker for backup export/import/reset. Renders a checklist from opaque
// row descriptors (model-side bitmask) and returns the chosen bits. Descriptor
// keys: bit, title, subtitle, symbol, color, detailSections, shared, or
// isGroup + groupMask + submodules.
@interface RYGBackupScopePickerVC : UIViewController

@property (nonatomic, copy) NSString *continueTitle;
@property (nonatomic, copy, nullable) NSString *headerMessage;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, assign) NSInteger initialSelection;
@property (nonatomic, assign) BOOL showsImportMode;
@property (nonatomic, assign) BOOL showsEncryptOption;
@property (nonatomic, copy, nullable) NSString *rawJSON;

// Account filter, its own mask space (bit i = accountRows[i]). Empty rows hide
// the section; `accounts` then comes back as 0, meaning "everything".
@property (nonatomic, copy) NSArray<NSDictionary *> *accountRows;
@property (nonatomic, assign) NSInteger initialAccountSelection;

@property (nonatomic, copy) void (^onContinue)(NSInteger chosen, NSInteger accounts, BOOL merge, NSString *_Nullable password);

// Scanning the stores would stall the tap, so the picker presents empty and
// spinning, then gets filled. Set before presenting.
@property (nonatomic, assign) BOOL loadingContent;
- (void)applyContent:(NSDictionary *)payload;

// Pushed sub-selection (feature-data modules): edits live, no commit bar; each
// toggle reports the running bitmask through onSelectionChanged.
@property (nonatomic, assign) BOOL subPicker;
@property (nonatomic, assign) BOOL showsSharedTags;
@property (nonatomic, copy, nullable) void (^onSelectionChanged)(NSInteger selection);

@end

NS_ASSUME_NONNULL_END
