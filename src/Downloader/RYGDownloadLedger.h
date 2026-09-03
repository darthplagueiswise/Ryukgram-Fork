// Remembers what was already downloaded so a repeat can be caught before it starts.

#import <Foundation/Foundation.h>
#import "RYGDownloadCenter.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGDownloadLedger : NSObject

+ (NSString *)storageDirectory;

+ (NSString *)variantForMediaKind:(RYGDownloadMediaKind)kind;

/// URL identity, plus a media-scoped one when `pk` is set — that second key is what
/// ties a DASH mux to the progressive download of the same post.
+ (NSArray<NSString *> *)keysForURL:(nullable NSURL *)url
                            mediaPK:(nullable NSString *)pk
                            variant:(nullable NSString *)variant;

/// One key group per item. Prompts once when any group matches, then runs `proceed`.
+ (void)guardKeyGroups:(nullable NSArray<NSArray<NSString *> *> *)groups
               proceed:(void (^)(void))proceed;

+ (void)guardKeys:(nullable NSArray<NSString *> *)keys proceed:(void (^)(void))proceed;

/// Runs `block` with the prompt suppressed, for retries and manual redownloads.
+ (void)withBypass:(void (^)(void))block;

+ (void)recordKeys:(nullable NSArray<NSString *> *)keys
             label:(nullable NSString *)label
    galleryFileIDs:(nullable NSArray<NSString *> *)galleryFileIDs;

+ (NSUInteger)count;
+ (void)clearAll;
+ (void)mergeImportedStoreAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
