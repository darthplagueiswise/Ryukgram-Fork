// Ivar-walking helpers. IG's Swift-bridged objects reject KVC for most keys, so
// we read via class_getInstanceVariable + object_getIvar. Same shape as the
// sciStrIvar / sciAnyIvar pattern in SCIDeletedMessagesCapture.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

static inline id _Nullable SCIBgIvarValue(id _Nullable obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = NULL;
    for (Class c = [obj class]; c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, name);
    if (!iv) return nil;
    const char *type = ivar_getTypeEncoding(iv);
    // object_getIvar is unsafe on primitive ivars (BOOL/int/struct) — gate on encoding.
    if (!type || type[0] != '@') return nil;
    @try { return object_getIvar(obj, iv); } @catch (__unused id e) { return nil; }
}

static inline NSString *_Nullable SCIBgStringIvar(id _Nullable obj, const char *name) {
    id v = SCIBgIvarValue(obj, name);
    return [v isKindOfClass:NSString.class] ? v : nil;
}

// IG 430+: IGDirectThreadKey._djangoThread_identifier (IGDirectDjangoThreadIdentifier)
// ._serverThread_threadId carries the real id. Legacy keys kept as fallbacks.
static inline NSString *_Nullable SCIBgReadTidFromContainer(id _Nullable container) {
    if (!container) return nil;
    static const char *kTidIvars[] = {
        "_djangoThread_identifier",
        "_threadId", "_threadID", "_threadIdentifier", "_id", "_pk", NULL
    };
    for (int i = 0; kTidIvars[i]; i++) {
        id v = SCIBgIvarValue(container, kTidIvars[i]);
        if ([v isKindOfClass:NSString.class] && ((NSString *)v).length) return v;
        if ([v isKindOfClass:NSNumber.class]) return [(NSNumber *)v stringValue];
        if (v) {
            static const char *kInnerIds[] = {
                "_serverThread_threadId",
                "_localMetaAINonCanonicalThread_localThreadId",
                "_identifier", "_value", "_threadId", "_threadID", "_string", "_rawValue", NULL
            };
            for (int j = 0; kInnerIds[j]; j++) {
                NSString *s = SCIBgStringIvar(v, kInnerIds[j]);
                if (s.length) return s;
            }
        }
    }
    return nil;
}

// Walks `obj`'s ivars (then one level deeper) for any value whose class name
// contains "ThreadKey" — handles shapes like session._threadInfoProvider._threadKey.
static inline id _Nullable SCIBgFindThreadKey(id _Nullable obj) {
    if (!obj) return nil;
    unsigned int n = 0;
    Ivar *list = class_copyIvarList([obj class], &n);
    id direct = nil;
    NSMutableArray *children = [NSMutableArray new];
    for (unsigned int i = 0; i < n; i++) {
        const char *type = ivar_getTypeEncoding(list[i]);
        if (!type || type[0] != '@') continue;
        id v = nil;
        @try { v = object_getIvar(obj, list[i]); } @catch (__unused id e) {}
        if (!v) continue;
        NSString *cls = NSStringFromClass([v class]);
        if ([cls containsString:@"ThreadKey"]) { direct = v; break; }
        if ([cls hasPrefix:@"IG"] || [cls hasPrefix:@"_TtC"]) [children addObject:v];
    }
    free(list);
    if (direct) return direct;
    for (id child in children) {
        unsigned int cn = 0;
        Ivar *cl = class_copyIvarList([child class], &cn);
        id hit = nil;
        for (unsigned int i = 0; i < cn; i++) {
            const char *type = ivar_getTypeEncoding(cl[i]);
            if (!type || type[0] != '@') continue;
            id v = nil;
            @try { v = object_getIvar(child, cl[i]); } @catch (__unused id e) {}
            if (!v) continue;
            if ([NSStringFromClass([v class]) containsString:@"ThreadKey"]) { hit = v; break; }
        }
        free(cl);
        if (hit) return hit;
    }
    return nil;
}

NS_ASSUME_NONNULL_END
