// Shared bottom-sheet color picker. Single source of truth for any feature
// that needs a live UIColorPickerViewController with optional gradient mode
// (Start/End swatches).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGColorPickerSheetMode) {
    RYGColorPickerSheetModeSolid = 0,
    RYGColorPickerSheetModeGradient,
};

// Fires on every color change. `secondary` is non-nil only in gradient mode.
typedef void (^RYGColorPickerSheetApplyHandler)(RYGColorPickerSheetMode mode,
                                                UIColor *primary,
                                                UIColor * _Nullable secondary);

@interface RYGColorPickerSheet : UIViewController

@property (nonatomic, assign, readonly) RYGColorPickerSheetMode mode;
@property (nonatomic, strong, readonly) UIColor *startColor;
@property (nonatomic, strong, readonly, nullable) UIColor *endColor;

+ (instancetype)sheetWithMode:(RYGColorPickerSheetMode)mode
                   startColor:(nullable UIColor *)start
                     endColor:(nullable UIColor *)end
                 applyHandler:(RYGColorPickerSheetApplyHandler)handler;

- (void)presentFromViewController:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
