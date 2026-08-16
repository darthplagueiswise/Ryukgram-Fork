#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, RYGNotificationTone) {
    RYGNotificationToneSuccess,
    RYGNotificationToneError,
    RYGNotificationToneInfo,
    RYGNotificationToneWarning,
};

typedef NS_ENUM(NSUInteger, RYGNotificationStyle) {
    RYGNotificationStyleMinimal,
    RYGNotificationStyleColorful,
    RYGNotificationStyleGlow,
    RYGNotificationStyleIsland,
};

typedef NS_ENUM(NSUInteger, RYGNotificationPosition) {
    RYGNotificationPositionTop,
    RYGNotificationPositionBottom,
};

@class RYGNotificationPillView;

@interface RYGPillSpinnerView : UIView
@property (nonatomic, strong, nullable) UIColor *color;
@property (nonatomic, assign, readonly) BOOL isAnimating;
- (void)startAnimating;
- (void)stopAnimating;
@end

@interface RYGNotificationPillView : UIView

@property (nonatomic, assign, readonly) RYGNotificationStyle style;
@property (nonatomic, assign, readonly) RYGNotificationPosition position;
@property (nonatomic, assign, readonly) RYGNotificationTone tone;

@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *subtitleText;
@property (nonatomic, copy, nullable) NSString *iconSymbolName;
@property (nonatomic, assign) BOOL showsProgress;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) BOOL indeterminate;
@property (nonatomic, assign) BOOL showsCancelButton;

@property (nonatomic, copy, nullable) void (^onTap)(RYGNotificationPillView *pill);
@property (nonatomic, copy, nullable) void (^onCancel)(RYGNotificationPillView *pill);
@property (nonatomic, copy, nullable) void (^onSwipeDismiss)(RYGNotificationPillView *pill);

- (instancetype)initWithStyle:(RYGNotificationStyle)style
                     position:(RYGNotificationPosition)position;

- (void)applyTone:(RYGNotificationTone)tone animated:(BOOL)animated;
- (void)setProgress:(float)progress animated:(BOOL)animated;
- (void)refreshSizeAnimated:(BOOL)animated;
- (void)pulseIcon;
// Target height from the height constraint — valid right after refreshSize, before
// bounds resolve (bounds read 0 until layout, which breaks stack spacing math).
- (CGFloat)pillTargetHeight;

@end

NS_ASSUME_NONNULL_END
