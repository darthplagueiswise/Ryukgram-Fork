#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <pthread.h>

// DirectNotes dogfooding is the canonical native owner for Notes feature types.
// This hook intentionally does NOT create separate RyukGram feature toggles for
// GIF/Music/Location/Icebreaker/etc. The native menu owns those options.
//
// Goal:
//   native DirectNotes Dogfooding UI selection
//   -> original Instagram callback runs first
//   -> restricted native apply/persist/commit/flush sweep on only related objects
//   -> no startup MobileConfig observer, no C++ call, no fake config, no global sweep.

static BOOL gRYDNApplyDisabled = NO;
static pthread_mutex_t gRYDNLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet<NSString *> *gRYDNInstalled;

static NSString *RYDNClassName(id obj) {
    if (!obj) return @"";
    NSString *name = NSStringFromClass([obj class]);
    return name ?: @"";
}

static BOOL RYDNClassLooksRelevantName(NSString *name) {
    NSString *n = name.lowercaseString ?: @"";
    return ([n containsString:@"directnotes"] ||
            [n containsString:@"notesdogfood"] ||
            ([n containsString:@"notes"] && [n containsString:@"dogfood"]) ||
            ([n containsString:@"notes"] && [n containsString:@"settings"]) ||
            ([n containsString:@"notes"] && [n containsString:@"option"]) ||
            ([n containsString:@"notes"] && [n containsString:@"override"]) ||
            ([n containsString:@"notes"] && [n containsString:@"store"]) ||
            ([n containsString:@"notes"] && [n containsString:@"config"]));
}

static BOOL RYDNObjectLooksRelevant(id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return NO;
    return RYDNClassLooksRelevantName(RYDNClassName(obj));
}

static BOOL RYDNSelectorAllowed(NSString *selName) {
    static NSSet<NSString *> *allowed;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowed = [NSSet setWithArray:@[
            @"apply",
            @"persist",
            @"commit",
            @"flush",
            @"save",
            @"synchronize",
            @"applyOverrides",
            @"persistOverrides",
            @"commitOverrides",
            @"flushOverrides",
            @"saveOverrides",
            @"commitChanges",
            @"persistChanges",
            @"applyChanges",
            @"flushChanges",
            @"writeToDisk",
            @"saveToDisk",
            @"updateConfigs",
            @"tryUpdateConfigs"
        ]];
    });
    return [allowed containsObject:selName ?: @""];
}

static BOOL RYDNReturnTypeSafe(Method m) {
    if (!m) return NO;
    char ret[32] = {0};
    method_getReturnType(m, ret, sizeof(ret));
    if (!ret[0]) return NO;
    return ret[0] == 'v' || ret[0] == '@' || ret[0] == 'B' || ret[0] == 'c' || ret[0] == 'C' || ret[0] == 'q' || ret[0] == 'Q' || ret[0] == 'i' || ret[0] == 'I';
}

static void RYDNSafeCallNoArg(id obj, SEL sel) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) return;
    Method m = class_getInstanceMethod([obj class], sel);
    if (!m || method_getNumberOfArguments(m) != 2 || !RYDNReturnTypeSafe(m)) return;
    ((void (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void RYDNQueuePush(NSMutableArray *queue, NSMutableSet *seen, id obj) {
    if (!obj || ![obj isKindOfClass:NSObject.class]) return;
    NSString *key = [NSString stringWithFormat:@"%p", (__bridge void *)obj];
    if ([seen containsObject:key]) return;
    [seen addObject:key];
    [queue addObject:obj];
}

static BOOL RYDNIvarNameUseful(Ivar ivar) {
    const char *raw = ivar ? ivar_getName(ivar) : NULL;
    if (!raw) return NO;
    NSString *n = [[NSString stringWithUTF8String:raw] lowercaseString];
    return [n containsString:@"directnotes"] ||
           [n containsString:@"dogfood"] ||
           [n containsString:@"settings"] ||
           [n containsString:@"option"] ||
           [n containsString:@"override"] ||
           [n containsString:@"store"] ||
           [n containsString:@"config"] ||
           [n containsString:@"manager"] ||
           [n containsString:@"controller"];
}

static id RYDNSafeObjectIvar(id obj, Ivar ivar) {
    if (!obj || !ivar) return nil;
    const char *type = ivar_getTypeEncoding(ivar);
    if (!type || type[0] != '@') return nil;
    return object_getIvar(obj, ivar);
}

static void RYDNApplyPersistFromObject(id root, NSString *reason) {
    if (gRYDNApplyDisabled || !root) return;

    static BOOL inApply = NO;
    if (inApply) return;
    inApply = YES;

    @autoreleasepool {
        NSMutableArray *queue = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        NSMutableSet *called = [NSMutableSet set];
        RYDNQueuePush(queue, seen, root);

        NSUInteger cursor = 0;
        NSUInteger budget = 80;
        while (cursor < queue.count && budget-- > 0) {
            id obj = queue[cursor++];
            NSString *className = RYDNClassName(obj);
            BOOL relevant = RYDNClassLooksRelevantName(className);

            if (relevant) {
                unsigned int methodCount = 0;
                Method *methods = class_copyMethodList([obj class], &methodCount);
                for (unsigned int i = 0; i < methodCount; i++) {
                    SEL sel = method_getName(methods[i]);
                    NSString *selName = NSStringFromSelector(sel);
                    if (!RYDNSelectorAllowed(selName)) continue;
                    if (method_getNumberOfArguments(methods[i]) != 2) continue;
                    if (!RYDNReturnTypeSafe(methods[i])) continue;

                    NSString *callKey = [NSString stringWithFormat:@"%p:%@", (__bridge void *)obj, selName];
                    if ([called containsObject:callKey]) continue;
                    [called addObject:callKey];

                    NSLog(@"[RyukGram][DirectNotesDogfood] %@ -> %@ %@", reason ?: @"persist", className, selName);
                    RYDNSafeCallNoArg(obj, sel);
                }
                if (methods) free(methods);
            }

            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList([obj class], &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                if (!RYDNIvarNameUseful(ivars[i])) continue;
                id value = RYDNSafeObjectIvar(obj, ivars[i]);
                if (value && RYDNObjectLooksRelevant(value)) RYDNQueuePush(queue, seen, value);
            }
            if (ivars) free(ivars);
        }
    }

    inApply = NO;
}

static void RYDNApplyPersistFromMany(NSString *reason, id a, id b, id c) {
    if (gRYDNApplyDisabled) return;
    @try {
        RYDNApplyPersistFromObject(a, reason);
        RYDNApplyPersistFromObject(b, reason);
        RYDNApplyPersistFromObject(c, reason);
    } @catch (id e) {
        gRYDNApplyDisabled = YES;
        NSLog(@"[RyukGram][DirectNotesDogfood] persistence disabled after exception: %@", e);
    }
}

static void (*origRYDNToggleDidToggle)(id self, SEL _cmd, id cell, BOOL didToggle) = NULL;
static void hookRYDNToggleDidToggle(id self, SEL _cmd, id cell, BOOL didToggle) {
    if (origRYDNToggleDidToggle) origRYDNToggleDidToggle(self, _cmd, cell, didToggle);
    RYDNApplyPersistFromMany(@"dogfoodingSettingsToggleCell:didToggle:", self, cell, nil);
}

static void (*origRYDNSelectionUpdatedOptions)(id self, SEL _cmd, id vc, id options) = NULL;
static void hookRYDNSelectionUpdatedOptions(id self, SEL _cmd, id vc, id options) {
    if (origRYDNSelectionUpdatedOptions) origRYDNSelectionUpdatedOptions(self, _cmd, vc, options);
    RYDNApplyPersistFromMany(@"dogfoodingSettingsSelectionViewController:updatedOptions:", self, vc, options);
}

static void RYDNHookSelectorIfPresent(Class cls, SEL sel, IMP replacement, IMP *orig) {
    if (!cls || !sel || !replacement || !orig) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    NSString *key = [NSString stringWithFormat:@"%@:%@", NSStringFromClass(cls), NSStringFromSelector(sel)];

    pthread_mutex_lock(&gRYDNLock);
    if (!gRYDNInstalled) gRYDNInstalled = [NSMutableSet set];
    BOOL exists = [gRYDNInstalled containsObject:key];
    if (!exists) [gRYDNInstalled addObject:key];
    pthread_mutex_unlock(&gRYDNLock);
    if (exists) return;

    MSHookMessageEx(cls, sel, replacement, orig);
    NSLog(@"[RyukGram][DirectNotesDogfood] hooked %@", key);
}

static void RYDNHookClassForCallbacks(Class cls) {
    if (!cls) return;
    RYDNHookSelectorIfPresent(cls,
                             NSSelectorFromString(@"dogfoodingSettingsToggleCell:didToggle:"),
                             (IMP)hookRYDNToggleDidToggle,
                             (IMP *)&origRYDNToggleDidToggle);
    RYDNHookSelectorIfPresent(cls,
                             NSSelectorFromString(@"dogfoodingSettingsSelectionViewController:updatedOptions:"),
                             (IMP)hookRYDNSelectionUpdatedOptions,
                             (IMP *)&origRYDNSelectionUpdatedOptions);
}

static BOOL RYDNClassNameMayOwnDirectNotesDogfood(NSString *name) {
    NSString *n = name.lowercaseString ?: @"";
    return [n containsString:@"directnotesdogfooding"] ||
           ([n containsString:@"dogfooding"] && [n containsString:@"settings"]) ||
           ([n containsString:@"directnotes"] && [n containsString:@"settings"]);
}

static void RYDNInstallDirectNotesDogfoodingHooks(void) {
    RYDNHookClassForCallbacks(NSClassFromString(@"IGDirectNotesDogfoodingSettings"));
    RYDNHookClassForCallbacks(NSClassFromString(@"IGDirectNotesDogfoodingSettings.IGDirectNotesDogfoodingSettingsViewController"));
    RYDNHookClassForCallbacks(NSClassFromString(@"_TtC31IGDirectNotesDogfoodingSettings39IGDirectNotesDogfoodingSettingsViewController"));

    int count = objc_getClassList(NULL, 0);
    if (count <= 0 || count > 30000) return;
    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return;
    int realCount = objc_getClassList(classes, count);
    for (int i = 0; i < realCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (!RYDNClassNameMayOwnDirectNotesDogfood(name)) continue;
        RYDNHookClassForCallbacks(classes[i]);
    }
    free(classes);
}

__attribute__((constructor))
static void RYDNDirectNotesDogfoodingInit(void) {
    @autoreleasepool {
        // No MobileConfig, no observer, no fake option state at launch. This only
        // hooks native dogfooding selection callbacks when their classes exist.
        RYDNInstallDirectNotesDogfoodingHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RYDNInstallDirectNotesDogfoodingHooks();
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            RYDNInstallDirectNotesDogfoodingHooks();
        });
    }
}
