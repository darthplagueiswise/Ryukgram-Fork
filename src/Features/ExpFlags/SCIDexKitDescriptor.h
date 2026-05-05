#import <Foundation/Foundation.h>

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
- (NSString *)ownerDisplayName;
- (NSString *)ownerGroupKey;
@end

NS_ASSUME_NONNULL_END
