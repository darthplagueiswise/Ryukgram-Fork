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
    c.searchText   = self.searchText;
    c.kinds        = [self.kinds mutableCopy];
    c.dateRange    = self.dateRange;
    c.customStart  = self.customStart;
    c.customEnd    = self.customEnd;
    c.sort         = self.sort;
    return c;
}

- (BOOL)isEmpty {
    return self.searchText.length == 0
        && !self.hasKindFilter
        && self.dateRange == SCIDMDateRangeAll;
}

- (BOOL)hasKindFilter { return self.kinds.count > 0; }

- (BOOL)matchesKind:(SCIDeletedMessageKind)kind {
    if (!self.hasKindFilter) return YES;
    return [self.kinds containsObject:@(kind)];
}

- (void)toggleKind:(SCIDeletedMessageKind)kind {
    NSNumber *k = @(kind);
    if ([self.kinds containsObject:k]) [self.kinds removeObject:k];
    else                                [self.kinds addObject:k];
}

- (void)clearKinds { [self.kinds removeAllObjects]; }

#pragma mark - Date helpers

- (NSDate *)effectiveStart {
    if (self.dateRange == SCIDMDateRangeCustom) return self.customStart;
    NSCalendar *cal = NSCalendar.currentCalendar;
    NSDate *now = [NSDate date];
    switch (self.dateRange) {
        case SCIDMDateRangeToday: return [cal startOfDayForDate:now];
        case SCIDMDateRangeWeek:  return [cal dateByAddingUnit:NSCalendarUnitDay  value:-7  toDate:now options:0];
        case SCIDMDateRangeMonth: return [cal dateByAddingUnit:NSCalendarUnitDay  value:-30 toDate:now options:0];
        default:                  return nil;
    }
}

- (NSDate *)effectiveEnd {
    if (self.dateRange == SCIDMDateRangeCustom) return self.customEnd;
    return nil;
}

- (BOOL)matchKindForMessage:(SCIDeletedMessage *)m {
    return [self matchesKind:m.kind];
}

- (BOOL)matchDateForMessage:(SCIDeletedMessage *)m {
    NSDate *key = m.deletedAt ?: m.capturedAt ?: m.sentAt;
    if (!key) return self.dateRange == SCIDMDateRangeAll;
    NSDate *start = [self effectiveStart];
    NSDate *end   = [self effectiveEnd];
    if (start && [key compare:start] == NSOrderedAscending) return NO;
    if (end   && [key compare:end]   == NSOrderedDescending) return NO;
    return YES;
}

- (BOOL)matchSearchForMessage:(SCIDeletedMessage *)m {
    NSString *q = self.searchText;
    if (!q.length) return YES;
    NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSArray *fields = @[ m.text ?: @"", m.previewText ?: @"",
                         m.senderUsername ?: @"", m.senderFullName ?: @"",
                         m.threadTitle ?: @"" ];
    for (NSString *f in fields) {
        if ([f rangeOfString:q options:opt].location != NSNotFound) return YES;
    }
    return NO;
}

#pragma mark - Apply

- (NSArray<SCIDeletedMessage *> *)apply:(NSArray<SCIDeletedMessage *> *)messages {
    NSMutableArray<SCIDeletedMessage *> *out = [NSMutableArray arrayWithCapacity:messages.count];
    for (SCIDeletedMessage *m in messages) {
        if (![self matchKindForMessage:m])   continue;
        if (![self matchDateForMessage:m])   continue;
        if (![self matchSearchForMessage:m]) continue;
        [out addObject:m];
    }
    NSDate *(^key)(SCIDeletedMessage *) = ^NSDate *(SCIDeletedMessage *m) {
        return m.deletedAt ?: m.capturedAt ?: m.sentAt ?: [NSDate distantPast];
    };
    if (self.sort == SCIDMSortOldest) {
        [out sortUsingComparator:^(SCIDeletedMessage *a, SCIDeletedMessage *b) {
            return [key(a) compare:key(b)];
        }];
    } else {
        [out sortUsingComparator:^(SCIDeletedMessage *a, SCIDeletedMessage *b) {
            return [key(b) compare:key(a)];
        }];
    }
    return out;
}

- (NSArray<SCIDeletedMessageGroup *> *)applyToGroups:(NSArray<SCIDeletedMessageGroup *> *)groups {
    NSMutableArray<SCIDeletedMessageGroup *> *out = [NSMutableArray arrayWithCapacity:groups.count];
    for (SCIDeletedMessageGroup *g in groups) {
        NSArray *filtered = [self apply:g.messages];
        if (!filtered.count) {
            // Search may still match the sender even when no message body does.
            if (self.searchText.length && !self.hasKindFilter
                && self.dateRange == SCIDMDateRangeAll) {
                NSStringCompareOptions opt = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
                BOOL hit = ([(g.senderUsername ?: @"") rangeOfString:self.searchText options:opt].location != NSNotFound)
                        || ([(g.senderFullName ?: @"") rangeOfString:self.searchText options:opt].location != NSNotFound);
                if (!hit) continue;
                filtered = g.messages;
            } else {
                continue;
            }
        }
        SCIDeletedMessageGroup *copy = [SCIDeletedMessageGroup new];
        copy.senderPk            = g.senderPk;
        copy.senderUsername      = g.senderUsername;
        copy.senderFullName      = g.senderFullName;
        copy.senderProfilePicURL = g.senderProfilePicURL;
        copy.messages            = filtered;
        [out addObject:copy];
    }
    if (self.sort == SCIDMSortCountDesc) {
        [out sortUsingComparator:^(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
            if (b.count != a.count) return b.count > a.count ? NSOrderedDescending : NSOrderedAscending;
            return [(b.lastDeletedAt ?: [NSDate distantPast]) compare:(a.lastDeletedAt ?: [NSDate distantPast])];
        }];
    } else if (self.sort == SCIDMSortOldest) {
        [out sortUsingComparator:^(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
            return [(a.lastDeletedAt ?: [NSDate distantFuture]) compare:(b.lastDeletedAt ?: [NSDate distantFuture])];
        }];
    } else {
        [out sortUsingComparator:^(SCIDeletedMessageGroup *a, SCIDeletedMessageGroup *b) {
            return [(b.lastDeletedAt ?: [NSDate distantPast]) compare:(a.lastDeletedAt ?: [NSDate distantPast])];
        }];
    }
    return out;
}

@end
