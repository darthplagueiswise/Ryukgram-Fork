// Capture-aware chrome primitives. RYGChromeCanvas handles redaction via
// the UITextField secure-canvas technique; RYGChromeButton / RYGChromeLabel
// own the full visible hierarchy so IG's liquid glass can't wrap them.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - RYGChromeCanvas

@interface RYGChromeCanvas : UIView
@property (nonatomic, readonly) UIView *contentContainer;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// YES if `field` is the secure-canvas helper owned by RYGChromeCanvas.
/// Used by the Instants screenshot bypass to skip our own redaction fields.
BOOL RYGChromeCanvasOwnsSecureField(UITextField *field);

#ifdef __cplusplus
}
#endif

// MARK: - RYGChromeButton

@interface RYGChromeButton : UIButton
- (instancetype)initWithSymbol:(NSString *)symbol
                     pointSize:(CGFloat)pointSize
                      diameter:(CGFloat)diameter NS_DESIGNATED_INITIALIZER;

@property (nonatomic, assign, readonly) CGFloat diameter;
@property (nonatomic, copy) NSString *symbolName;
@property (nonatomic, assign) CGFloat symbolPointSize;
@property (nonatomic, copy) UIColor *iconTint;
@property (nonatomic, copy) UIColor *bubbleColor;
/// `symbolName` is SF-only. For IG-styled glyphs use `setIconResource:` or
/// assign `iconView.image` directly with a baked image.
@property (nonatomic, strong, readonly) UIImageView *iconView;

/// IG-styled glyph via `+[RYGIcon imageNamed:]`. Clears `symbolName`.
- (void)setIconResource:(NSString *)resourceName pointSize:(CGFloat)pointSize;

/// Capture-redacted host. Add overlay subviews (badges, counters) here instead
/// of as direct button subviews so Hide UI on Capture redacts them too.
@property (nonatomic, strong, readonly) UIView *captureContentView;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

// MARK: - RYGChromeLabel

@interface RYGChromeLabel : UIView
- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, assign) NSTextAlignment textAlignment;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
@end

#ifdef __cplusplus
extern "C" {
#endif

// Bar button item whose customView is an RYGChromeButton. `outButton` yields
// the inner button for menu/tint/etc.
UIBarButtonItem *RYGChromeBarButtonItem(NSString *symbol,
                                         CGFloat pointSize,
                                         id _Nullable target,
                                         SEL _Nullable action,
                                         RYGChromeButton * _Nullable * _Nullable outButton);

RYGChromeButton * _Nullable RYGChromeButtonForBarItem(UIBarButtonItem *item);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
