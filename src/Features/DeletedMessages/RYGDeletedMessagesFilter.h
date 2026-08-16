#import <Foundation/Foundation.h>
#import "RYGDeletedMessagesModels.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGDMDateRange) {
    RYGDMDateRangeAll = 0,
    RYGDMDateRangeToday,
    RYGDMDateRangeWeek,
    RYGDMDateRangeMonth,
    RYGDMDateRangeCustom,
};

typedef NS_ENUM(NSInteger, RYGDMSort) {
    RYGDMSortRecent = 0,        // newest deleted first
    RYGDMSortOldest,
    RYGDMSortCountDesc,         // groups only
};

@interface RYGDeletedMessagesFilter : NSObject <NSCopying>

@property (nonatomic, copy, nullable)   NSString *searchText;
// Set of NSNumber-wrapped RYGDeletedMessageKind. Empty = match all kinds.
@property (nonatomic, strong)           NSMutableSet<NSNumber *> *kinds;
@property (nonatomic, assign)           RYGDMDateRange dateRange;
@property (nonatomic, strong, nullable) NSDate *customStart;
@property (nonatomic, strong, nullable) NSDate *customEnd;
@property (nonatomic, assign)           RYGDMSort sort;
@property (nonatomic, assign)           BOOL ephemeralOnly;   // only disappearing / view-once media

- (BOOL)isEmpty;
- (BOOL)hasKindFilter;
- (BOOL)matchesKind:(RYGDeletedMessageKind)kind;
- (void)toggleKind:(RYGDeletedMessageKind)kind;
- (void)clearKinds;

- (NSArray<RYGDeletedMessage *> *)apply:(NSArray<RYGDeletedMessage *> *)messages;
- (NSArray<RYGDeletedMessageGroup *> *)applyToGroups:(NSArray<RYGDeletedMessageGroup *> *)groups;

@end

NS_ASSUME_NONNULL_END
