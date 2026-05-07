#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static void (*origSCIDogMainViewWillDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogMainViewDidDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogSelectionViewWillDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogSelectionViewDidDisappear)(id self, SEL _cmd, BOOL animated);
static void (*origSCIDogMainDidSelect)(id self, SEL _cmd, id tableView, NSIndexPath *indexPath);
static void (*origSCIDogSelectionDidSelect)(id self, SEL _cmd, id tableView, NSIndexPath *indexPath);

static NSString *SCIDogPersistClassName(id obj) {
    if (!obj) return @"nil";
    NSString *name = NSStringFromClass([obj class]);
    return name ?: @"?";
}

static BOOL SCIDogPersistUsefulIvarName(NSString *name) {
    NSString *n = name.lowercaseString;
    return [n containsString:@"dogfood"] ||
           [n containsString:@"config"] ||
           [n containsString:@"setting"] ||
           [n containsString:@"option"] ||
           [n containsString:@"override"] ||
           [n containsString:@"selection"] ||
           [n containsString:@"store"] ||
           [n containsString:@"manager"] ||
           [n containsString:@"coordinator"] ||
           [n containsString:@"viewmodel"] ||
           [n containsString:@"data"] ||
           [n containsString:@"source"] ||
           [n containsString:@"model"];
}

static id SCIDogPersistSafeNoArg(id target, SEL sel) {
    if (!target || !sel || ![target respondsToSelector:sel]) return nil;
    Method method = class_getInstanceMethod([target class], sel);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char ret[64] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    if (ret[0] == '{' || ret[0] == '[' || ret[0] == '(') return nil;
    @try {
        if (ret[0] == 'v') {
            ((void (*)(id, SEL))objc_msgSend)(target, sel);
            return nil;
        }
        id value = ((id (*)(id, SEL))objc_msgSend)(target, sel);
        return value;
    } @catch (__unused id e) {
        return nil;
    }
}

static BOOL SCIDogPersistSendVoidNoArg(id target, NSString *selectorName) {
    if (!target || !selectorName.length) return NO;
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) return NO;
    Method method = class_getInstanceMethod([target class], sel);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char ret[64] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    if (ret[0] == '{' || ret[0] == '[' || ret[0] == '(') return NO;
    @try {
        ((void (*)(id, SEL))objc_msgSend)(target, sel);
        return YES;
    } @catch (__unused id e) {
        return NO;
    }
}

static id SCIDogPersistSafeObjectIvar(id target, Ivar ivar) {
    if (!target || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    @try {
        return object_getIvar(target, ivar);
    } @catch (__unused id e) {
        return nil;
    }
}

static void SCIDogPersistQueuePush(NSMutableArray *queue, NSMutableSet *seen, id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return;
    if ([obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSValue.class] || [obj isKindOfClass:NSNumber.class]) return;
    NSString *key = [NSString stringWithFormat:@"%p", (__bridge void *)obj];
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [queue addObject:obj];
}

static void SCIDogPersistTryObject(id obj, NSString *reason, NSUInteger *count) {
    if (!obj) return;
    NSArray<NSString *> *selectors = @[
        @"save",
        @"saveSettings",
        @"saveChanges",
        @"saveOverrides",
        @"persist",
        @"persistSettings",
        @"persistOverrides",
        @"commit",
        @"commitChanges",
        @"apply",
        @"applyChanges",
        @"applyPendingChanges",
        @"flush",
        @"flushChanges",
        @"synchronize",
        @"sync",
        @"writeToDisk",
        @"writeChanges",
        @"updateConfigOverrides",
        @"updateOverrides",
        @"didUpdateOverrides",
        @"setNeedsRestart",
        @"restartRequired"
    ];

    for (NSString *selectorName in selectors) {
        if (SCIDogPersistSendVoidNoArg(obj, selectorName)) {
            if (count) (*count)++;
            NSLog(@"[RyukGram][DogfoodPersist] %@ sent -%@ to %@ <%p>", reason ?: @"persist", selectorName, SCIDogPersistClassName(obj), obj);
        }
    }
}

static void SCIDogPersistSweepFrom(id root, NSString *reason) {
    if (!root) return;

    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    SCIDogPersistQueuePush(queue, seen, root);

    NSArray<NSString *> *objectSelectors = @[
        @"config",
        @"settingsConfig",
        @"dogfoodingConfig",
        @"dogfoodingSettingsConfig",
        @"option",
        @"options",
        @"override",
        @"overrides",
        @"settings",
        @"store",
        @"settingsStore",
        @"dataSource",
        @"viewModel",
        @"model",
        @"selection",
        @"selectedOption",
        @"coordinator",
        @"manager",
        @"dogfoodingSettings"
    ];

    NSUInteger calls = 0;
    NSUInteger cursor = 0;
    NSUInteger budget = 300;
    while (cursor < queue.count && budget-- > 0) {
        id obj = queue[cursor++];
        SCIDogPersistTryObject(obj, reason, &calls);

        for (NSString *selectorName in objectSelectors) {
            id value = SCIDogPersistSafeNoArg(obj, NSSelectorFromString(selectorName));
            if ([value isKindOfClass:NSArray.class]) {
                for (id item in (NSArray *)value) SCIDogPersistQueuePush(queue, seen, item);
            } else if ([value isKindOfClass:NSDictionary.class]) {
                for (id item in [(NSDictionary *)value allValues]) SCIDogPersistQueuePush(queue, seen, item);
            } else {
                SCIDogPersistQueuePush(queue, seen, value);
            }
        }

        Class cls = [obj class];
        NSUInteger superBudget = 4;
        while (cls && cls != NSObject.class && superBudget-- > 0) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(cls, &count);
            for (unsigned int i = 0; i < count; i++) {
                NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[i]) ?: ""];
                if (!SCIDogPersistUsefulIvarName(name)) continue;
                id value = SCIDogPersistSafeObjectIvar(obj, ivars[i]);
                if ([value isKindOfClass:NSArray.class]) {
                    for (id item in (NSArray *)value) SCIDogPersistQueuePush(queue, seen, item);
                } else if ([value isKindOfClass:NSDictionary.class]) {
                    for (id item in [(NSDictionary *)value allValues]) SCIDogPersistQueuePush(queue, seen, item);
                } else {
                    SCIDogPersistQueuePush(queue, seen, value);
                }
            }
            if (ivars) free(ivars);
            cls = class_getSuperclass(cls);
        }
    }

    [[NSUserDefaults standardUserDefaults] synchronize];
    NSLog(@"[RyukGram][DogfoodPersist] sweep reason=%@ visited=%lu calls=%lu", reason ?: @"?", (unsigned long)seen.count, (unsigned long)calls);
}

static void SCIDogPersistSoon(id root, NSString *reason) {
    if (!root) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIDogPersistSweepFrom(root, reason);
    });
}

static void hookSCIDogMainViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    SCIDogPersistSweepFrom(self, @"main viewWillDisappear before original");
    if (origSCIDogMainViewWillDisappear) origSCIDogMainViewWillDisappear(self, _cmd, animated);
    SCIDogPersistSoon(self, @"main viewWillDisappear after original");
}

static void hookSCIDogMainViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origSCIDogMainViewDidDisappear) origSCIDogMainViewDidDisappear(self, _cmd, animated);
    SCIDogPersistSoon(self, @"main viewDidDisappear");
}

static void hookSCIDogSelectionViewWillDisappear(id self, SEL _cmd, BOOL animated) {
    SCIDogPersistSweepFrom(self, @"selection viewWillDisappear before original");
    if (origSCIDogSelectionViewWillDisappear) origSCIDogSelectionViewWillDisappear(self, _cmd, animated);
    SCIDogPersistSoon(self, @"selection viewWillDisappear after original");
}

static void hookSCIDogSelectionViewDidDisappear(id self, SEL _cmd, BOOL animated) {
    if (origSCIDogSelectionViewDidDisappear) origSCIDogSelectionViewDidDisappear(self, _cmd, animated);
    SCIDogPersistSoon(self, @"selection viewDidDisappear");
}

static void hookSCIDogMainDidSelect(id self, SEL _cmd, id tableView, NSIndexPath *indexPath) {
    if (origSCIDogMainDidSelect) origSCIDogMainDidSelect(self, _cmd, tableView, indexPath);
    SCIDogPersistSoon(self, @"main didSelect");
}

static void hookSCIDogSelectionDidSelect(id self, SEL _cmd, id tableView, NSIndexPath *indexPath) {
    if (origSCIDogSelectionDidSelect) origSCIDogSelectionDidSelect(self, _cmd, tableView, indexPath);
    SCIDogPersistSoon(self, @"selection didSelect");
}

static Class SCIDogPersistResolveClass(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!name.length) continue;
        Class cls = NSClassFromString(name);
        if (cls) return cls;
        cls = (Class)objc_getClass(name.UTF8String);
        if (cls) return cls;
    }
    return Nil;
}

static void SCIDogHookClassMethodIfPresent(Class cls, SEL sel, IMP hook, IMP *orig) {
    if (!cls || !sel || !hook || !orig || *orig) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    MSHookMessageEx(cls, sel, hook, orig);
}

static void SCIDogInstallPersistenceHooks(void) {
    Class mainVC = SCIDogPersistResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsViewController",
        @"IGDogfoodingSettingsViewController",
        @"_TtC20IGDogfoodingSettings34IGDogfoodingSettingsViewController"
    ]);

    Class selectionVC = SCIDogPersistResolveClass(@[
        @"IGDogfoodingSettings.IGDogfoodingSettingsSelectionViewController",
        @"IGDogfoodingSettingsSelectionViewController",
        @"_TtC20IGDogfoodingSettings43IGDogfoodingSettingsSelectionViewController"
    ]);

    SCIDogHookClassMethodIfPresent(mainVC, @selector(viewWillDisappear:), (IMP)hookSCIDogMainViewWillDisappear, (IMP *)&origSCIDogMainViewWillDisappear);
    SCIDogHookClassMethodIfPresent(mainVC, @selector(viewDidDisappear:), (IMP)hookSCIDogMainViewDidDisappear, (IMP *)&origSCIDogMainViewDidDisappear);
    SCIDogHookClassMethodIfPresent(mainVC, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hookSCIDogMainDidSelect, (IMP *)&origSCIDogMainDidSelect);

    SCIDogHookClassMethodIfPresent(selectionVC, @selector(viewWillDisappear:), (IMP)hookSCIDogSelectionViewWillDisappear, (IMP *)&origSCIDogSelectionViewWillDisappear);
    SCIDogHookClassMethodIfPresent(selectionVC, @selector(viewDidDisappear:), (IMP)hookSCIDogSelectionViewDidDisappear, (IMP *)&origSCIDogSelectionViewDidDisappear);
    SCIDogHookClassMethodIfPresent(selectionVC, @selector(tableView:didSelectRowAtIndexPath:), (IMP)hookSCIDogSelectionDidSelect, (IMP *)&origSCIDogSelectionDidSelect);

    NSLog(@"[RyukGram][DogfoodPersist] hooks main=%@ selection=%@", mainVC ? NSStringFromClass(mainVC) : @"nil", selectionVC ? NSStringFromClass(selectionVC) : @"nil");
}

__attribute__((constructor))
static void SCIDogfoodingPersistenceInit(void) {
    @autoreleasepool {
        SCIDogInstallPersistenceHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIDogInstallPersistenceHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIDogInstallPersistenceHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCIDogInstallPersistenceHooks();
        });
    }
}
