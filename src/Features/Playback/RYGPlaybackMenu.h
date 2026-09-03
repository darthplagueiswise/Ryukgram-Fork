#import <UIKit/UIKit.h>
#import "RYGPlaybackControls.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSString *RYGPlaybackSurface NS_TYPED_ENUM;
extern RYGPlaybackSurface const RYGPlaybackSurfaceReels;
extern RYGPlaybackSurface const RYGPlaybackSurfaceStories;

typedef BOOL (^RYGPlaybackModuleIsOn)(void);
typedef UIView *_Nullable (^RYGPlaybackModuleBuildSection)(void);

@interface RYGPlaybackMenu : NSObject

+ (void)registerModuleWithID:(NSString *)moduleID
                     surface:(RYGPlaybackSurface)surface
                        isOn:(RYGPlaybackModuleIsOn)isOn
                buildSection:(RYGPlaybackModuleBuildSection)buildSection;

+ (BOOL)anyModuleEnabledForSurface:(RYGPlaybackSurface)surface;

// Runs when a long-press opens the panel, so a surface can capture its player context.
+ (void)setAnchorHandler:(void (^_Nullable)(UIView *anchor))handler forSurface:(RYGPlaybackSurface)surface;

+ (void)installLongPressOnView:(UIView *)view surface:(RYGPlaybackSurface)surface;
+ (void)presentForSurface:(RYGPlaybackSurface)surface anchor:(nullable UIView *)anchor;

+ (float)speedRateForKey:(NSString *)key;
+ (double)seekStepForKey:(NSString *)key;

+ (void)registerSpeedModuleForSurface:(RYGPlaybackSurface)surface
                           enabledKey:(NSString *)enabledKey
                              rateKey:(NSString *)rateKey
                                apply:(void (^)(float rate))apply;

// A nil key drops its control.
+ (void)registerTransportModuleForSurface:(RYGPlaybackSurface)surface
                                  seekKey:(nullable NSString *)seekKey
                                  stepKey:(nullable NSString *)stepKey
                                   onSeek:(nullable void (^)(double delta))onSeek
                                 pauseKey:(nullable NSString *)pauseKey
                              pauseToggle:(nullable void (^)(void))pauseToggle
                                isPlaying:(nullable BOOL (^)(void))isPlaying;

@end

@interface RYGPlaybackSection : UIView
- (instancetype)initWithTitle:(NSString *)title content:(UIView *)content;
@end

NS_ASSUME_NONNULL_END
