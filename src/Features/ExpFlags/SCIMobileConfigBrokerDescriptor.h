#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIMCBrokerKind) {
    SCIMCBrokerKindPrimary = 0,
    SCIMCBrokerKindComplement = 1,
    SCIMCBrokerKindCompat = 2,
};

@interface SCIMobileConfigBrokerDescriptor : NSObject
@property (nonatomic, copy) NSString *brokerID;        // Short stable key suffix: ig, igsl, eg, mci...
@property (nonatomic, copy) NSString *symbol;          // Mach-O / dlsym symbol with leading underscore.
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *details;
@property (nonatomic, copy) NSString *imageName;       // FBSharedFramework for this build.
@property (nonatomic, assign) uint64_t expectedOrig8;  // 0 means observation-only/no strict build guard.
@property (nonatomic, assign) uintptr_t vmAddress;
@property (nonatomic, assign) NSUInteger xrefCount;
@property (nonatomic, assign) SCIMCBrokerKind kind;
@property (nonatomic, assign) BOOL exactIGInternalSignature;
+ (NSArray<SCIMobileConfigBrokerDescriptor *> *)allDescriptors;
+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForID:(NSString *)brokerID;
+ (nullable SCIMobileConfigBrokerDescriptor *)descriptorForSymbol:(NSString *)symbol;
@end

NS_ASSUME_NONNULL_END
