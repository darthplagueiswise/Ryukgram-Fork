#import "RYGNSEConfig.h"
#import "../../Utils.h"
#import <objc/runtime.h>

@interface LSBundleProxy : NSObject
@property (nonatomic, readonly) NSDictionary *entitlements;
+ (instancetype)bundleProxyForCurrentProcess;
@end

static NSString *rygGroupId(void) {
    Class cls = objc_getClass("LSBundleProxy");
    if (cls) {
        id proxy = [cls bundleProxyForCurrentProcess];
        NSDictionary *ents = [proxy valueForKey:@"entitlements"];
        NSArray *groups = [ents isKindOfClass:NSDictionary.class] ? ents[@"com.apple.security.application-groups"] : nil;
        if ([groups isKindOfClass:NSArray.class] && groups.count) return groups.firstObject;
    }
    return @"group.com.burbn.instagram";
}

@implementation RYGNSEConfig

+ (NSString *)sharedDir {
    NSURL *g = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:rygGroupId()];
    if (!g) return nil;
    NSURL *d = [g URLByAppendingPathComponent:@"RyukGram" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d.path;
}

+ (void)sync {
    NSString *dir = [self sharedDir];
    if (!dir) return;
    NSDictionary *cfg = @{
        @"enabled": @([RYGUtils getBoolPref:@"nse_viewonce_enabled"]),
        @"log_enabled": @([RYGUtils getBoolPref:@"deleted_messages_log_enabled"]),
        @"capture_normal_media": @([RYGUtils getBoolPref:@"nse_capture_normal_media"]),
    };
    NSData *j = [NSJSONSerialization dataWithJSONObject:cfg options:0 error:nil];
    [j writeToFile:[dir stringByAppendingPathComponent:@"nse_config.json"] atomically:YES];
}

+ (void)startObserving {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *n) {
            static BOOL pending = NO;
            if (pending) return;
            pending = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                pending = NO;
                [self sync];
            });
        }];
    });
    [self sync];
}

@end
