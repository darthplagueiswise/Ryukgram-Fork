#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Lightweight, stubbable runtime browser for Instagram internals.
// It does not scan live heap and does not call target methods. It only builds
// method/property/ivar stubs from ObjC metadata on demand, like a safe RuntimeBrowser.
@interface SCIDogfoodStubRuntime : NSObject

+ (NSArray<NSDictionary *> *)stubsMatching:(nullable NSString *)query limit:(NSUInteger)limit;
+ (NSDictionary *)detailsForClassName:(NSString *)className;
+ (void)clearCache;

@end

NS_ASSUME_NONNULL_END
