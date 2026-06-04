#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Shared long-press menu surfaced from the reel 3-dot button.
// Each playback module (speed picker, …) registers itself at startup.
// Coordinator installs the long-press recognizer only when at least one
// registered module's `isOn` returns YES.

typedef BOOL (^SCIReelsModuleIsOn)(void);
typedef UIView * _Nullable (^SCIReelsModuleBuildSection)(void);

@interface SCIReelsPlaybackMenu : NSObject

+ (void)registerModuleWithID:(NSString *)moduleID
                        isOn:(SCIReelsModuleIsOn)isOn
                buildSection:(SCIReelsModuleBuildSection)buildSection;

+ (BOOL)anyModuleEnabled;

@end

// Module-side helper to build a section card matching the menu's style.
// Header label + content view stacked vertically with a divider between rows.
@interface SCIReelsPlaybackSection : UIView
- (instancetype)initWithTitle:(NSString *)title content:(UIView *)content;
@end

NS_ASSUME_NONNULL_END
