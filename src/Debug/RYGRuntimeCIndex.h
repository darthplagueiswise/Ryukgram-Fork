#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RYGCImportSymbol : NSObject
@property(nonatomic,copy) NSString *imagePath;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *pointerSection;
@property(nonatomic,assign) uint64_t pointerSlot;
@property(nonatomic,assign) uint64_t currentTarget;
@property(nonatomic,assign,getter=isRebindable) BOOL rebindable;
@property(nonatomic,copy,nullable) NSString *knownABI;
@property(nonatomic,assign,getter=isManaged) BOOL managed;
@end

typedef void (^RYGCIndexCompletion)(NSArray<RYGCImportSymbol *> *symbols);

@interface RYGRuntimeCIndex : NSObject
+ (void)requestImportsForImagePath:(NSString *)imagePath completion:(RYGCIndexCompletion)completion;
+ (nullable NSArray<RYGCImportSymbol *> *)cachedImportsForImagePath:(NSString *)imagePath;
+ (void)invalidate;
@end

NS_ASSUME_NONNULL_END
