// Shared bottom-sheet color picker. Single source of truth for any feature
// that needs a live UIColorPickerViewController with optional gradient mode
// (Start/End swatches).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIColorPickerSheetMode) {
    SCIColorPickerSheetModeSolid = 0,
    SCIColorPickerSheetModeGradient,
};

// Fires on every color change. `secondary` is non-nil only in gradient mode.
typedef void (^SCIColorPickerSheetApplyHandler)(SCIColorPickerSheetMode mode,
                                                UIColor *primary,
                                                UIColor * _Nullable secondary);

@interface SCIColorPickerSheet : UIViewController

@property (nonatomic, assign, readonly) SCIColorPickerSheetMode mode;
@property (nonatomic, strong, readonly) UIColor *startColor;
@property (nonatomic, strong, readonly, nullable) UIColor *endColor;

+ (instancetype)sheetWithMode:(SCIColorPickerSheetMode)mode
                   startColor:(nullable UIColor *)start
                     endColor:(nullable UIColor *)end
                 applyHandler:(SCIColorPickerSheetApplyHandler)handler;

- (void)presentFromViewController:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
