#import "RYGDeveloperHookRegistry.h"
#import "RYGRuntimeBrowserEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

static NSString *const kRYGDeveloperOverridesKey = @"ryg_developer_bool_overrides_v2";
static NSString *const RYGDeveloperHookErrorDomain = @"com.ryukgram.developerhooks";

static const char *RYGSkipTypeQualifiers(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}

static BOOL RYGMethodShape(Method method, RYGRuntimeArgumentKind *kindOut) {
    if (!method) return NO;
    char ret[32] = {0};
    method_getReturnType(method, ret, sizeof(ret));
    const char *returnType = RYGSkipTypeQualifiers(ret);
    if (!returnType || !strchr("BcC", *returnType)) return NO;

    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) {
        if (kindOut) *kindOut = RYGRuntimeArgumentNone;
        return YES;
    }
    if (count != 3) return NO;

    char arg[64] = {0};
    method_getArgumentType(method, 2, arg, sizeof(arg));
    const char *argumentType = RYGSkipTypeQualifiers(arg);
    if (argumentType && *argumentType == '@') {
        if (kindOut) *kindOut = RYGRuntimeArgumentObject;
        return YES;
    }
    if (argumentType && strchr("qQiIlLsScC", *argumentType)) {
        if (kindOut) *kindOut = RYGRuntimeArgumentInteger;
        return YES;
    }
    return NO;
}

static NSString *RYGUUIDStringForImagePath(NSString *path) {
    if (!path.length) return nil;
    NSString *target = path.stringByStandardizingPath;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *rawName = _dyld_get_image_name(i);
        if (!rawName) continue;
        NSString *candidate = [[NSString stringWithUTF8String:rawName] stringByStandardizingPath];
        if (![candidate isEqualToString:target]) continue;
        const struct mach_header *header = _dyld_get_image_header(i);
        if (!header) return nil;
        const uint8_t *cursor = (const uint8_t *)header +
            (header->magic == MH_MAGIC_64 || header->magic == MH_CIGAM_64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
        for (uint32_t commandIndex = 0; commandIndex < header->ncmds; commandIndex++) {
            const struct load_command *command = (const struct load_command *)cursor;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                const struct uuid_command *uuidCommand = (const struct uuid_command *)cursor;
                const unsigned char *u = uuidCommand->uuid;
                return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                        u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15]];
            }
            if (command->cmdsize < sizeof(struct load_command)) break;
            cursor += command->cmdsize;
        }
        return nil;
    }
    return nil;
}

static Method RYGDirectMethod(Class owner, SEL selector) {
    if (!owner || !selector) return NULL;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(owner, &count);
    Method found = NULL;
    for (unsigned int index = 0; methods && index < count; index++) {
        if (method_getName(methods[index]) == selector) {
            found = methods[index];
            break;
        }
    }
    if (methods) free(methods);
    return found;
}

static Method RYGLiveMethod(RYGRuntimeBoolMethod *method, Class *ownerOut) {
    if (!method.className.length || !method.selectorName.length) return NULL;
    Class cls = objc_lookUpClass(method.className.UTF8String);
    if (!cls) return NULL;
    Class owner = method.classMethod ? object_getClass(cls) : cls;
    SEL selector = NSSelectorFromString(method.selectorName);
    Method live = RYGDirectMethod(owner, selector);
    if (ownerOut) *ownerOut = owner;
    return live;
}

static NSString *RYGIdentityForMethod(RYGRuntimeBoolMethod *method, Method live) {
    Class cls = objc_lookUpClass(method.className.UTF8String);
    if (!cls || !live) return nil;
    const char *rawImage = class_getImageName(cls);
    NSString *image = rawImage ? [NSString stringWithUTF8String:rawImage] : method.imagePath;
    NSString *uuid = RYGUUIDStringForImagePath(image);
    const char *encoding = method_getTypeEncoding(live);
    NSString *liveEncoding = encoding ? [NSString stringWithUTF8String:encoding] : @"";
    if (!uuid.length || !liveEncoding.length) return nil;
    return [NSString stringWithFormat:@"%@|%@|%c|%@|%@", uuid, method.className,
            method.classMethod ? '+' : '-', method.selectorName, liveEncoding];
}

static RYGRuntimeBoolMethod *RYGMethodForPersistedIdentity(NSString *identity) {
    NSArray<NSString *> *parts = [identity componentsSeparatedByString:@"|"];
    if (parts.count != 5) return nil;
    NSString *uuid = parts[0], *className = parts[1], *kind = parts[2], *selectorName = parts[3], *encoding = parts[4];
    if (!uuid.length || !className.length || !selectorName.length || !encoding.length) return nil;
    BOOL classMethod = [kind isEqualToString:@"+"];
    if (!classMethod && ![kind isEqualToString:@"-"]) return nil;

    Class cls = objc_lookUpClass(className.UTF8String);
    if (!cls) return nil;
    const char *rawImage = class_getImageName(cls);
    NSString *imagePath = rawImage ? [NSString stringWithUTF8String:rawImage] : nil;
    if (!imagePath.length || ![[RYGUUIDStringForImagePath(imagePath) uppercaseString] isEqualToString:uuid.uppercaseString]) return nil;

    Class owner = classMethod ? object_getClass(cls) : cls;
    Method live = RYGDirectMethod(owner, NSSelectorFromString(selectorName));
    if (!live) return nil;
    const char *rawEncoding = method_getTypeEncoding(live);
    NSString *liveEncoding = rawEncoding ? [NSString stringWithUTF8String:rawEncoding] : @"";
    if (![liveEncoding isEqualToString:encoding]) return nil;

    RYGRuntimeArgumentKind argumentKind = (RYGRuntimeArgumentKind)-1;
    if (!RYGMethodShape(live, &argumentKind)) return nil;

    RYGRuntimeBoolMethod *method = [RYGRuntimeBoolMethod new];
    method.className = className;
    method.selectorName = selectorName;
    method.classMethod = classMethod;
    method.argumentKind = argumentKind;
    method.typeEncoding = liveEncoding;
    method.imagePath = imagePath;
    return method;
}

@interface RYGDeveloperHookRecord : NSObject
@property (nonatomic, copy) NSString *identity;
@property (nonatomic, assign) IMP nativeIMP;
@property (nonatomic, assign) IMP shimIMP;
@end
@implementation RYGDeveloperHookRecord @end

@interface RYGDeveloperHookRegistry ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, RYGDeveloperHookRecord *> *records;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *overrides;
@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic, assign) BOOL started;
@end

@implementation RYGDeveloperHookRegistry

+ (instancetype)sharedRegistry {
    static RYGDeveloperHookRegistry *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ registry = [self new]; });
    return registry;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.ryukgram.developerhooks", DISPATCH_QUEUE_SERIAL);
        _records = [NSMutableDictionary dictionary];
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:kRYGDeveloperOverridesKey];
        _overrides = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSDictionary<NSString *, NSNumber *> *)snapshotOverrides {
    @synchronized (self) { return [self.overrides copy]; }
}

- (void)startIfNeeded {
    @synchronized (self) {
        if (self.started) return;
        self.started = YES;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            [weakSelf restorePersistedOverridesForLoadedImages];
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                                                         object:nil
                                                          queue:NSOperationQueue.mainQueue
                                                     usingBlock:^(__unused NSNotification *note) {
            [weakSelf restorePersistedOverridesForLoadedImages];
        }];
    });
    if ([self snapshotOverrides].count) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(650 * NSEC_PER_MSEC)), self.queue, ^{
            [weakSelf restorePersistedOverridesForLoadedImages];
        });
    }
}

- (void)persistOverrides {
    NSDictionary *snapshot = [self snapshotOverrides];
    [NSUserDefaults.standardUserDefaults setObject:snapshot forKey:kRYGDeveloperOverridesKey];
}

- (NSNumber *)overrideValueForMethod:(RYGRuntimeBoolMethod *)method {
    Method live = RYGLiveMethod(method, NULL);
    NSString *identity = live ? RYGIdentityForMethod(method, live) : nil;
    if (!identity.length) return nil;
    NSNumber *forced = nil;
    @synchronized (self) { forced = self.overrides[identity]; }
    if (forced) (void)[self installShimForMethod:method error:nil];
    return forced;
}

- (BOOL)installShimForMethod:(RYGRuntimeBoolMethod *)method error:(NSError **)error {
    Class owner = Nil;
    Method live = RYGLiveMethod(method, &owner);
    if (!live || !owner) {
        if (error) *error = [NSError errorWithDomain:RYGDeveloperHookErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"Class or direct selector is not currently loaded."}];
        return NO;
    }
    RYGRuntimeArgumentKind kind = (RYGRuntimeArgumentKind)-1;
    if (!RYGMethodShape(live, &kind) || kind != method.argumentKind) {
        if (error) *error = [NSError errorWithDomain:RYGDeveloperHookErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"The live Objective-C ABI no longer matches this feature."}];
        return NO;
    }
    const char *encoding = method_getTypeEncoding(live);
    NSString *liveEncoding = encoding ? [NSString stringWithUTF8String:encoding] : @"";
    if (method.typeEncoding.length && ![method.typeEncoding isEqualToString:liveEncoding]) {
        if (error) *error = [NSError errorWithDomain:RYGDeveloperHookErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey:@"Type encoding changed; override was quarantined."}];
        return NO;
    }
    NSString *identity = RYGIdentityForMethod(method, live);
    if (!identity.length) {
        if (error) *error = [NSError errorWithDomain:RYGDeveloperHookErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey:@"Owning image has no resolvable LC_UUID."}];
        return NO;
    }

    @synchronized (self) {
        RYGDeveloperHookRecord *existing = self.records[identity];
        if (existing && method_getImplementation(live) == existing.shimIMP) return YES;
    }

    IMP nativeIMP = method_getImplementation(live);
    SEL selector = method_getName(live);
    __weak typeof(self) weakSelf = self;
    IMP shim = NULL;
    if (kind == RYGRuntimeArgumentNone) {
        BOOL (^block)(id) = ^BOOL(id receiver) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL))nativeIMP)(receiver, selector);
        };
        shim = imp_implementationWithBlock(block);
    } else if (kind == RYGRuntimeArgumentObject) {
        BOOL (^block)(id, id) = ^BOOL(id receiver, id argument) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL, id))nativeIMP)(receiver, selector, argument);
        };
        shim = imp_implementationWithBlock(block);
    } else if (kind == RYGRuntimeArgumentInteger) {
        BOOL (^block)(id, long long) = ^BOOL(id receiver, long long argument) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL, long long))nativeIMP)(receiver, selector, argument);
        };
        shim = imp_implementationWithBlock(block);
    }
    if (!shim) return NO;

    method_setImplementation(live, shim);
    RYGDeveloperHookRecord *record = [RYGDeveloperHookRecord new];
    record.identity = identity;
    record.nativeIMP = nativeIMP;
    record.shimIMP = shim;
    @synchronized (self) { self.records[identity] = record; }
    return YES;
}

- (BOOL)setOverrideValue:(NSNumber *)value forMethod:(RYGRuntimeBoolMethod *)method error:(NSError **)error {
    [self startIfNeeded];
    if (![self installShimForMethod:method error:error]) return NO;
    Method live = RYGLiveMethod(method, NULL);
    NSString *identity = live ? RYGIdentityForMethod(method, live) : nil;
    if (!identity.length) return NO;
    @synchronized (self) {
        if (value) self.overrides[identity] = @(value.boolValue);
        else [self.overrides removeObjectForKey:identity];
    }
    [self persistOverrides];
    return YES;
}

- (void)restorePersistedOverridesForLoadedImages {
    NSDictionary<NSString *, NSNumber *> *snapshot = [self snapshotOverrides];
    if (!snapshot.count) return;
    dispatch_async(self.queue, ^{
        @autoreleasepool {
            for (NSString *identity in snapshot) {
                RYGRuntimeBoolMethod *method = RYGMethodForPersistedIdentity(identity);
                if (!method) continue; // exact UUID/class/selector/encoding is not loaded yet
                (void)[self installShimForMethod:method error:nil];
            }
        }
    });
}

@end

__attribute__((constructor(226))) static void RYGDeveloperHookRegistryBootstrap(void) {
    // Intentionally cheap: loads only the persisted identity dictionary and
    // notification observers. No class/image/method enumeration occurs here.
    [[RYGDeveloperHookRegistry sharedRegistry] startIfNeeded];
}
