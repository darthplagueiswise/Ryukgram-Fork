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
typedef void (^RYGRuntimeMethodsCompletion)(NSArray<RYGRuntimeBoolMethod *> *methods);
typedef void (^RYGRuntimeSearchCompletion)(NSArray<RYGRuntimeBoolMethod *> *matches,
                                            NSUInteger classesScanned,
                                            NSUInteger methodsScanned,
                                            BOOL finished);

@interface RYGRuntimeIndex : NSObject
/// Loads only the class names for an image. It never walks every class method
/// list just to open the browser.
+ (void)requestIndexForImagePath:(NSString *)imagePath completion:(RYGRuntimeIndexCompletion)completion;
/// Resolves ABI-safe BOOL methods for one class on demand.
+ (void)requestMethodsForClassName:(NSString *)className
                         imagePath:(NSString *)imagePath
                        completion:(RYGRuntimeMethodsCompletion)completion;
/// Performs an explicitly requested selector/class search off-main-thread and
/// publishes progressive results. Starting a new search cancels the previous
/// search without blocking the UI.
+ (void)requestSearchForImagePath:(NSString *)imagePath
                            query:(NSString *)query
                       completion:(RYGRuntimeSearchCompletion)completion;
+ (void)cancelActiveSearch;
+ (nullable RYGRuntimeImageIndex *)cachedIndexForImagePath:(NSString *)imagePath;
+ (void)invalidate;
@end

NS_ASSUME_NONNULL_END
