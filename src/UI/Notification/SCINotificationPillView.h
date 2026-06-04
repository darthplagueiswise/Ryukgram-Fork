#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SCINotificationTone) {
    SCINotificationToneSuccess,
    SCINotificationToneError,
    SCINotificationToneInfo,
    SCINotificationToneWarning,
};

typedef NS_ENUM(NSUInteger, SCINotificationStyle) {
    SCINotificationStyleMinimal,
    SCINotificationStyleColorful,
    SCINotificationStyleGlow,
    SCINotificationStyleIsland,
};

typedef NS_ENUM(NSUInteger, SCINotificationPosition) {
    SCINotificationPositionTop,
    SCINotificationPositionBottom,
};

@class SCINotificationPillView;

@interface SCIPillSpinnerView : UIView
@property (nonatomic, strong, nullable) UIColor *color;
@property (nonatomic, assign, readonly) BOOL isAnimating;
- (void)startAnimating;
- (void)stopAnimating;
@end

@interface SCINotificationPillView : UIView

@property (nonatomic, assign, readonly) SCINotificationStyle style;
@property (nonatomic, assign, readonly) SCINotificationPosition position;
@property (nonatomic, assign, readonly) SCINotificationTone tone;

@property (nonatomic, copy, nullable) NSString *titleText;
@property (nonatomic, copy, nullable) NSString *subtitleText;
@property (nonatomic, copy, nullable) NSString *iconSymbolName;
@property (nonatomic, assign) BOOL showsProgress;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) BOOL indeterminate;
@property (nonatomic, assign) BOOL showsCancelButton;

@property (nonatomic, copy, nullable) void (^onTap)(SCINotificationPillView *pill);
@property (nonatomic, copy, nullable) void (^onCancel)(SCINotificationPillView *pill);
@property (nonatomic, copy, nullable) void (^onSwipeDismiss)(SCINotificationPillView *pill);

- (instancetype)initWithStyle:(SCINotificationStyle)style
                     position:(SCINotificationPosition)position;

- (void)applyTone:(SCINotificationTone)tone animated:(BOOL)animated;
- (void)setProgress:(float)progress animated:(BOOL)animated;
- (void)refreshSizeAnimated:(BOOL)animated;
- (void)pulseIcon;

@end

NS_ASSUME_NONNULL_END
