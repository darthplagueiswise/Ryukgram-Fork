#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDexKitSelectorRules : NSObject
+ (BOOL)selectorLooksBoolLegacyC:(NSString *)selector;
+ (NSInteger)curatedScoreForClassName:(NSString *)className selector:(NSString *)selector;
+ (BOOL)isCuratedClassName:(NSString *)className selector:(NSString *)selector;
+ (BOOL)isExcludedClassName:(NSString *)className selector:(NSString *)selector;

// Semantic classifier used by DexKit discovery. It is intentionally metadata-only:
// scanner/UI can show safer categories without changing existing override keys or
// hook behavior. Keys returned: semanticCategory, riskLevel, batchForceAllowed,
// observeRecommended, forceRecommended, classificationReason, familyKey.
+ (NSDictionary<NSString *, id> *)classificationForClassName:(NSString *)className
                                                    selector:(NSString *)selector
                                               imageBasename:(NSString *)imageBasename
                                                typeEncoding:(NSString *)typeEncoding;
+ (NSString *)familyKeyForClassName:(NSString *)className selector:(NSString *)selector;
@end

NS_ASSUME_NONNULL_END
