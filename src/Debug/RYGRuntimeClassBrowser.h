#import <Foundation/Foundation.h>
#import "RYGRuntimeBrowserEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGRuntimeClassRow : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, assign) NSUInteger instanceMethodCount;
@property (nonatomic, assign) NSUInteger classMethodCount;
@property (nonatomic, assign) NSUInteger propertyCount;
@end

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

@interface RYGRuntimeClassBrowser : NSObject
+ (NSArray<RYGRuntimeClassRow *> *)classesForImagePath:(NSString *)imagePath;
+ (NSArray<RYGRuntimeMethodRow *> *)methodsForClass:(RYGRuntimeClassRow *)row classMethods:(BOOL)classMethods;
+ (NSArray<RYGRuntimePropertyRow *> *)propertiesForClass:(RYGRuntimeClassRow *)row classProperties:(BOOL)classProperties;
+ (nullable RYGRuntimeBoolMethod *)boolDescriptorForMethod:(RYGRuntimeMethodRow *)method;
+ (BOOL)methodRow:(RYGRuntimeMethodRow *)row matchesSearch:(NSString *)query;
@end

NS_ASSUME_NONNULL_END
