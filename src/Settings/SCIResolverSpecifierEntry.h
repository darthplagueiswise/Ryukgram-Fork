#import <Foundation/Foundation.h>

@interface SCIResolverSpecifierEntry : NSObject
@property (nonatomic, assign) unsigned long long specifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *source; // e.g. "dlsym", "hardcoded", "pattern"
@property (nonatomic, assign) BOOL suggestedValue; // YES = should be forced ON, NO = forced OFF
@end
