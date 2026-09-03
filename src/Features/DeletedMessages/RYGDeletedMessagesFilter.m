#import "RYGDeletedMessagesFilter.h"

@implementation RYGDeletedMessagesFilter

- (instancetype)init {
	if ((self = [super init])) {
		_kinds = [NSMutableSet set];
		_dateRange = RYGDMDateRangeAll;
		_sort = RYGDMSortRecent;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	RYGDeletedMessagesFilter *c = [[RYGDeletedMessagesFilter allocWithZone:zone] init];
	c.searchText = self.searchText;
	c.kinds = self.kinds.mutableCopy;
	c.dateRange = self.dateRange;
	c.customStart = self.customStart;
	c.customEnd = self.customEnd;
	c.sort = self.sort;
	c.ephemeralOnly = self.ephemeralOnly;
	return c;
}

- (BOOL)hasKindFilter { return self.kinds.count > 0; }

- (BOOL)isEmpty {
	return self.searchText.length == 0 && !self.hasKindFilter && self.dateRange == RYGDMDateRangeAll && !self.ephemeralOnly;
}

- (BOOL)matchesKind:(RYGDeletedMessageKind)kind {
	return !self.hasKindFilter || [self.kinds containsObject:@(kind)];
}

- (void)toggleKind:(RYGDeletedMessageKind)kind {
	NSNumber *k = @(kind);
	[self.kinds containsObject:k] ? [self.kinds removeObject:k] : [self.kinds addObject:k];
}

- (void)clearKinds {
	[self.kinds removeAllObjects];
}

#pragma mark - Helpers

static NSDate *rygDMDate(RYGDeletedMessage *m) {
	return m.deletedAt ?: m.capturedAt ?: m.sentAt;
}

static NSString *rygDMSearchText(NSString *s) {
	return s.length ? [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}

static BOOL rygContains(NSString *field, NSString *q) {
	return field.length && [field rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

- (NSDate *)effectiveStart {
	if (self.dateRange == RYGDMDateRangeCustom) return self.customStart;

	NSDate *now = NSDate.date;
	NSCalendar *cal = NSCalendar.currentCalendar;

	switch (self.dateRange) {
		case RYGDMDateRangeToday:
			return [cal startOfDayForDate:now];

		case RYGDMDateRangeWeek:
			return [cal dateByAddingUnit:NSCalendarUnitDay value:-7 toDate:now options:0];

		case RYGDMDateRangeMonth:
			return [cal dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:now options:0];

		default:
			return nil;
	}
}

- (NSDate *)effectiveEnd {
	return self.dateRange == RYGDMDateRangeCustom ? self.customEnd : nil;
}

- (BOOL)message:(RYGDeletedMessage *)m matchesSearch:(NSString *)q {
	if (!q.length) return YES;

	return rygContains(m.text, q)
		|| rygContains(m.previewText, q)
		|| rygContains(m.senderUsername, q)
		|| rygContains(m.senderFullName, q)
		|| rygContains(m.threadTitle, q)
		|| rygContains(m.mediaURL, q)
		|| rygContains(m.thumbnailURL, q)
		|| rygContains(m.replyToMessageId, q)
		|| rygContains(RYGDeletedMessageKindLocalizedName(m.kind), q)
		|| rygContains(RYGDeletedMessageKindToString(m.kind), q);
}

- (BOOL)message:(RYGDeletedMessage *)m matchesStart:(NSDate *)start end:(NSDate *)end {
	if (!start && !end) return YES;

	NSDate *d = rygDMDate(m);
	if (!d) return self.dateRange == RYGDMDateRangeAll;

	if (start && [d compare:start] == NSOrderedAscending) return NO;
	if (end && [d compare:end] == NSOrderedDescending) return NO;
	return YES;
}

static void rygSortMessages(NSMutableArray<RYGDeletedMessage *> *messages, RYGDMSort sort) {
	[messages sortUsingComparator:^NSComparisonResult(RYGDeletedMessage *a, RYGDeletedMessage *b) {
		NSDate *da = rygDMDate(a) ?: NSDate.distantPast;
		NSDate *db = rygDMDate(b) ?: NSDate.distantPast;
		return sort == RYGDMSortOldest ? [da compare:db] : [db compare:da];
	}];
}

static void rygSortGroups(NSMutableArray<RYGDeletedMessageGroup *> *groups, RYGDMSort sort) {
	[groups sortUsingComparator:^NSComparisonResult(RYGDeletedMessageGroup *a, RYGDeletedMessageGroup *b) {
		if (sort == RYGDMSortCountDesc && a.count != b.count) {
			return b.count > a.count ? NSOrderedDescending : NSOrderedAscending;
		}

		NSDate *da = a.lastDeletedAt ?: NSDate.distantPast;
		NSDate *db = b.lastDeletedAt ?: NSDate.distantPast;
		return sort == RYGDMSortOldest ? [da compare:db] : [db compare:da];
	}];
}

#pragma mark - Apply

- (NSArray<RYGDeletedMessage *> *)apply:(NSArray<RYGDeletedMessage *> *)messages {
	if (!messages.count) return @[];

	NSString *q = rygDMSearchText(self.searchText);
	NSDate *start = self.effectiveStart;
	NSDate *end = self.effectiveEnd;
	BOOL hasKind = self.hasKindFilter;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:messages.count];

	for (RYGDeletedMessage *m in messages) {
		if (self.ephemeralOnly && !m.isEphemeral) continue;
		if (hasKind && ![self.kinds containsObject:@(m.kind)]) continue;
		if (![self message:m matchesStart:start end:end]) continue;
		if (![self message:m matchesSearch:q]) continue;
		[out addObject:m];
	}

	rygSortMessages(out, self.sort);
	return out;
}

- (NSArray<RYGDeletedMessageGroup *> *)applyToGroups:(NSArray<RYGDeletedMessageGroup *> *)groups {
	if (!groups.count) return @[];

	NSString *q = rygDMSearchText(self.searchText);
	BOOL groupNameSearchOnly = q.length && !self.hasKindFilter && self.dateRange == RYGDMDateRangeAll;
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:groups.count];

	for (RYGDeletedMessageGroup *g in groups) {
		NSArray *filtered = [self apply:g.messages];

		if (!filtered.count && groupNameSearchOnly) {
			BOOL hit = rygContains(g.senderUsername, q) || rygContains(g.senderFullName, q) || rygContains(g.threadTitle, q);
			if (hit) filtered = g.messages;
		}

		if (!filtered.count) continue;

		RYGDeletedMessageGroup *copy = [RYGDeletedMessageGroup new];
		copy.threadId = g.threadId;
		copy.isGroup = g.isGroup;
		copy.threadTitle = g.threadTitle;
		copy.threadAvatarURL = g.threadAvatarURL;
		copy.senderPk = g.senderPk;
		copy.senderUsername = g.senderUsername;
		copy.senderFullName = g.senderFullName;
		copy.senderProfilePicURL = g.senderProfilePicURL;
		copy.messages = filtered;
		[out addObject:copy];
	}

	rygSortGroups(out, self.sort);
	return out;
}

@end