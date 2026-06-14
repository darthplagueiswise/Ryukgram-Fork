#import <UIKit/UIKit.h>
#import "SCIProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIPAListKind) {
    SCIPAListKindPlain,           // no action button
    SCIPAListKindUnfollow,        // show "Unfollow" button (you follow them)
    SCIPAListKindFollow,          // they follow you, you don't — follow-back/remove menu
    SCIPAListKindRefollow,        // people you unfollowed — plain re-follow button
    SCIPAListKindProfileUpdate,   // displays previous → current change rows
    SCIPAListKindMutual,          // mutuals — Unfollow inline + visit-style subtitle
    SCIPAListKindVisited,         // visited profiles tracker — last-seen subtitle, date filter
};

@interface SCIProfileAnalyzerListViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<SCIProfileAnalyzerUser *> *)users
                         kind:(SCIPAListKind)kind;
- (instancetype)initWithTitle:(NSString *)title
              profileUpdates:(NSArray<SCIProfileAnalyzerProfileChange *> *)updates;
- (instancetype)initVisitedListWithTitle:(NSString *)title
                                   visits:(NSArray<SCIProfileAnalyzerVisit *> *)visits;
@end

NS_ASSUME_NONNULL_END
