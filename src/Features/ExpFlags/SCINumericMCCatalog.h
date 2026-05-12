#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SCINumericMCCatalogDidReloadNotification;

@interface SCINumericMCEntry : NSObject
@property (nonatomic, copy) NSString *specifierHex;
@property (nonatomic, assign) unsigned long long specifier;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *featureGroup;
@property (nonatomic, copy) NSString *classification;
@property (nonatomic, strong, nullable) NSNumber *recommendedValue;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *confidence;
@property (nonatomic, copy) NSString *fileoff;
@property (nonatomic, copy) NSString *vmaddr;
@property (nonatomic, copy) NSArray<NSString *> *evidence;
@property (nonatomic, readonly) NSString *overrideKey;
@property (nonatomic, readonly) NSString *displayTitle;
@property (nonatomic, readonly) NSString *displaySubtitle;
@end

@interface SCINumericMCCatalog : NSObject
+ (NSString *)catalogPath;
+ (BOOL)hasInstalledCatalog;
+ (NSString *)sourceDescription;
+ (BOOL)installCatalogJSONData:(NSData *)data error:(NSError **)error;
+ (void)reload;
+ (NSArray<SCINumericMCEntry *> *)allEntries;
+ (NSArray<NSString *> *)allFeatureGroups;
+ (NSArray<SCINumericMCEntry *> *)entriesForFeatureGroup:(nullable NSString *)group;
+ (NSArray<SCINumericMCEntry *> *)entriesMatchingQuery:(nullable NSString *)query group:(nullable NSString *)group;
+ (NSUInteger)entryCount;
@end

NS_ASSUME_NONNULL_END
