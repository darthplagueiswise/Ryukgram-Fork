#import <Foundation/Foundation.h>

@interface SCIMobileConfigMapping : NSObject

+ (NSString *)primaryMobileConfigDirectory;
+ (NSString *)primaryIDNameMappingPath;
+ (NSString *)primaryOverridesPath;
+ (NSString *)bundleIGSchemaPath;

+ (NSArray<NSString *> *)mappingPaths;
+ (NSString *)activeIDNameMappingPath;

+ (NSDictionary<NSNumber *, NSDictionary *> *)idNameMapping;
+ (NSDictionary *)mappingForParamID:(unsigned long long)paramID;
+ (NSString *)resolvedNameForParamID:(unsigned long long)paramID;
+ (NSString *)sourceForParamID:(unsigned long long)paramID;
+ (NSString *)mappingStatusLine;

+ (NSDictionary *)allOverrides;
+ (NSArray<NSNumber *> *)allOverriddenParamIDs;
+ (id)overrideObjectForParamID:(unsigned long long)paramID typeName:(NSString *)typeName;
+ (void)setOverrideObject:(id)value
               forParamID:(unsigned long long)paramID
                 typeName:(NSString *)typeName
                     name:(NSString *)name;
+ (void)removeOverrideForParamID:(unsigned long long)paramID;
+ (void)resetOverrides;

+ (NSArray<NSDictionary *> *)schemaMatchesForQuery:(NSString *)query limit:(NSUInteger)limit;

@end
