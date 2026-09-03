#import "RYGStoryAudienceStats.h"
#import "RYGStoriesArchiveStore.h"
#import "RYGArchivedStory.h"
#import "RYGArchivedStoryViewer.h"

// Shorter viewer lists say nothing about how early someone looked.
static NSInteger const kRankableListSize = 5;

@implementation RYGStoryStatPoint @end

@implementation RYGAudienceMember
- (instancetype)init {
	if (self = [super init]) _earliness = -1;
	return self;
}
@end

@interface RYGStoryAudienceStats ()
@property (nonatomic, assign) NSInteger storyCount, totalViews, totalReactions, uniqueViewers, loyalViewers, earlyViewers, peakHour;
@property (nonatomic, assign) double avgViews, engagement;
@property (nonatomic, copy) NSArray<RYGStoryStatPoint *> *points;
@property (nonatomic, copy) NSArray<RYGAudienceMember *> *members;
@property (nonatomic, strong) RYGStoryAudienceStats *previous;
@end

@implementation RYGStoryAudienceStats

+ (NSTimeInterval)lengthForRange:(RYGStatsRange)range {
	if (range == RYGStatsRangeWeek) return 7 * 86400;
	if (range == RYGStatsRangeMonth) return 30 * 86400;
	return 0;
}

+ (void)computeForStore:(RYGStoriesArchiveStore *)store
                  range:(RYGStatsRange)range
             completion:(void (^)(RYGStoryAudienceStats *))completion {
	if (!store) { if (completion) completion([RYGStoryAudienceStats new]); return; }
	NSTimeInterval length = [self lengthForRange:range];
	NSDate *from = length ? [NSDate dateWithTimeIntervalSinceNow:-length] : nil;

	[store performBackground:^(NSManagedObjectContext *ctx) {
		NSArray<RYGArchivedStory *> *stories = [store storiesSortedByDateDescendingInContext:ctx];
		NSArray<RYGArchivedStoryViewer *> *viewers = [store allViewersInContext:ctx];

		RYGStoryAudienceStats *out = [self statsFromStories:stories viewers:viewers from:from to:nil withPoints:YES];
		if (from)
			out.previous = [self statsFromStories:stories
			                              viewers:viewers
			                                 from:[from dateByAddingTimeInterval:-length]
			                                   to:from
			                             withPoints:NO];

		dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(out); });
	}];
}

+ (RYGStoryAudienceStats *)statsFromStories:(NSArray<RYGArchivedStory *> *)stories
                                    viewers:(NSArray<RYGArchivedStoryViewer *> *)viewers
                                       from:(NSDate *)from
                                         to:(NSDate *)to
                                 withPoints:(BOOL)withPoints {
	RYGStoryAudienceStats *out = [RYGStoryAudienceStats new];
	out.peakHour = -1;

	NSMutableDictionary<NSString *, NSNumber *> *listSizes = [NSMutableDictionary dictionary];
	NSMutableArray<RYGStoryStatPoint *> *points = withPoints ? [NSMutableArray array] : nil;
	NSInteger hourViews[24] = {0}, hourStories[24] = {0};
	NSCalendar *cal = NSCalendar.currentCalendar;

	for (RYGArchivedStory *s in stories) {
		if (!s.pk.length) continue;
		if (from && (!s.takenAt || [s.takenAt compare:from] == NSOrderedAscending)) continue;
		if (to && (!s.takenAt || [s.takenAt compare:to] != NSOrderedAscending)) continue;
		listSizes[s.pk] = @(s.viewersCount);

		NSInteger reactions = (NSInteger)(s.likesCount + s.reactionsCount);
		out.storyCount++;
		out.totalViews += (NSInteger)s.viewersCount;
		out.totalReactions += reactions;

		if (withPoints) {
			RYGStoryStatPoint *p = [RYGStoryStatPoint new];
			p.pk = s.pk;
			p.takenAt = s.takenAt;
			p.views = (NSInteger)s.viewersCount;
			p.reactions = reactions;
			[points insertObject:p atIndex:0];
		}

		if (s.takenAt) {
			NSInteger h = [cal component:NSCalendarUnitHour fromDate:s.takenAt];
			if (h >= 0 && h < 24) { hourViews[h] += (NSInteger)s.viewersCount; hourStories[h]++; }
		}
	}
	out.points = points ?: @[];

	NSMutableDictionary<NSString *, RYGAudienceMember *> *byPK = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *placesByPK = [NSMutableDictionary dictionary];

	for (RYGArchivedStoryViewer *v in viewers) {
		RYGArchivedStory *story = v.story;
		NSNumber *listSize = story.pk.length ? listSizes[story.pk] : nil;
		if (!v.pk.length || !listSize) continue;

		RYGAudienceMember *m = byPK[v.pk];
		if (!m) {
			m = [RYGAudienceMember new];
			m.pk = v.pk;
			byPK[v.pk] = m;
		}
		m.views++;
		if (v.liked || v.reactionEmoji.length) m.reactions++;

		// IG returns viewers newest-first, so a high index means they looked early.
		NSInteger size = listSize.integerValue;
		if (size >= kRankableListSize) {
			NSMutableArray *places = placesByPK[v.pk];
			if (!places) { places = [NSMutableArray array]; placesByPK[v.pk] = places; }
			[places addObject:@((double)v.sortIndex / (size - 1))];
		}

		// Identity and relationship come from the most recent story they viewed.
		NSDate *seen = story.takenAt ?: v.addedAt;
		if (seen && (!m.lastSeenAt || [seen compare:m.lastSeenAt] == NSOrderedDescending)) {
			m.lastSeenAt = seen;
			m.username = v.username;
			m.fullName = v.fullName;
			m.profilePicURL = v.profilePicURL;
			m.isVerified = v.isVerified;
			m.following = v.following;
			m.followedBy = v.followedBy;
		}
		if (v.reactionEmoji.length && !m.reactionEmoji.length) m.reactionEmoji = v.reactionEmoji;
		if (v.liked) m.liked = YES;

	}

	NSArray<RYGAudienceMember *> *members = [byPK.allValues sortedArrayUsingComparator:^NSComparisonResult(RYGAudienceMember *a, RYGAudienceMember *b) {
		if (a.views != b.views) return a.views > b.views ? NSOrderedAscending : NSOrderedDescending;
		return [(a.username ?: @"") caseInsensitiveCompare:(b.username ?: @"")];
	}];
	out.members = members;
	out.uniqueViewers = members.count;
	out.avgViews = out.storyCount ? (double)out.totalViews / out.storyCount : 0;
	out.engagement = out.totalViews ? (double)out.totalReactions / out.totalViews * 100.0 : 0;

	for (RYGAudienceMember *m in members) {
		NSArray<NSNumber *> *places = placesByPK[m.pk];
		if (!places.count) continue;
		double sum = 0;
		for (NSNumber *n in places) sum += n.doubleValue;
		m.earliness = sum / places.count;
		if (m.earliness >= 0.8) out.earlyViewers++;
	}

	if (out.storyCount >= 3) {
		NSInteger threshold = (NSInteger)ceil(out.storyCount * 0.8);
		for (RYGAudienceMember *m in members) if (m.views >= threshold) out.loyalViewers++;

		double best = 0;
		for (NSInteger h = 0; h < 24; h++) {
			if (!hourStories[h]) continue;
			double avg = (double)hourViews[h] / hourStories[h];
			if (avg > best) { best = avg; out.peakHour = h; }
		}
	}
	return out;
}

@end

NSString *RYGStatShortNumber(NSInteger value) {
	if (value < 1000) return [NSString stringWithFormat:@"%ld", (long)value];
	if (value < 1000000) {
		double k = value / 1000.0;
		return [NSString stringWithFormat:k < 10 ? @"%.1fK" : @"%.0fK", k];
	}
	double m = value / 1000000.0;
	return [NSString stringWithFormat:m < 10 ? @"%.1fM" : @"%.0fM", m];
}
