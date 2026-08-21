#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGCImportSymbol : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *rawName;
@property (nonatomic, copy) NSString *bindingKind;
@property (nonatomic, assign) NSUInteger slotCount;
@property (nonatomic, assign) uint64_t firstSlotAddress;
@property (nonatomic, assign) uint64_t currentTarget;
@property (nonatomic, readonly, nullable) NSNumber *overrideValue;
@end

typedef void (^RYGCImportIndexCompletion)(NSArray<RYGCImportSymbol *> *symbols, NSTimeInterval buildDuration);

@interface RYGCImportIndex : NSObject
+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGCImportIndexCompletion)completion;
+ (nullable NSArray<RYGCImportSymbol *> *)cachedIndexForImagePath:(NSString *)imagePath;
+ (void)invalidate;

/// Rebinds only lazy/non-lazy import pointer slots in the selected Mach-O image.
/// This deliberately does not modify __TEXT. The replacement is a scalar x0
/// constant-return trampoline; callers must only use it for an ABI whose result
/// is returned in x0 (BOOL/integer/pointer-sized scalar).
+ (BOOL)setScalarOverride:(nullable NSNumber *)value
                forSymbol:(RYGCImportSymbol *)symbol
                    error:(NSError **)error;
+ (nullable NSNumber *)scalarOverrideForSymbol:(RYGCImportSymbol *)symbol;
@end

NS_ASSUME_NONNULL_END
