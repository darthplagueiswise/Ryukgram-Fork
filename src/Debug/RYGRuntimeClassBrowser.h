#import <Foundation/Foundation.h>
#import "RYGRuntimeBrowserEngine.h"

NS_ASSUME_NONNULL_BEGIN

// Compatibility presentation models used by the existing class-detail UI.
// RYGRuntimeClassRow itself is owned by RYGRuntimeBrowserEngine so there is a
// single runtime/image enumeration implementation.
@interface RYGRuntimeMethodRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, copy) NSString *selectorName;
@property (nonatomic, copy) NSString *typeEncoding;
@property (nonatomic, assign) BOOL classMethod;
@property (nonatomic, assign) BOOL hookableBool;
@property (nonatomic, assign) RYGRuntimeArgumentKind argumentKind;
@end

@interface RYGRuntimePropertyRow : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *attributes;
@property (nonatomic, assign) BOOL classProperty;
@end

/// Thin UI adapter over RYGRuntimeBrowserEngine. No independent scan, feature
/// keyword classification, cached table, or Class-object retention lives here.
@interface RYGRuntimeClassBrowser : NSObject
+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath;
+ (NSArray<RYGRuntimeMethodRow *> *)methodsForClass:(RYGRuntimeClassRow *)row classMethods:(BOOL)classMethods;
+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row;
+ (nullable RYGRuntimeBoolMethod *)boolDescriptorForMethod:(RYGRuntimeMethodRow *)method;
+ (BOOL)methodRow:(RYGRuntimeMethodRow *)row matchesSearch:(NSString *)query;
@end

NS_ASSUME_NONNULL_END
