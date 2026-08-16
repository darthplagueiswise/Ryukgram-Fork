#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, RYGActivityType) {
    RYGActivityTypeRead    = 1 << 0,
    RYGActivityTypeOnline  = 1 << 1,
    RYGActivityTypeOffline = 1 << 2,
    RYGActivityTypeTyping  = 1 << 3,
};

// Notify and log are independent bits, so the mode is a 2-bit field.
typedef NS_ENUM(NSInteger, RYGActivityMode) {
    RYGActivityModeOff       = 0,
    RYGActivityModeLog       = 1 << 0,
    RYGActivityModeNotify    = 1 << 1,
    RYGActivityModeNotifyLog = RYGActivityModeLog | RYGActivityModeNotify,
};

FOUNDATION_EXPORT NSNotificationName const RYGActivityConfigDidChangeNotification;

// Global default per type comes from the mode prefs; a person with an override
// ignores the global and uses their own notify/log masks.
@interface RYGActivityConfig : NSObject

+ (NSArray<NSNumber *> *)allTypes;
+ (NSArray<NSNumber *> *)allModes;
+ (NSString *)titleForType:(RYGActivityType)type;
+ (NSString *)iconForType:(RYGActivityType)type;
+ (UIImage *)imageForType:(RYGActivityType)type;
+ (UIColor *)tintForType:(RYGActivityType)type;
+ (NSString *)titleForMode:(RYGActivityMode)mode;

// Global default per type — one mode carrying the notify and log bits.
+ (RYGActivityMode)globalModeForType:(RYGActivityType)type;
+ (void)setGlobalMode:(RYGActivityMode)mode forType:(RYGActivityType)type;
+ (RYGActivityType)globalNotifyMask;
+ (RYGActivityType)globalLogMask;

// Coarse "run the read-receipt diff at all" gate: master on and Read not Off.
+ (BOOL)readReceiptsActive;

// A person with an override carries two independent masks: notify (what pings you)
// and log (what lands in the activity log). Either can be muted without the other.
+ (BOOL)hasOverrideForPK:(NSString *)pk;
+ (RYGActivityType)overrideMaskForPK:(NSString *)pk;              // = notify mask
+ (RYGActivityType)overrideLogMaskForPK:(NSString *)pk;
+ (BOOL)hasLogOverrideForPK:(NSString *)pk;
+ (void)setNotifyMask:(RYGActivityType)mask forPK:(NSString *)pk;
+ (void)setLogMask:(RYGActivityType)mask forPK:(NSString *)pk;
+ (void)setOverrideNotifyMask:(RYGActivityType)notifyMask logMask:(RYGActivityType)logMask forPK:(NSString *)pk username:(nullable NSString *)username picURL:(nullable NSString *)picURL;
+ (void)clearOverrideForPK:(NSString *)pk;
+ (NSArray<NSString *> *)peopleWithOverrides;
+ (nullable NSString *)overrideUsernameForPK:(NSString *)pk;
+ (nullable NSString *)overridePicURLForPK:(NSString *)pk;

// The two gates every emitter calls.
+ (BOOL)shouldNotifyType:(RYGActivityType)type forPK:(nullable NSString *)pk;
+ (BOOL)shouldLogType:(RYGActivityType)type forPK:(nullable NSString *)pk;

@end

NS_ASSUME_NONNULL_END
