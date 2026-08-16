// Measures RyukGram's own on-disk footprint, broken down per feature store.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "RYGSymbol.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGStorageAccountEntry : NSObject
@property (nonatomic, copy, readonly) NSString *pk;
@property (nonatomic, readonly) unsigned long long byteSize;
@property (nonatomic, readonly) NSUInteger fileCount;
@property (nonatomic, copy, readonly) NSString *displayName;
@end

@interface RYGStorageEntry : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, strong, readonly) RYGSymbol *symbol;
@property (nonatomic, strong, readonly) UIColor *color;
@property (nonatomic, readonly) unsigned long long byteSize;
@property (nonatomic, readonly) NSUInteger fileCount;
@property (nonatomic, copy, readonly, nullable) NSArray<RYGStorageAccountEntry *> *accounts;
@end

@interface RYGStorageUsage : NSObject

// Scans off-main, completes on main, biggest-first.
+ (void)scanWithCompletion:(nullable void (^)(NSArray<RYGStorageEntry *> *entries, unsigned long long total))completion;

// 0 until a scan completes.
+ (unsigned long long)cachedTotal;
+ (void)refreshTotalInBackground;

+ (NSString *)formattedSize:(unsigned long long)bytes;

// Owner of a file in an account-scoped store: "<pk>.<…>", or "media/<pk>/…"
// for blobs. nil for anything else.
+ (nullable NSString *)accountPKForRelativePath:(NSString *)relativePath;

@end

NS_ASSUME_NONNULL_END
