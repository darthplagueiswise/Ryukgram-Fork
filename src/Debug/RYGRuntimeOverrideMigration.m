#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kRYGLegacyMethodOverridesKey = @"ryg_runtime_method_overrides_v4";
static NSString *const kRYGLegacyCOverridesKey = @"ryg_runtime_c_overrides_v4";
static NSString *const kRYGOwnerMethodOverridesKeyV5 = @"ryg_runtime_method_overrides_v5";
static NSString *const kRYGOwnerCOverridesKeyV5 = @"ryg_runtime_c_overrides_v5";
static NSString *const kRYGOwnerMigrationDoneKey = @"ryg_runtime_override_owner_v5_migrated";

static BOOL RYGMigrationParseMethodKey(NSString *key, NSString **className, NSString **selectorName, BOOL *classMethod) {
    if (key.length < 4) return NO;
    unichar prefix = [key characterAtIndex:0];
    if (prefix != '+' && prefix != '-') return NO;
    NSString *body = [key substringFromIndex:1];
    NSRange separator = [body rangeOfString:@"#"];
    if (separator.location == NSNotFound || separator.location == 0 || NSMaxRange(separator) >= body.length) return NO;
    if (className) *className = [body substringToIndex:separator.location];
    if (selectorName) *selectorName = [body substringFromIndex:NSMaxRange(separator)];
    if (classMethod) *classMethod = prefix == '+';
    return YES;
}

static RYGRuntimeBoolMethod *RYGMigrationMethod(NSString *key) {
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGMigrationParseMethodKey(key, &className, &selectorName, &classMethod)) return nil;
    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = selectorName.length ? NSSelectorFromString(selectorName) : NULL;
    Class owner = cls ? (classMethod ? object_getClass(cls) : cls) : Nil;
    Method method = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
    if (!method) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.className = className;
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    const char *types = method_getTypeEncoding(method);
    row.typeEncoding = types ? [NSString stringWithUTF8String:types] : @"";
    const char *image = class_getImageName(cls);
    row.imagePath = image ? [NSString stringWithUTF8String:image] : @"";
    return row;
}

static void RYGRunRuntimeOverrideMigration(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kRYGOwnerMigrationDoneKey]) return;

    NSDictionary *legacyMethods = [defaults dictionaryForKey:kRYGLegacyMethodOverridesKey];
    NSMutableDictionary *v5Methods = [[defaults dictionaryForKey:kRYGOwnerMethodOverridesKeyV5] mutableCopy] ?: [NSMutableDictionary dictionary];
    [legacyMethods enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
        (void)stop;
        if (![rawKey isKindOfClass:NSString.class] || ![rawValue isKindOfClass:NSNumber.class]) return;
        if (!v5Methods[rawKey]) v5Methods[rawKey] = @([(NSNumber *)rawValue boolValue]);
    }];
    if (v5Methods.count) [defaults setObject:v5Methods.copy forKey:kRYGOwnerMethodOverridesKeyV5];

    NSDictionary *legacyC = [defaults dictionaryForKey:kRYGLegacyCOverridesKey];
    NSMutableDictionary *v5C = [[defaults dictionaryForKey:kRYGOwnerCOverridesKeyV5] mutableCopy] ?: [NSMutableDictionary dictionary];
    [legacyC enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
        (void)stop;
        if (![rawKey isKindOfClass:NSString.class] || ![rawValue isKindOfClass:NSDictionary.class]) return;
        if (!v5C[rawKey]) v5C[rawKey] = rawValue;
    }];
    if (v5C.count) [defaults setObject:v5C.copy forKey:kRYGOwnerCOverridesKeyV5];
    [defaults setBool:YES forKey:kRYGOwnerMigrationDoneKey];
    [defaults synchronize];

    // RYGRuntimeOverrideOwner has already initialized during +load. Feed legacy
    // method state through the public API so its in-memory owner map is updated
    // immediately instead of waiting for another process launch.
    [legacyMethods enumerateKeysAndObjectsUsingBlock:^(id rawKey, id rawValue, BOOL *stop) {
        (void)stop;
        if (![rawKey isKindOfClass:NSString.class] || ![rawValue isKindOfClass:NSNumber.class]) return;
        RYGRuntimeBoolMethod *method = RYGMigrationMethod(rawKey);
        if (method) [RYGRuntimeBrowserEngine setOverride:@([(NSNumber *)rawValue boolValue]) forMethod:method];
    }];
    [RYGRuntimeBrowserEngine reinstallPersistedOverrides];
}

__attribute__((constructor)) static void RYGInstallRuntimeOverrideMigration(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RYGRunRuntimeOverrideMigration();
    });
}
