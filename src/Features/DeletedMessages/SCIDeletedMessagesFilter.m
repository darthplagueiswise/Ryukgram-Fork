#import "SCIDeletedMessagesFilter.h"

@implementation SCIDeletedMessagesFilter

- (instancetype)init {
	if ((self = [super init])) {
		_kinds = [NSMutableSet set];
		_dateRange = SCIDMDateRangeAll;
		_sort = SCIDMSortRecent;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone {
	SCIDeletedMessagesFilter *c = [[SCIDeletedMessagesFilter allocWithZone:zone] init];
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
	return self.searchText.length == 0 && !self.hasKindFilter && self.dateRange == SCIDMDateRangeAll && !self.ephemeralOnly;
}

- (BOOL)matchesKind:(SCIDeletedMessageKind)kind {
	return !self.hasKindFilter || [self.kinds containsObject:@(kind)];
}

- (void)toggleKind:(SCIDeletedMessageKind)kind {
	NSNumber *k = @(kind);
	[self.kinds containsObject:k] ? [self.kinds removeObject:k] : [self.kinds addObject:k];
}

- (void)clearKinds {
	[self.kinds removeAllObjects];
}

#pragma mark - Helpers

static NSDate *sciDMDate(SCIDeletedMessage *m) {
	return m.deletedAt ?: m.capturedAt ?: m.sentAt;
}

static NSString *sciDMSearchText(NSString *s) {
	return s.length ? [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
}

static BOOL sciContains(NSString *field, NSString *q) {
	return field.length && [field rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound;
}

- (NSDate *)effectiveStart {
	if (self.dateRange == SCIDMDateRangeCustom) return self.customStart;

	NSDate *now = NSDate.date;
	NSCalendar *cal = NSCalendar.currentCalendar;

	switch (self.dateRange) {
		case SCIDMDateRangeToday:
			return [cal startOfDayForDate:now];

		case SCIDMDateRangeWeek:
			return [cal dateByAddingUnit:NSCalendarUnitDay value:-7 toDate:now options:0];

		case SCIDMDateRangeMonth:
			return [cal dateByAddingUnit:NSCalendarUnitDay value:-30 toDate:now options:0];

		default:
			return nil;
	}
}

- (NSDate *)effectiveEnd {
	return self.dateRange == SCIDMDateRangeCustom ? self.customEnd : nil;
}

- (BOOL)message:(SCIDeletedMessage *)m matchesSearch:(NSString *)q {
	if (!q.length) return YES;

	return sciContains(m.text, q)
		|| sciContains(m.previewText, q)
		|| sciContains(m.senderUsername, q)
		|| sciContains(m.senderFullName, q)
		|| sciContains(m.threadTitle, q)
		|| sciContains(m.mediaURL, q)
		|| sciContains(m.thumbnailURL, q)
		|| sciContains(m.replyToMessageId, q)
		|| sciContains(SCIDeletedMessageKindLocalizedName(m.kind), q)
		|| sciContains(SCIDeletedMessageKindToString(m.kind), q);
}

- (BOOL)message:(SCIDeletedMessage *)m matchesStart:(NSDate *)start end:(NSDate *)end {
	if (!start && !end) return YES;

	NSDate *d = sciDMDate(m);
	if (!d) return self.dateRange == SCIDMDateRangeAll;

	if (start && [d compare:start] == NSOrderedAscending) return NO;
	if (end && [d compare:end] == NSOrderedDescending) return NO;
	return YES;
}

static void sciSortMessages(NSMutableArray<SCIDeletedMessage *> *messages, SCIDMSort sort) {
	[messages sortUsingComparator:^NSComparisonResult(SCIDeletedMessage *a, SCIDeletedMessage *b) {
		NSDate *da = sciDMDate(a) ?: NSDate.distantPast;
		NSDate *db = sciDMDate(b) ?: NSDate.distantPast;
		return sort == SCIDMSortOldest ? [da compare:db] : [db compare:da];
	}];
}

static void sciSortGroups(NSMutableArray<SCIDeletedMessageGroup *> *groups, SCIDMSort sort) {
	[groups sortUsingComparator:^NSComparisonResult(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
		if (sort == SCIDMSortCountDesc && a.count != b.count) {
			return b.count > a.count ? NSOrderedDescending : NSOrderedAscending;
		}

		NSDate *da = a.lastDeletedAt ?: NSDate.distantPast;
		NSDate *db = b.lastDeletedAt ?: NSDate.distantPast;
		return sort == SCIDMSortOldest ? [da compare:db] : [db compare:da];
	}];
}

#pragma mark - Apply

- (NSArray<SCIDeletedMessage *> *)apply:(NSArray<SCIDeletedMessage *> *)messages {
	if (!messages.count) return @[];

	NSString *q = sciDMSearchText(self.searchText);
	NSDate *start = self.effectiveStart;
	NSDate *end = self.effectiveEnd;
	BOOL hasKind = self.hasKindFilter;

	NSMutableArray *out = [NSMutableArray arrayWithCapacity:messages.count];

	for (SCIDeletedMessage *m in messages) {
		if (self.ephemeralOnly && !m.isEphemeral) continue;
		if (hasKind && ![self.kinds containsObject:@(m.kind)]) continue;
		if (![self message:m matchesStart:start end:end]) continue;
		if (![self message:m matchesSearch:q]) continue;
		[out addObject:m];
	}

	sciSortMessages(out, self.sort);
	return out;
}

- (NSArray<SCIDeletedMessageGroup *> *)applyToGroups:(NSArray<SCIDeletedMessageGroup *> *)groups {
	if (!groups.count) return @[];

	NSString *q = sciDMSearchText(self.searchText);
	BOOL groupNameSearchOnly = q.length && !self.hasKindFilter && self.dateRange == SCIDMDateRangeAll;
	NSMutableArray *out = [NSMutableArray arrayWithCapacity:groups.count];

	for (SCIDeletedMessageGroup *g in groups) {
		NSArray *filtered = [self apply:g.messages];

		if (!filtered.count && groupNameSearchOnly) {
			BOOL hit = sciContains(g.senderUsername, q) || sciContains(g.senderFullName, q) || sciContains(g.threadTitle, q);
			if (hit) filtered = g.messages;
		}

		if (!filtered.count) continue;

		SCIDeletedMessageGroup *copy = [SCIDeletedMessageGroup new];
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

	sciSortGroups(out, self.sort);
	return out;
}

@end
