#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification;

@interface SCIIgMobileDeprecatedConfigMatch : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *group;
@property (nonatomic, copy) NSString *param;
@property (nonatomic, copy) NSString *evidence;
@property (nonatomic, assign) NSInteger score;
@end

@interface SCIIgMobileDeprecatedConfigCatalog : NSObject

+ (NSDictionary *)importDeprecatedConfigValuesObject:(id)object source:(NSString *)source;
+ (NSDictionary *)importDeprecatedConfigValuesFileAtPath:(NSString *)path;
+ (NSUInteger)configCount;
+ (NSArray<NSString *> *)allKeys;
+ (nullable NSString *)summaryLine;

+ (NSArray<SCIIgMobileDeprecatedConfigMatch *> *)matchesForClassName:(NSString *)className
                                                        selectorName:(NSString *)selectorName
                                                          ownerGroup:(NSString *)ownerGroup
                                                           familyKey:(NSString *)familyKey
                                                    semanticCategory:(NSString *)semanticCategory
                                                               limit:(NSUInteger)limit;

+ (nullable SCIIgMobileDeprecatedConfigMatch *)bestMatchForClassName:(NSString *)className
                                                        selectorName:(NSString *)selectorName
                                                          ownerGroup:(NSString *)ownerGroup
                                                           familyKey:(NSString *)familyKey
                                                    semanticCategory:(NSString *)semanticCategory;
@end

NS_ASSUME_NONNULL_END
