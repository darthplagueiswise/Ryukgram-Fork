#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Per-account snapshot archive: record toggle, capacity, compare-anchor picker,
// and multi-select delete. Pushed from the analyzer's Preferences section.
@interface SCIProfileAnalyzerSnapshotsViewController : UIViewController
- (instancetype)initWithUserPK:(NSString *)userPK;
@end

NS_ASSUME_NONNULL_END
