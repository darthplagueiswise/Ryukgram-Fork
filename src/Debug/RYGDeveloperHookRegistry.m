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
        const uint8_t *cursor = (const uint8_t *)header + (header->magic == MH_MAGIC_64 || header->magic == MH_CIGAM_64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
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

static Method RYGLiveMethod(RYGRuntimeBoolMethod *method, Class *ownerOut) {
    if (!method.className.length || !method.selectorName.length) return NULL;
    Class cls = objc_lookUpClass(method.className.UTF8String);
    if (!cls) return NULL;
    Class owner = method.classMethod ? object_getClass(cls) : cls;
    SEL selector = NSSelectorFromString(method.selectorName);
    Method live = owner && selector ? class_getInstanceMethod(owner, selector) : NULL;
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
    return [NSString stringWithFormat:@"%@|%@|%c|%@|%@", uuid, method.className, method.classMethod ? '+' : '-', method.selectorName, liveEncoding];
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

- (void)startIfNeeded {
    @synchronized (self) {
        if (self.started) return;
        self.started = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak typeof(self) weakSelf = self;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            [weakSelf restorePersistedOverridesForLoadedImages];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf restorePersistedOverridesForLoadedImages];
        });
    });
}

- (NSDictionary *)snapshotOverrides {
    @synchronized (self) { return [self.overrides copy]; }
}

- (void)persistOverrides {
    NSDictionary *snapshot = [self snapshotOverrides];
    [NSUserDefaults.standardUserDefaults setObject:snapshot forKey:kRYGDeveloperOverridesKey];
}

- (NSNumber *)overrideValueForMethod:(RYGRuntimeBoolMethod *)method {
    Method live = RYGLiveMethod(method, NULL);
    NSString *identity = live ? RYGIdentityForMethod(method, live) : nil;
    if (!identity.length) return nil;
    @synchronized (self) { return self.overrides[identity]; }
}

- (BOOL)installShimForMethod:(RYGRuntimeBoolMethod *)method error:(NSError **)error {
    Class owner = Nil;
    Method live = RYGLiveMethod(method, &owner);
    if (!live || !owner) {
        if (error) *error = [NSError errorWithDomain:RYGDeveloperHookErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"Class or selector is not currently loaded."}];
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
    __weak typeof(self) weakSelf = self;
    IMP shim = NULL;
    if (kind == RYGRuntimeArgumentNone) {
        BOOL (^block)(id) = ^BOOL(id receiver) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL))nativeIMP)(receiver, method_getName(live));
        };
        shim = imp_implementationWithBlock(block);
    } else if (kind == RYGRuntimeArgumentObject) {
        BOOL (^block)(id, id) = ^BOOL(id receiver, id argument) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL, id))nativeIMP)(receiver, method_getName(live), argument);
        };
        shim = imp_implementationWithBlock(block);
    } else if (kind == RYGRuntimeArgumentInteger) {
        BOOL (^block)(id, long long) = ^BOOL(id receiver, long long argument) {
            NSNumber *forced = nil;
            @synchronized (weakSelf) { forced = weakSelf.overrides[identity]; }
            if (forced) return forced.boolValue;
            return ((BOOL (*)(id, SEL, long long))nativeIMP)(receiver, method_getName(live), argument);
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
    // Exact identities are restored lazily when their Developer surface is
    // catalogued. We deliberately avoid an objc_getClassList walk here.
    // The retained override dictionary is therefore effectively a quarantine
    // until the live method is rediscovered with the same LC_UUID/encoding.
}

@end
