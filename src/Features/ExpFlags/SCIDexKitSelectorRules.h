#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIDexKitSelectorRules : NSObject
+ (BOOL)selectorLooksBoolLegacyC:(NSString *)selector;
+ (NSInteger)curatedScoreForClassName:(NSString *)className selector:(NSString *)selector;
+ (BOOL)isCuratedClassName:(NSString *)className selector:(NSString *)selector;
+ (BOOL)isExcludedClassName:(NSString *)className selector:(NSString *)selector;
@end

NS_ASSUME_NONNULL_END
