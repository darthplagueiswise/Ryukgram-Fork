#import <UIKit/UIKit.h>
#import "RYGProfileAnalyzerModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGPAListKind) {
    RYGPAListKindPlain,           // no action button
    RYGPAListKindUnfollow,        // show "Unfollow" button (you follow them)
    RYGPAListKindFollow,          // they follow you, you don't — follow-back/remove menu
    RYGPAListKindRefollow,        // people you unfollowed — plain re-follow button
    RYGPAListKindProfileUpdate,   // displays previous → current change rows
    RYGPAListKindMutual,          // mutuals — Unfollow inline + visit-style subtitle
    RYGPAListKindVisited,         // visited profiles tracker — last-seen subtitle, date filter
};

@interface RYGProfileAnalyzerListViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title
                        users:(NSArray<RYGProfileAnalyzerUser *> *)users
                         kind:(RYGPAListKind)kind;
- (instancetype)initWithTitle:(NSString *)title
              profileUpdates:(NSArray<RYGProfileAnalyzerProfileChange *> *)updates;
- (instancetype)initVisitedListWithTitle:(NSString *)title
                                   visits:(NSArray<RYGProfileAnalyzerVisit *> *)visits;

// Identity IDs new since the list was last opened; surfaces a NEW pill + New-first sort.
@property (nonatomic, copy, nullable) NSSet<NSString *> *unseenEntryIDs;
@end

NS_ASSUME_NONNULL_END
