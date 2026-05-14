#import "SCIMobileConfigIdNameMappingExporter.h"
#import "SCIIgMobileDeprecatedConfigCatalog.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const kSCIIgMobileExporterStatusKey = @"sci.mc.id_name_mapping_exporter.last_status";

static id SCIIGCallClass0(Class cls, NSString *selName) {
    if (!cls || !selName.length) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (!class_getClassMethod(cls, sel)) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, sel);
}

static id SCIIGCallObj0(id obj, NSString *selName) {
    if (!obj || !selName.length) return nil;
    SEL sel = NSSelectorFromString(selName);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static NSString *SCIIGISODate(NSDate *date) {
    if (![date isKindOfClass:NSDate.class]) return @"";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    return [fmt stringFromDate:date] ?: @"";
}

static NSData *SCIIGDataFromObject(id obj) {
    if (!obj) return nil;
    if ([obj isKindOfClass:NSData.class]) return obj;
    if ([obj isKindOfClass:NSString.class]) return [(NSString *)obj dataUsingEncoding:NSUTF8StringEncoding];
    if ([NSJSONSerialization isValidJSONObject:obj]) return [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
    NSString *desc = [obj respondsToSelector:@selector(description)] ? [obj description] : @"";
    return desc.length ? [desc dataUsingEncoding:NSUTF8StringEncoding] : nil;
}

static BOOL SCIIGWriteData(NSData *data, NSString *path, NSMutableArray<NSString *> *outputs, NSMutableArray<NSString *> *errors) {
    if (!data.length || !path.length) return NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = path.stringByDeletingLastPathComponent;
    NSError *dirError = nil;
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&dirError]) {
        [errors addObject:[NSString stringWithFormat:@"mkdir failed %@: %@", dir, dirError.localizedDescription ?: @"unknown"]];
        return NO;
    }
    NSError *writeError = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        [errors addObject:[NSString stringWithFormat:@"write failed %@: %@", path, writeError.localizedDescription ?: @"unknown"]];
        return NO;
    }
    [outputs addObject:path];
    return YES;
}

static NSDictionary *SCIIGExportDeprecatedJSON(void) {
    NSMutableArray<NSString *> *outputs = [NSMutableArray array];
    NSMutableArray<NSString *> *errors = [NSMutableArray array];

    Class cls = NSClassFromString(@"FBMobileConfigStartupConfigsDeprecated");
    if (!cls) return @{@"ok": @NO, @"status": @"IGMobile deprecated startup configs missing", @"outputs": outputs, @"errors": errors, @"configValuesCount": @0, @"configValuesOverrideCount": @0, @"catalogImport": @{}};

    id inst = SCIIGCallClass0(cls, @"getInstance");
    if (!inst) { @try { inst = [[cls alloc] init]; } @catch (__unused id ex) {} }
    if (!inst) return @{@"ok": @NO, @"status": @"IGMobile deprecated startup configs instance unavailable", @"outputs": outputs, @"errors": errors, @"configValuesCount": @0, @"configValuesOverrideCount": @0, @"catalogImport": @{}};

    id toJSON = SCIIGCallObj0(inst, @"toJSON");
    id values = SCIIGCallObj0(inst, @"configValues") ?: @{};
    id overrides = SCIIGCallObj0(inst, @"configValuesOverride") ?: @{};

    NSUInteger valuesCount = [values respondsToSelector:@selector(count)] ? [values count] : 0;
    NSUInteger overrideCount = [overrides respondsToSelector:@selector(count)] ? [overrides count] : 0;

    NSDictionary *catalogImport = [SCIIgMobileDeprecatedConfigCatalog importDeprecatedConfigValuesObject:@{
        @"configValues": values ?: @{},
        @"configValuesOverride": overrides ?: @{},
        @"configValuesCount": @(valuesCount),
        @"configValuesOverrideCount": @(overrideCount)
    } source:@"FBMobileConfigStartupConfigsDeprecated"] ?: @{};

    NSData *raw = SCIIGDataFromObject(toJSON);
    NSData *packed = SCIIGDataFromObject(@{
        @"source": @"FBMobileConfigStartupConfigsDeprecated",
        @"class": NSStringFromClass(cls) ?: @"",
        @"configValues": values ?: @{},
        @"configValuesOverride": overrides ?: @{},
        @"configValuesCount": @(valuesCount),
        @"configValuesOverrideCount": @(overrideCount),
        @"exportedAt": SCIIGISODate([NSDate date])
    });

    NSString *home = NSHomeDirectory() ?: @"";
    NSArray<NSString *> *dirs = @[
        [home stringByAppendingPathComponent:@"Documents/RyukGram/mobileconfig"],
        [[home stringByAppendingPathComponent:@"Library/Application Support"] stringByAppendingPathComponent:@"RyukGram/mobileconfig"]
    ];

    for (NSString *dir in dirs) {
        if (raw.length) SCIIGWriteData(raw, [dir stringByAppendingPathComponent:@"igmobile_deprecated_toJSON.json"], outputs, errors);
        if (packed.length) SCIIGWriteData(packed, [dir stringByAppendingPathComponent:@"igmobile_deprecated_configValues.json"], outputs, errors);
    }

    NSString *status = [NSString stringWithFormat:@"IGMobile deprecated startup configs exported · values=%lu overrides=%lu outputs=%lu", (unsigned long)valuesCount, (unsigned long)overrideCount, (unsigned long)outputs.count];
    [NSUserDefaults.standardUserDefaults setObject:status forKey:kSCIIgMobileExporterStatusKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    [[NSNotificationCenter defaultCenter] postNotificationName:SCIMobileConfigIdNameMappingExporterDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification object:nil];

    return @{
        @"ok": @(outputs.count > 0),
        @"status": status,
        @"outputs": outputs,
        @"errors": errors,
        @"configValuesCount": @(valuesCount),
        @"configValuesOverrideCount": @(overrideCount),
        @"catalogImport": catalogImport
    };
}

@implementation SCIMobileConfigIdNameMappingExporter (SCIIgMobileDeprecatedJSON)

+ (NSDictionary *)exportIGMobileDeprecatedJSONNow {
    return SCIIGExportDeprecatedJSON();
}

+ (NSDictionary *)exportDeprecatedStartupConfigsNow {
    return SCIIGExportDeprecatedJSON();
}

+ (NSDictionary *)exportIDNameMappingNow {
    return SCIIGExportDeprecatedJSON();
}

@end
