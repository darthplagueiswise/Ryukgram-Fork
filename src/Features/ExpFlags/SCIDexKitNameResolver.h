#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SCIDexKitNameResolverDidUpdateNotification;
extern NSString * const SCIDexKitNameResolverRuntimeFeedDidUpdateNotification;

typedef NS_ENUM(NSInteger, SCIDexKitNameConfidence) {
    SCIDexKitNameConfidenceNone = 0,
    SCIDexKitNameConfidenceLow = 1,
    SCIDexKitNameConfidenceMedium = 2,
    SCIDexKitNameConfidenceHigh = 3,
    SCIDexKitNameConfidenceExact = 4,
};

@interface SCIDexKitResolvedName : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *rawKey;
@property (nonatomic, copy) NSString *normalizedKey;
@property (nonatomic, copy) NSString *family;
@property (nonatomic, copy) NSString *param;
@property (nonatomic, copy) NSString *tag;
@property (nonatomic, assign) SCIDexKitNameConfidence confidence;
@property (nonatomic, assign) BOOL manual;
@property (nonatomic, assign) BOOL runtimeObserved;
@property (nonatomic, assign) BOOL pointerLike;
@property (nonatomic, copy) NSString *callerImage;
@property (nonatomic, copy) NSString *callerSymbol;
@property (nonatomic, copy) NSString *callerAddress;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface SCIDexKitNameResolver : NSObject
+ (uint64_t)normalizedSpecifierValue:(uint64_t)value;
+ (NSString *)hexForValue:(uint64_t)value;
+ (NSArray<NSString *> *)identityCandidatesForBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value;
+ (BOOL)sourceRepresentsExactName:(NSString *)source;
+ (nullable NSString *)manualNameForIdentity:(NSString *)identity;
+ (void)setManualName:(nullable NSString *)name forIdentity:(NSString *)identity;
+ (SCIDexKitResolvedName *)resolveBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value;
+ (NSDictionary *)resolvedDictionaryForBrokerID:(NSString * _Nullable)brokerID value:(uint64_t)value;
+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className
                                     selector:(NSString *)selectorName
                                    specifier:(uint64_t)specifier
                                 defaultValue:(BOOL)defaultValue
                                originalValue:(BOOL)originalValue
                                   finalValue:(BOOL)finalValue
                                       source:(NSString *)source;
+ (void)noteMobileConfigBoolReadWithClassName:(NSString *)className
                                     selector:(NSString *)selectorName
                                    specifier:(uint64_t)specifier
                                 defaultValue:(BOOL)defaultValue
                                originalValue:(BOOL)originalValue
                                   finalValue:(BOOL)finalValue
                                       source:(NSString *)source
                                  callerImage:(nullable NSString *)callerImage
                                 callerSymbol:(nullable NSString *)callerSymbol
                                callerAddress:(uint64_t)callerAddress;
+ (void)noteAliasFromSpecifier:(uint64_t)rawSpecifier
                   toSpecifier:(uint64_t)translatedSpecifier
                        source:(NSString *)source;
@end

NS_ASSUME_NONNULL_END
