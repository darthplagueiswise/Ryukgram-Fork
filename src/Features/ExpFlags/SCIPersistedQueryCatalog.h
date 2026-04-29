#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SCIPersistedQueryEntry : NSObject

@property (nonatomic, copy) NSString *operationName;
@property (nonatomic, copy) NSString *operationNameHash;
@property (nonatomic, copy) NSString *operationTextHash;
@property (nonatomic, copy) NSString *clientDocID;
@property (nonatomic, copy) NSString *schema;
@property (nonatomic, copy) NSString *category;
@property (nonatomic, copy) NSString *surface;
@property (nonatomic, copy) NSString *rawKey;

- (NSString *)summaryLine;

@end

@interface SCIPersistedQueryCatalog : NSObject

+ (instancetype)sharedCatalog;
+ (void)prewarmInBackground;

- (void)reload;
- (BOOL)isLoaded;
- (NSString *)sourceDescription;
- (NSArray<SCIPersistedQueryEntry *> *)allEntries;
- (NSArray<NSString *> *)allCategories;
- (NSArray<SCIPersistedQueryEntry *> *)entriesForCategory:(NSString *)category;
- (NSArray<SCIPersistedQueryEntry *> *)entriesMatchingQuery:(NSString *)query category:(NSString * _Nullable)category limit:(NSUInteger)limit;
- (SCIPersistedQueryEntry * _Nullable)entryForOperationName:(NSString *)operationName;
- (SCIPersistedQueryEntry * _Nullable)entryForClientDocID:(NSString *)clientDocID;
- (NSArray<SCIPersistedQueryEntry *> *)priorityQuickSnapEntries;
- (NSArray<SCIPersistedQueryEntry *> *)priorityDogfoodEntries;
- (NSString *)diagnosticReport;

@end

NS_ASSUME_NONNULL_END
