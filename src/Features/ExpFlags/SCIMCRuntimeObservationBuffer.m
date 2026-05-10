#import "SCIMCRuntimeObservationBuffer.h"

NSString * const SCIMCRuntimeObservationBufferDidFlushNotification = @"SCIMCRuntimeObservationBufferDidFlushNotification";
NSString * const SCIMCRuntimeObservationBufferBoolEventsKey = @"boolEvents";
NSString * const SCIMCRuntimeObservationBufferAliasEventsKey = @"aliasEvents";

static dispatch_queue_t gSCIMCBufferQueue;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *gSCIMCBoolEvents;
static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *gSCIMCAliasEvents;
static BOOL gSCIMCFlushScheduled;
static SCIMCRuntimeObservationFlushHandler gSCIMCFlushHandler;

static dispatch_queue_t SCIMCBufferQueue(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSCIMCBufferQueue = dispatch_queue_create("com.ryukgram.mc-runtime-buffer", DISPATCH_QUEUE_SERIAL);
    });
    return gSCIMCBufferQueue;
}

static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *SCIMCBoolEvents(void) {
    if (!gSCIMCBoolEvents) gSCIMCBoolEvents = [NSMutableDictionary dictionary];
    return gSCIMCBoolEvents;
}

static NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, id> *> *SCIMCAliasEvents(void) {
    if (!gSCIMCAliasEvents) gSCIMCAliasEvents = [NSMutableDictionary dictionary];
    return gSCIMCAliasEvents;
}

static NSString *SCIMCHex64(uint64_t value) {
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)value];
}

static void SCIMCScheduleFlushLocked(void) {
    if (gSCIMCFlushScheduled) return;
    gSCIMCFlushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), SCIMCBufferQueue(), ^{
        SCIMCRuntimeObservationBufferFlushNow();
    });
}

void SCIMCRuntimeObservationBufferNoteBoolRead(NSString *brokerID,
                                               uint64_t specifier,
                                               BOOL originalValue,
                                               BOOL finalValue,
                                               uintptr_t callerAddress) {
    if (![brokerID isKindOfClass:NSString.class] || !brokerID.length || specifier == 0) return;

    NSString *bid = [brokerID copy];
    uint64_t value = specifier;
    uintptr_t caller = callerAddress;
    BOOL original = originalValue;
    BOOL final = finalValue;

    dispatch_async(SCIMCBufferQueue(), ^{
        NSString *hex = SCIMCHex64(value);
        NSString *key = [NSString stringWithFormat:@"%@:%@", bid, hex];
        NSMutableDictionary<NSString *, id> *event = SCIMCBoolEvents()[key];
        if (!event) {
            event = [@{
                @"brokerID": bid,
                @"specifier": @(value),
                @"specifierHex": hex,
                @"firstOriginalValue": @(original),
                @"firstFinalValue": @(final),
                @"lastOriginalValue": @(original),
                @"lastFinalValue": @(final),
                @"callerAddress": @((unsigned long long)caller),
                @"hitCount": @1,
                @"firstTimestamp": @([[NSDate date] timeIntervalSince1970]),
                @"lastTimestamp": @([[NSDate date] timeIntervalSince1970])
            } mutableCopy];
            SCIMCBoolEvents()[key] = event;
        } else {
            NSUInteger hits = [event[@"hitCount"] unsignedIntegerValue] + 1;
            event[@"hitCount"] = @(hits);
            event[@"lastOriginalValue"] = @(original);
            event[@"lastFinalValue"] = @(final);
            event[@"callerAddress"] = @((unsigned long long)caller);
            event[@"lastTimestamp"] = @([[NSDate date] timeIntervalSince1970]);
        }
        SCIMCScheduleFlushLocked();
    });
}

void SCIMCRuntimeObservationBufferNoteAlias(uint64_t rawSpecifier,
                                            uint64_t translatedSpecifier,
                                            NSString *source) {
    if (rawSpecifier == 0 || translatedSpecifier == 0 || rawSpecifier == translatedSpecifier) return;

    uint64_t raw = rawSpecifier;
    uint64_t translated = translatedSpecifier;
    NSString *src = [source isKindOfClass:NSString.class] && source.length ? [source copy] : @"runtime-alias";

    dispatch_async(SCIMCBufferQueue(), ^{
        NSString *rawHex = SCIMCHex64(raw);
        NSString *translatedHex = SCIMCHex64(translated);
        NSString *key = [NSString stringWithFormat:@"%@:%@:%@", src, rawHex, translatedHex];
        NSMutableDictionary<NSString *, id> *event = SCIMCAliasEvents()[key];
        if (!event) {
            event = [@{
                @"rawSpecifier": @(raw),
                @"translatedSpecifier": @(translated),
                @"rawSpecifierHex": rawHex,
                @"translatedSpecifierHex": translatedHex,
                @"source": src,
                @"hitCount": @1,
                @"firstTimestamp": @([[NSDate date] timeIntervalSince1970]),
                @"lastTimestamp": @([[NSDate date] timeIntervalSince1970])
            } mutableCopy];
            SCIMCAliasEvents()[key] = event;
        } else {
            NSUInteger hits = [event[@"hitCount"] unsignedIntegerValue] + 1;
            event[@"hitCount"] = @(hits);
            event[@"lastTimestamp"] = @([[NSDate date] timeIntervalSince1970]);
        }
        SCIMCScheduleFlushLocked();
    });
}

void SCIMCRuntimeObservationBufferSetFlushHandler(SCIMCRuntimeObservationFlushHandler handler) {
    SCIMCRuntimeObservationFlushHandler copied = [handler copy];
    dispatch_async(SCIMCBufferQueue(), ^{
        gSCIMCFlushHandler = copied;
    });
}

void SCIMCRuntimeObservationBufferFlushNow(void) {
    dispatch_async(SCIMCBufferQueue(), ^{
        NSArray<NSDictionary<NSString *, id> *> *boolEvents = [SCIMCBoolEvents().allValues copy] ?: @[];
        NSArray<NSDictionary<NSString *, id> *> *aliasEvents = [SCIMCAliasEvents().allValues copy] ?: @[];

        [SCIMCBoolEvents() removeAllObjects];
        [SCIMCAliasEvents() removeAllObjects];
        gSCIMCFlushScheduled = NO;

        if (!boolEvents.count && !aliasEvents.count) return;

        SCIMCRuntimeObservationFlushHandler handler = gSCIMCFlushHandler;
        if (handler) handler(boolEvents, aliasEvents);

        NSDictionary *userInfo = @{
            SCIMCRuntimeObservationBufferBoolEventsKey: boolEvents,
            SCIMCRuntimeObservationBufferAliasEventsKey: aliasEvents
        };

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:SCIMCRuntimeObservationBufferDidFlushNotification
                                                                object:nil
                                                              userInfo:userInfo];
        });
    });
}

NSUInteger SCIMCRuntimeObservationBufferPendingBoolCount(void) {
    __block NSUInteger count = 0;
    dispatch_sync(SCIMCBufferQueue(), ^{
        count = SCIMCBoolEvents().count;
    });
    return count;
}

NSUInteger SCIMCRuntimeObservationBufferPendingAliasCount(void) {
    __block NSUInteger count = 0;
    dispatch_sync(SCIMCBufferQueue(), ^{
        count = SCIMCAliasEvents().count;
    });
    return count;
}
