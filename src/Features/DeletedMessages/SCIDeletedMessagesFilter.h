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

@interface SCIDeletedMessagesFilter : NSObject <NSCopying>

@property (nonatomic, copy, nullable)   NSString *searchText;
// Set of NSNumber-wrapped SCIDeletedMessageKind. Empty = match all kinds.
@property (nonatomic, strong)           NSMutableSet<NSNumber *> *kinds;
@property (nonatomic, assign)           SCIDMDateRange dateRange;
@property (nonatomic, strong, nullable) NSDate *customStart;
@property (nonatomic, strong, nullable) NSDate *customEnd;
@property (nonatomic, assign)           SCIDMSort sort;
@property (nonatomic, assign)           BOOL ephemeralOnly;   // only disappearing / view-once media

- (BOOL)isEmpty;
- (BOOL)hasKindFilter;
- (BOOL)matchesKind:(SCIDeletedMessageKind)kind;
- (void)toggleKind:(SCIDeletedMessageKind)kind;
- (void)clearKinds;

- (NSArray<SCIDeletedMessage *> *)apply:(NSArray<SCIDeletedMessage *> *)messages;
- (NSArray<SCIDeletedMessageGroup *> *)applyToGroups:(NSArray<SCIDeletedMessageGroup *> *)groups;

@end

NS_ASSUME_NONNULL_END
