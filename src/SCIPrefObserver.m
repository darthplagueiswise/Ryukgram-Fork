#import "SCIPrefObserver.h"

@interface SCIPrefObserver ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *handlers;
@property (nonatomic, assign) BOOL notificationObserverInstalled;
@end

@implementation SCIPrefObserver

+ (instancetype)shared {
    static SCIPrefObserver *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SCIPrefObserver new];
        s.handlers = [NSMutableDictionary dictionary];
    });
    return s;
}

+ (void)observeKey:(NSString *)key handler:(void (^)(void))handler {
    if (!key.length || !handler) return;
    SCIPrefObserver *s = [self shared];
    @synchronized (s) {
        NSMutableArray *arr = s.handlers[key];
        if (!arr) {
            arr = [NSMutableArray array];
            s.handlers[key] = arr;
            [[NSUserDefaults standardUserDefaults] addObserver:s
                                                    forKeyPath:key
                                                       options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
                                                       context:NULL];
        }
        if (!s.notificationObserverInstalled) {
            s.notificationObserverInstalled = YES;
            [[NSNotificationCenter defaultCenter] addObserver:s
                                                     selector:@selector(sciDefaultsChanged:)
                                                         name:NSUserDefaultsDidChangeNotification
                                                       object:[NSUserDefaults standardUserDefaults]];
        }
        [arr addObject:[handler copy]];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    NSArray *snapshot;
    @synchronized (self) { snapshot = [self.handlers[keyPath] copy]; }
    if (!snapshot.count) return;
    dispatch_block_t run = ^{
        for (void (^h)(void) in snapshot) h();
    };
    if ([NSThread isMainThread]) run();
    else dispatch_async(dispatch_get_main_queue(), run);
}

- (void)sciDefaultsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if (![key isKindOfClass:NSString.class] || !key.length) return;
    [self observeValueForKeyPath:key ofObject:note.object change:@{} context:NULL];
}

@end
