#import <Foundation/Foundation.h>
#import <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIDexKitKnownBoolState) {
    SCIDexKitKnownBoolStateUnknown = -1,
    SCIDexKitKnownBoolStateOff = 0,
    SCIDexKitKnownBoolStateOn = 1,
};

@interface SCIDexKitDescriptor : NSObject <NSCopying>
@property (nonatomic, copy) NSString *imageBasename;
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, copy) NSString *overrideKey;
@property (nonatomic, copy) NSString *observedKey;
@property (nonatomic, assign) BOOL observedKnown;
@property (nonatomic, assign) BOOL observedValue;
@property (nonatomic, strong, nullable) NSNumber *overrideValue;
@property (nonatomic, assign) SCIDexKitKnownBoolState effectiveState;
@property (nonatomic, assign) BOOL hookInstalled;
@property (nonatomic, assign) BOOL unavailable;
@property (nonatomic, copy, nullable) NSString *unavailableReason;
@property (nonatomic, assign) NSInteger curatedScore;

// Commit 1 classifier metadata. These fields do not change existing override
// behavior yet; they let the UI/routing layer distinguish feature gates from
// noisy UI state/default/variant methods in the next commits.
@property (nonatomic, copy) NSString *semanticCategory;
@property (nonatomic, assign) NSInteger riskLevel;
@property (nonatomic, assign) BOOL batchForceAllowed;
@property (nonatomic, assign) BOOL observeRecommended;
@property (nonatomic, assign) BOOL forceRecommended;
@property (nonatomic, copy) NSString *classificationReason;
@property (nonatomic, copy) NSString *familyKey;
@property (nonatomic, assign) uint64_t impAddress;
@property (nonatomic, copy) NSString *impSymbol;
@property (nonatomic, copy) NSString *implementationKey;

- (NSString *)ownerDisplayName;
- (NSString *)ownerGroupKey;
@end

NS_ASSUME_NONNULL_END
