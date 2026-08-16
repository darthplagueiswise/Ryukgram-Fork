#import "RYGAccountObserver.h"
#import "../Utils.h"
#import "../InstagramHeaders.h"
#import <UIKit/UIKit.h>

NSString *const RYGActiveAccountDidChangeNotification = @"RYGActiveAccountDidChangeNotification";
NSString *const RYGAccountObserverPreviousPKKey = @"previousPK";
NSString *const RYGAccountObserverCurrentPKKey = @"currentPK";

static NSString *rygNormPK(NSString *pk) {
    return (pk.length && ![pk isEqualToString:@"0"]) ? pk : nil;
}

@implementation RYGAccountObserver {
    dispatch_queue_t _q;
    NSString *_currentPK;
    NSMutableDictionary<NSNumber *, RYGAccountChangeHandler> *_handlers;
    unsigned long long _nextToken;
    BOOL _started;
}

+ (instancetype)shared {
    static RYGAccountObserver *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [self new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _q = dispatch_queue_create("com.ryuk.account-observer", DISPATCH_QUEUE_SERIAL);
        _handlers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)currentPK {
    __block NSString *pk;
    dispatch_sync(_q, ^{ pk = _currentPK; });
    return pk;
}

- (void)start {
    dispatch_async(_q, ^{
        if (_started) return;
        _started = YES;
        _currentPK = rygNormPK([RYGUtils currentUserPK]);
    });
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(refreshNow) name:UIApplicationDidBecomeActiveNotification object:nil];
    if (@available(iOS 13.0, *))
        [nc addObserver:self selector:@selector(refreshNow) name:UISceneDidActivateNotification object:nil];
}

- (void)refreshNow {
    dispatch_async(_q, ^{
        NSString *pk = rygNormPK([RYGUtils currentUserPK]);
        BOOL same = (pk == _currentPK) || (pk && [pk isEqualToString:_currentPK]);
        if (same) return;
        NSString *prev = _currentPK;
        _currentPK = pk;
        NSArray<RYGAccountChangeHandler> *handlers = [_handlers allValues];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:RYGActiveAccountDidChangeNotification
                                                               object:self
                                                             userInfo:@{
                RYGAccountObserverPreviousPKKey: prev ?: (id)[NSNull null],
                RYGAccountObserverCurrentPKKey: pk ?: (id)[NSNull null],
            }];
            for (RYGAccountChangeHandler h in handlers) h(prev, pk);
        });
    });
}

- (id)addChangeHandler:(RYGAccountChangeHandler)handler {
    if (!handler) return nil;
    __block NSNumber *token;
    dispatch_sync(_q, ^{
        token = @(++_nextToken);
        _handlers[token] = [handler copy];
    });
    return token;
}

- (void)removeChangeHandler:(id)token {
    if (!token) return;
    dispatch_async(_q, ^{ [_handlers removeObjectForKey:token]; });
}

@end

%group RYGAccountObserverTriggers
%hook IGTabBarController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[RYGAccountObserver shared] refreshNow];
}
%end
%hook IGDirectInboxViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[RYGAccountObserver shared] refreshNow];
}
%end
%end

%ctor {
    [[RYGAccountObserver shared] start];
    %init(RYGAccountObserverTriggers);
}
