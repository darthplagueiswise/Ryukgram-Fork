#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIMCBrokerKind) {
    SCIMCBrokerKindPrimary = 0,
    SCIMCBrokerKindComplement = 1,
    SCIMCBrokerKindCompat = 2,
    SCIMCBrokerKindAdvanced = 3,
};

typedef NS_ENUM(NSInteger, SCIMCBrokerABI) {
    SCIMCBrokerABIIGInternalBool = 0,
    SCIMCBrokerABIGeneric8Bool = 1,
};

typedef NS_ENUM(NSInteger, SCIMCBrokerKeyKind) {
    SCIMCBrokerKeyKindSpecifier = 0,
    SCIMCBrokerKeyKindGate = 1,
};

@interface SCIMobileConfigBrokerDescriptor : NSObject
@property (nonatomic, copy) NSString *brokerID;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *details;
@property (nonatomic, copy) NSString *imageName;
@property (nonatomic, assign) uint64_t expectedOrig8;
@property (nonatomic, assign) uintptr_t vmAddress;
@property (nonatomic, assign) NSUInteger xrefCount;
@property (nonatomic, assign) SCIMCBrokerKind kind;
@property (nonatomic, assign) SCIMCBrokerABI abi;
@property (nonatomic, assign) SCIMCBrokerKeyKind keyKind;
@property (nonatomic, assign) NSUInteger keyArgumentIndex;
@property (nonatomic, assign) NSUInteger defaultArgumentIndex;
@property (nonatomic, assign) BOOL exactIGInternalSignature;
+ (NSArray<SCIMobileConfigBrokerDescriptor *> *)allDescriptors;
+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForID:(NSString *)brokerID;
+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForSymbol:(NSString *)symbol;
- (NSString *)namespaceSymbol;
- (NSString *)kindLabel;
- (NSString *)tierLabel;
@end

NS_ASSUME_NONNULL_END
