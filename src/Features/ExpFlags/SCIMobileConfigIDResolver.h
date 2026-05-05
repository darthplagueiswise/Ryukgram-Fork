#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIMobileConfigIDResolution : NSObject
@property (nonatomic, copy) NSString *brokerID;
@property (nonatomic, assign) unsigned long long rawValue;
@property (nonatomic, assign) unsigned long long normalizedValue;
@property (nonatomic, copy) NSString *rawHex;
@property (nonatomic, copy) NSString *normalizedHex;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *resolvedName;
@property (nonatomic, copy) NSString *resolvedDetail;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *tagHex;
@property (nonatomic, copy) NSString *familyHex;
@property (nonatomic, copy) NSString *paramHex;
@property (nonatomic, assign) BOOL resolved;
@property (nonatomic, assign) BOOL runtimePointerLike;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface SCIMobileConfigIDResolver : NSObject
+ (NSString *)hexForValue:(unsigned long long)value;
+ (unsigned long long)normalizedSpecifierValue:(unsigned long long)value;
+ (SCIMobileConfigIDResolution *)resolutionForBrokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (NSDictionary *)resolvedDictionaryForBrokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (NSString *)displayTitleForBrokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (NSString *)detailLineForBrokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (NSString *)manualLabelForBrokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (void)setManualLabel:(nullable NSString *)label brokerID:(NSString *)brokerID value:(unsigned long long)value;
+ (void)noteResolvedName:(NSString *)name detail:(nullable NSString *)detail brokerID:(NSString *)brokerID value:(unsigned long long)value source:(nullable NSString *)source;
+ (NSString *)mappingStatusLine;
@end

NS_ASSUME_NONNULL_END
