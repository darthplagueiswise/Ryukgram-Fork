#import <Foundation/Foundation.h>
#import "RYGStoryViewerCell.h"

@class RYGStoriesArchiveStore;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RYGStatsRange) {
	RYGStatsRangeWeek = 0,
	RYGStatsRangeMonth,
	RYGStatsRangeAll,
};

// One person folded across every archived story they showed up in.
@interface RYGAudienceMember : NSObject <RYGStoryViewerDisplay>
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, copy, nullable) NSString *username;
@property (nonatomic, copy, nullable) NSString *fullName;
@property (nonatomic, copy, nullable) NSString *profilePicURL;
@property (nonatomic, assign) BOOL isVerified;
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, assign) BOOL following;
@property (nonatomic, assign) BOOL followedBy;
@property (nonatomic, copy, nullable) NSString *reactionEmoji;
@property (nonatomic, assign) NSInteger views;
@property (nonatomic, assign) NSInteger reactions;
@property (nonatomic, strong, nullable) NSDate *lastSeenAt;
// Mean place in the viewer list, 1 = always first to look. -1 when unrankable.
@property (nonatomic, assign) double earliness;
@end

@interface RYGStoryStatPoint : NSObject
@property (nonatomic, copy) NSString *pk;
@property (nonatomic, strong, nullable) NSDate *takenAt;
@property (nonatomic, assign) NSInteger views;
@property (nonatomic, assign) NSInteger reactions;
@end

@interface RYGStoryAudienceStats : NSObject

@property (nonatomic, assign, readonly) NSInteger storyCount;
@property (nonatomic, assign, readonly) NSInteger totalViews;
@property (nonatomic, assign, readonly) NSInteger totalReactions;
@property (nonatomic, assign, readonly) NSInteger uniqueViewers;
@property (nonatomic, assign, readonly) NSInteger loyalViewers;
@property (nonatomic, assign, readonly) NSInteger earlyViewers;
@property (nonatomic, assign, readonly) double avgViews;
@property (nonatomic, assign, readonly) double engagement;
// -1 when there aren't enough stories to call one.
@property (nonatomic, assign, readonly) NSInteger peakHour;
@property (nonatomic, copy, readonly) NSArray<RYGStoryStatPoint *> *points;
@property (nonatomic, copy, readonly) NSArray<RYGAudienceMember *> *members;
// The window of equal length before this one. nil for the all-time range.
@property (nonatomic, strong, readonly, nullable) RYGStoryAudienceStats *previous;

+ (void)computeForStore:(RYGStoriesArchiveStore *)store
                  range:(RYGStatsRange)range
             completion:(void (^)(RYGStoryAudienceStats *stats))completion;

@end

NSString *RYGStatShortNumber(NSInteger value);

NS_ASSUME_NONNULL_END
