#import <Foundation/Foundation.h>

@interface SCIExpMobileConfigDebug : NSObject

+ (void)noteContext:(id)context source:(NSString *)source;
+ (NSString *)debugState;
+ (NSString *)runDebugDumps;

@end
