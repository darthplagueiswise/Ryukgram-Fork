#import "RYGReadReceiptModels.h"

static NSDate *RYGDateFromNum(id v) { return [v isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[v doubleValue]] : nil; }
static NSNumber *RYGNumFromDate(NSDate *d) { return d ? @([d timeIntervalSince1970]) : nil; }

@implementation RYGReadReceipt

+ (instancetype)receiptFromJSONDict:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    RYGReadReceipt *r = [RYGReadReceipt new];
    r.threadId       = dict[@"threadId"];
    r.isGroup        = [dict[@"isGroup"] boolValue];
    r.threadTitle    = dict[@"threadTitle"];
    r.threadAvatarURL = dict[@"threadAvatarURL"];
    r.readerPk       = dict[@"readerPk"];
    r.readerUsername = dict[@"readerUsername"];
    r.readerProfilePicURL = dict[@"readerProfilePicURL"];
    r.messageId      = dict[@"messageId"];
    r.messagePreview = dict[@"messagePreview"];
    r.messageSentAt  = RYGDateFromNum(dict[@"messageSentAt"]);
    r.readAt         = RYGDateFromNum(dict[@"readAt"]) ?: [NSDate date];
    return r;
}

- (NSDictionary *)toJSONDict {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"threadId"]       = self.threadId;
    d[@"isGroup"]        = @(self.isGroup);
    d[@"threadTitle"]    = self.threadTitle;
    d[@"threadAvatarURL"] = self.threadAvatarURL;
    d[@"readerPk"]       = self.readerPk;
    d[@"readerUsername"] = self.readerUsername;
    d[@"readerProfilePicURL"] = self.readerProfilePicURL;
    d[@"messageId"]      = self.messageId;
    d[@"messagePreview"] = self.messagePreview;
    d[@"messageSentAt"]  = RYGNumFromDate(self.messageSentAt);
    d[@"readAt"]         = RYGNumFromDate(self.readAt);
    return d;
}

@end

@implementation RYGReadReceiptGroup

- (NSUInteger)count { return self.receipts.count; }
- (RYGReadReceipt *)latest { return self.receipts.firstObject; }
- (NSDate *)lastReadAt { return self.latest.readAt; }
- (NSString *)identifier { return self.threadId ?: (self.readerPk ?: @""); }

- (NSString *)displayTitle {
    if (self.isGroup) return self.threadTitle.length ? self.threadTitle : @"Group chat";
    NSString *u = self.readerUsername ?: self.latest.readerUsername;
    return u.length ? [@"@" stringByAppendingString:u] : (self.readerPk ?: @"");
}
- (NSString *)displayAvatarURL {
    if (self.isGroup) return self.threadAvatarURL ?: self.latest.threadAvatarURL;
    return self.readerProfilePicURL ?: self.latest.readerProfilePicURL;
}

- (NSArray<RYGReadReceipt *> *)distinctReaders {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (RYGReadReceipt *r in self.receipts) { // newest-first
        if (!r.readerPk || [seen containsObject:r.readerPk]) continue;
        [seen addObject:r.readerPk];
        [out addObject:r];
    }
    return out;
}

@end
