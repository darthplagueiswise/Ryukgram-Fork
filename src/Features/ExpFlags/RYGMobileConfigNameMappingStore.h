#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *RYGMCNameMappingCachePath(void);

FOUNDATION_EXPORT NSDictionary<NSNumber *, NSDictionary *> * _Nullable
RYGMCNameMappingCatalogFromData(NSData *data, NSError **error);

FOUNDATION_EXPORT NSData * _Nullable
RYGMCNameMappingDataFromCatalog(NSDictionary<NSNumber *, NSDictionary *> *catalog,
                                NSError **error);

FOUNDATION_EXPORT NSDictionary<NSNumber *, NSDictionary *> * _Nullable
RYGMCLoadCachedNameMappingCatalog(NSError **error);

FOUNDATION_EXPORT NSData * _Nullable RYGMCLoadCachedNameMappingData(void);

FOUNDATION_EXPORT BOOL
RYGMCSaveNameMappingCatalog(NSDictionary<NSNumber *, NSDictionary *> *catalog,
                            NSError **error);

FOUNDATION_EXPORT void
RYGMCMergeNameMappingCatalog(NSMutableDictionary<NSNumber *, NSDictionary *> *base,
                             NSDictionary<NSNumber *, NSDictionary *> *incoming);

NS_ASSUME_NONNULL_END
