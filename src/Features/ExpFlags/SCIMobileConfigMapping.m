#import "SCIMobileConfigMapping.h"

@implementation SCIMobileConfigMapping
+ (NSString *)primaryMobileConfigDirectory { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/mobileconfig"]; }
+ (NSString *)primaryIDNameMappingPath { return [[self primaryMobileConfigDirectory] stringByAppendingPathComponent:@"id_name_mapping.json"]; }
+ (NSString *)primaryOverridesPath { return [[self primaryMobileConfigDirectory] stringByAppendingPathComponent:@"mc_overrides.json"]; }
+ (NSString *)bundleIGSchemaPath { return [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/igios-instagram-schema_client-persist.json"]; }
+ (NSDictionary<NSNumber *, NSDictionary *> *)idNameMapping { return @{}; }
+ (NSDictionary *)mappingForParamID:(unsigned long long)paramID { return nil; }
+ (NSString *)resolvedNameForParamID:(unsigned long long)paramID { return nil; }
+ (NSString *)sourceForParamID:(unsigned long long)paramID { return nil; }
+ (NSString *)mappingStatusLine { return @"mapping=0"; }
+ (NSDictionary *)allOverrides { return @{}; }
+ (NSArray<NSNumber *> *)allOverriddenParamIDs { return @[]; }
+ (id)overrideObjectForParamID:(unsigned long long)paramID typeName:(NSString *)typeName { return nil; }
+ (void)setOverrideObject:(id)value forParamID:(unsigned long long)paramID typeName:(NSString *)typeName name:(NSString *)name {}
+ (void)removeOverrideForParamID:(unsigned long long)paramID {}
+ (void)resetOverrides {}
+ (NSArray<NSDictionary *> *)schemaMatchesForQuery:(NSString *)query limit:(NSUInteger)limit { return @[]; }
@end
