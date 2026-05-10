#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SCIMCRuntimeObservationBufferDidFlushNotification;
FOUNDATION_EXPORT NSString * const SCIMCRuntimeObservationBufferBoolEventsKey;
FOUNDATION_EXPORT NSString * const SCIMCRuntimeObservationBufferAliasEventsKey;

typedef void (^SCIMCRuntimeObservationFlushHandler)(NSArray<NSDictionary<NSString *, id> *> *boolEvents,
                                                   NSArray<NSDictionary<NSString *, id> *> *aliasEvents);

/// Hot-path safe capture for MobileConfig/EasyGating boolean reads.
/// This function only stores a small in-memory event and schedules a deferred flush.
/// Do not resolve names, write NSUserDefaults, call dladdr, or post UI notifications from hooks.
void SCIMCRuntimeObservationBufferNoteBoolRead(NSString *brokerID,
                                               uint64_t specifier,
                                               BOOL originalValue,
                                               BOOL finalValue,
                                               uintptr_t callerAddress);

/// Hot-path safe capture for real runtime aliases, for example translated/stable specifiers.
void SCIMCRuntimeObservationBufferNoteAlias(uint64_t rawSpecifier,
                                            uint64_t translatedSpecifier,
                                            NSString *source);

/// Optional consumer used by the resolver/store layer. Called outside the hook path during flush.
void SCIMCRuntimeObservationBufferSetFlushHandler(SCIMCRuntimeObservationFlushHandler _Nullable handler);

/// Forces a synchronous drain on the internal serial queue and posts one notification if data exists.
void SCIMCRuntimeObservationBufferFlushNow(void);

/// Returns the number of currently buffered unique bool events.
NSUInteger SCIMCRuntimeObservationBufferPendingBoolCount(void);

/// Returns the number of currently buffered unique alias events.
NSUInteger SCIMCRuntimeObservationBufferPendingAliasCount(void);

NS_ASSUME_NONNULL_END
