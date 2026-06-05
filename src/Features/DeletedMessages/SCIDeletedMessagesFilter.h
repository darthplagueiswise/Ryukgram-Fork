#import <Foundation/Foundation.h>
#import "SCIDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDMDateRange) {
    SCIDMDateRangeAll = 0,
    SCIDMDateRangeToday,
    SCIDMDateRangeWeek,
    SCIDMDateRangeMonth,
    SCIDMDateRangeCustom,
};

typedef NS_ENUM(NSInteger, SCIDMSort) {
    SCIDMSortRecent = 0,        // newest deleted first
    SCIDMSortOldest,
    SCIDMSortCountDesc,         // groups only
};

// Filter spec shared between the top VC and the per-user detail VC.
@interface SCIDeletedMessagesFilter : NSObject <NSCopying>

@property (nonatomic, copy, nullable)   NSString *searchText;
// Set of NSNumber-wrapped SCIDeletedMessageKind. Empty = match all kinds.
@property (nonatomic, strong)           NSMutableSet<NSNumber *> *kinds;
@property (nonatomic, assign)           SCIDMDateRange dateRange;
@property (nonatomic, strong, nullable) NSDate *customStart;
@property (nonatomic, strong, nullable) NSDate *customEnd;
@property (nonatomic, assign)           SCIDMSort sort;

- (BOOL)isEmpty;
- (BOOL)hasKindFilter;     // YES when at least one kind is selected
- (BOOL)matchesKind:(SCIDeletedMessageKind)kind;
- (void)toggleKind:(SCIDeletedMessageKind)kind;
- (void)clearKinds;

- (NSArray<SCIDeletedMessage *> *)apply:(NSArray<SCIDeletedMessage *> *)messages;
- (NSArray<SCIDeletedMessageGroup *> *)applyToGroups:(NSArray<SCIDeletedMessageGroup *> *)groups;

@end

NS_ASSUME_NONNULL_END
