#import <Foundation/Foundation.h>

@interface RYGStoryMarkedSeen : NSObject

+ (void)recordMediaPK:(NSString *)pk;
+ (BOOL)isMarkedMediaPK:(NSString *)pk;

@end
