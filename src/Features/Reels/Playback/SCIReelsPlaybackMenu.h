#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Long-press menu on a reel, built from modules that register at startup.
// The recognizer installs only while at least one module's `isOn` returns YES.

typedef BOOL (^SCIReelsModuleIsOn)(void);
typedef UIView * _Nullable (^SCIReelsModuleBuildSection)(void);

@interface SCIReelsPlaybackMenu : NSObject

+ (void)registerModuleWithID:(NSString *)moduleID
                        isOn:(SCIReelsModuleIsOn)isOn
                buildSection:(SCIReelsModuleBuildSection)buildSection;

+ (BOOL)anyModuleEnabled;

// Reel cell captured at long-press so seek targets the right reel.
+ (void)captureReelContextFromAnchor:(UIView *)anchor;
+ (nullable UIView *)capturedReelCell;

@end

// Section card: header label above a content view.
@interface SCIReelsPlaybackSection : UIView
- (instancetype)initWithTitle:(NSString *)title content:(UIView *)content;
@end

NS_ASSUME_NONNULL_END
