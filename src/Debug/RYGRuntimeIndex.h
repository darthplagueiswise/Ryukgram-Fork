#import <Foundation/Foundation.h>
#import "RYGRuntimeBrowserEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RYGRuntimeImageIndex : NSObject
@property (nonatomic, copy) NSString *imagePath;
@property (nonatomic, copy) NSArray<RYGRuntimeClassRow *> *classes;
@property (nonatomic, copy) NSDictionary<NSString *, NSArray<RYGRuntimeBoolMethod *> *> *methodsByClass;
@property (nonatomic, assign) NSUInteger classesScanned;
@property (nonatomic, assign) NSUInteger methodsScanned;
@property (nonatomic, assign) NSTimeInterval buildDuration;
- (NSArray<RYGRuntimeBoolMethod *> *)methodsForClassName:(NSString *)className;
@end

typedef void (^RYGRuntimeIndexCompletion)(RYGRuntimeImageIndex *index);

@interface RYGRuntimeIndex : NSObject
+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion;
+ (nullable RYGRuntimeImageIndex *)cachedIndexForImagePath:(NSString *)imagePath;
+ (void)invalidate;
@end

NS_ASSUME_NONNULL_END
