#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGPlaybackPills : NSObject
+ (UIButton *)pillWithTitle:(NSString *)title target:(id)target action:(SEL)action;
+ (UIButton *)actionPillWithSymbol:(NSString *)symbol target:(id)target action:(SEL)action;
+ (void)stylePill:(UIButton *)pill selected:(BOOL)selected;
+ (void)promptNumberWithTitle:(NSString *)title
                      message:(NSString *)message
                        value:(double)value
                          min:(double)min
                          max:(double)max
                        apply:(void (^)(double value))apply;
@end

@interface RYGPlaybackSpeedView : UIView
- (instancetype)initWithRate:(float)rate onChange:(void (^)(float rate))onChange;
@end

// Seek pills plus a transport row. A nil block drops its own controls.
@interface RYGPlaybackSeekView : UIView
- (instancetype)initWithStep:(double)step
               stepDidChange:(nullable void (^)(double step))stepDidChange
                      onSeek:(nullable void (^)(double delta))onSeek
                 pauseToggle:(nullable void (^)(void))pauseToggle
                   isPlaying:(nullable BOOL (^)(void))isPlaying;
@end

NS_ASSUME_NONNULL_END
