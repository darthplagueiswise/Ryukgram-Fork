// IG share-link rewrite — domain swap + tracking strip across copy / share / DM compose.
// UIPasteboard setters live on _UIConcretePasteboard, not the abstract base.

#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static NSArray<NSString *> *rygIGDomains(void) {
    static NSArray *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @[@"www.instagram.com", @"instagram.com", @"www.instagr.am", @"instagr.am"];
    });
    return d;
}

static BOOL rygLooksLikeIGURL(NSString *s) {
    if (s.length < 12 || s.length > 4096) return NO;
    for (NSString *d in rygIGDomains()) {
        if ([s containsString:d]) return YES;
    }
    return NO;
}

static NSString *rygRewriteIGURL(NSString *url) {
    if (!url.length) return url;

    if ([RYGUtils getBoolPref:@"embed_links"]) {
        NSString *domain = [RYGUtils getStringPref:@"embed_link_domain"];
        if (!domain.length) domain = @"kkinstagram.com";
        if (![url containsString:domain]) {
            for (NSString *d in rygIGDomains()) {
                NSRange r = [url rangeOfString:d];
                if (r.location != NSNotFound) {
                    NSString *target = [d hasPrefix:@"www."]
                        ? [NSString stringWithFormat:@"www.%@", domain] : domain;
                    url = [url stringByReplacingCharactersInRange:r withString:target];
                    break;
                }
            }
        }
    }

    if ([RYGUtils getBoolPref:@"strip_tracking_params"]) {
        NSURLComponents *comps = [NSURLComponents componentsWithString:url];
        if (comps.queryItems.count) {
            NSArray *strip = @[@"igsh", @"ig_rid", @"igshid", @"utm_source", @"utm_medium", @"utm_campaign", @"utm_term", @"utm_content"];
            NSMutableArray *clean = [NSMutableArray array];
            for (NSURLQueryItem *q in comps.queryItems) {
                if (![strip containsObject:q.name]) [clean addObject:q];
            }
            comps.queryItems = clean.count ? clean : nil;
            NSString *result = comps.string;
            if (result) url = result;
        }
    }

    return url;
}

static BOOL rygShouldRewrite(void) {
    return [RYGUtils getBoolPref:@"embed_links"] || [RYGUtils getBoolPref:@"strip_tracking_params"];
}

// Returns nil when no rewrite is needed so callers can keep the original ref.
static id rygRewriteValue(id v) {
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = v;
        if (!rygLooksLikeIGURL(s)) return nil;
        NSString *r = rygRewriteIGURL(s);
        return [r isEqualToString:s] ? nil : r;
    }
    if ([v isKindOfClass:[NSURL class]]) {
        NSString *s = [(NSURL *)v absoluteString];
        if (!rygLooksLikeIGURL(s)) return nil;
        NSString *r = rygRewriteIGURL(s);
        if ([r isEqualToString:s]) return nil;
        return [NSURL URLWithString:r] ?: nil;
    }
    if ([v isKindOfClass:[NSAttributedString class]]) {
        NSString *s = [(NSAttributedString *)v string];
        if (!rygLooksLikeIGURL(s)) return nil;
        NSString *r = rygRewriteIGURL(s);
        if ([r isEqualToString:s]) return nil;
        NSMutableAttributedString *m = [(NSAttributedString *)v mutableCopy];
        [m replaceCharactersInRange:NSMakeRange(0, m.length) withString:r];
        return [m copy];
    }
    return nil;
}


static NSArray *rygRewriteItemArray(NSArray *items) {
    if (!items.count) return items;
    NSMutableArray *out = nil;
    for (NSUInteger i = 0; i < items.count; i++) {
        id entry = items[i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *replacement = nil;
        for (id key in (NSDictionary *)entry) {
            id r = rygRewriteValue(entry[key]);
            if (!r) continue;
            if (!replacement) replacement = [(NSDictionary *)entry mutableCopy];
            replacement[key] = r;
        }
        if (replacement) {
            if (!out) out = [items mutableCopy];
            out[i] = replacement;
        }
    }
    return out ?: items;
}

static NSArray *rygRewriteObjectArray(NSArray *objs) {
    if (!objs.count) return objs;
    NSMutableArray *out = nil;
    for (NSUInteger i = 0; i < objs.count; i++) {
        id r = rygRewriteValue(objs[i]);
        if (!r) continue;
        if (!out) out = [objs mutableCopy];
        out[i] = r;
    }
    return out ?: objs;
}

static void (*orig_setString)(UIPasteboard *, SEL, NSString *);
static void new_setString(UIPasteboard *self, SEL _cmd, NSString *value) {
    if (rygShouldRewrite() && [value isKindOfClass:[NSString class]] && rygLooksLikeIGURL(value)) {
        value = rygRewriteIGURL(value);
    }
    orig_setString(self, _cmd, value);
}

static void (*orig_setURL)(UIPasteboard *, SEL, NSURL *);
static void new_setURL(UIPasteboard *self, SEL _cmd, NSURL *value) {
    if (rygShouldRewrite() && [value isKindOfClass:[NSURL class]]) {
        id r = rygRewriteValue(value);
        if (r) value = r;
    }
    orig_setURL(self, _cmd, value);
}

static void (*orig_setStrings)(UIPasteboard *, SEL, NSArray *);
static void new_setStrings(UIPasteboard *self, SEL _cmd, NSArray *strings) {
    if (rygShouldRewrite()) strings = rygRewriteObjectArray(strings);
    orig_setStrings(self, _cmd, strings);
}

static void (*orig_setURLs)(UIPasteboard *, SEL, NSArray *);
static void new_setURLs(UIPasteboard *self, SEL _cmd, NSArray *urls) {
    if (rygShouldRewrite()) urls = rygRewriteObjectArray(urls);
    orig_setURLs(self, _cmd, urls);
}

static void (*orig_setObjects)(UIPasteboard *, SEL, NSArray *);
static void new_setObjects(UIPasteboard *self, SEL _cmd, NSArray *objs) {
    if (rygShouldRewrite()) objs = rygRewriteObjectArray(objs);
    orig_setObjects(self, _cmd, objs);
}

static void (*orig_setObjectsOpts)(UIPasteboard *, SEL, NSArray *, NSDictionary *);
static void new_setObjectsOpts(UIPasteboard *self, SEL _cmd, NSArray *objs, NSDictionary *opts) {
    if (rygShouldRewrite()) objs = rygRewriteObjectArray(objs);
    orig_setObjectsOpts(self, _cmd, objs, opts);
}

static void (*orig_setObjectsLO)(UIPasteboard *, SEL, NSArray *, BOOL, NSDate *);
static void new_setObjectsLO(UIPasteboard *self, SEL _cmd, NSArray *objs, BOOL localOnly, NSDate *exp) {
    if (rygShouldRewrite()) objs = rygRewriteObjectArray(objs);
    orig_setObjectsLO(self, _cmd, objs, localOnly, exp);
}

static void (*orig_setItems)(UIPasteboard *, SEL, NSArray *);
static void new_setItems(UIPasteboard *self, SEL _cmd, NSArray *items) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_setItems(self, _cmd, items);
}

static void (*orig_setItemsOpts)(UIPasteboard *, SEL, NSArray *, NSDictionary *);
static void new_setItemsOpts(UIPasteboard *self, SEL _cmd, NSArray *items, NSDictionary *opts) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_setItemsOpts(self, _cmd, items, opts);
}

static void (*orig_addItems)(UIPasteboard *, SEL, NSArray *);
static void new_addItems(UIPasteboard *self, SEL _cmd, NSArray *items) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_addItems(self, _cmd, items);
}

// Private sink the public setters chain through — covered so any direct caller still rewrites.
static void (*orig_setItemsAndSave)(UIPasteboard *, SEL, NSArray *, NSDictionary *);
static void new_setItemsAndSave(UIPasteboard *self, SEL _cmd, NSArray *items, NSDictionary *opts) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_setItemsAndSave(self, _cmd, items, opts);
}

static void (*orig_setItemsAndSaveCoerce)(UIPasteboard *, SEL, NSArray *, NSDictionary *, BOOL);
static void new_setItemsAndSaveCoerce(UIPasteboard *self, SEL _cmd, NSArray *items, NSDictionary *opts, BOOL coerce) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_setItemsAndSaveCoerce(self, _cmd, items, opts, coerce);
}

static void (*orig_setItemsAndSaveCoerceOwner)(UIPasteboard *, SEL, NSArray *, NSDictionary *, BOOL, id);
static void new_setItemsAndSaveCoerceOwner(UIPasteboard *self, SEL _cmd, NSArray *items, NSDictionary *opts, BOOL coerce, id owner) {
    if (rygShouldRewrite()) items = rygRewriteItemArray(items);
    orig_setItemsAndSaveCoerceOwner(self, _cmd, items, opts, coerce, owner);
}

static void (*orig_setValueForType)(UIPasteboard *, SEL, id, NSString *);
static void new_setValueForType(UIPasteboard *self, SEL _cmd, id value, NSString *type) {
    if (rygShouldRewrite()) {
        id r = rygRewriteValue(value);
        if (r) value = r;
    }
    orig_setValueForType(self, _cmd, value, type);
}

static void (*orig_setDataForType)(UIPasteboard *, SEL, NSData *, NSString *);
static void new_setDataForType(UIPasteboard *self, SEL _cmd, NSData *data, NSString *type) {
    if (rygShouldRewrite() && [data isKindOfClass:[NSData class]] && data.length && data.length < 8192
        && ([type isEqualToString:@"public.url"] || [type isEqualToString:@"public.utf8-plain-text"] || [type isEqualToString:@"public.plain-text"] || [type isEqualToString:@"public.text"])) {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (s.length && rygLooksLikeIGURL(s)) {
            NSString *r = rygRewriteIGURL(s);
            if (![r isEqualToString:s]) {
                NSData *rd = [r dataUsingEncoding:NSUTF8StringEncoding];
                if (rd) data = rd;
            }
        }
    }
    orig_setDataForType(self, _cmd, data, type);
}


static void (*orig_setLoadedURL)(id, SEL, NSURL *);
static void new_setLoadedURL(id self, SEL _cmd, NSURL *url) {
    if (rygShouldRewrite() && [url isKindOfClass:[NSURL class]]) {
        id r = rygRewriteValue(url);
        if (r) url = r;
    }
    orig_setLoadedURL(self, _cmd, url);
}


static NSArray *rygRewriteActivityItems(NSArray *items) {
    if (!rygShouldRewrite() || !items.count) return items;
    NSMutableArray *out = nil;
    for (NSUInteger i = 0; i < items.count; i++) {
        id r = rygRewriteValue(items[i]);
        if (!r) continue;
        if (!out) out = [items mutableCopy];
        out[i] = r;
    }
    return out ?: items;
}

static id (*orig_avcInit)(id, SEL, NSArray *, NSArray *);
static id new_avcInit(id self, SEL _cmd, NSArray *items, NSArray *apps) {
    return orig_avcInit(self, _cmd, rygRewriteActivityItems(items), apps);
}


static void (*orig_gtvSetText)(id, SEL, NSString *);
static void new_gtvSetText(id self, SEL _cmd, NSString *text) {
    if (rygShouldRewrite() && [text isKindOfClass:[NSString class]] && rygLooksLikeIGURL(text)) {
        NSString *r = rygRewriteIGURL(text);
        if (![r isEqualToString:text]) text = r;
    }
    orig_gtvSetText(self, _cmd, text);
}

static void (*orig_gtvSetAttrText)(id, SEL, NSAttributedString *);
static void new_gtvSetAttrText(id self, SEL _cmd, NSAttributedString *text) {
    if (rygShouldRewrite() && [text isKindOfClass:[NSAttributedString class]]) {
        id r = rygRewriteValue(text);
        if (r) text = r;
    }
    orig_gtvSetAttrText(self, _cmd, text);
}


#define HOOK_IF(cls, sel, newFn, origPtr) do { \
    SEL _s = (sel); \
    if (class_getInstanceMethod((cls), _s)) MSHookMessageEx((cls), _s, (IMP)(newFn), (IMP *)(origPtr)); \
} while (0)

__attribute__((constructor)) static void _embedLinksInit(void) {
    Class pb = NSClassFromString(@"_UIConcretePasteboard") ?: [UIPasteboard class];
    HOOK_IF(pb, @selector(setString:), new_setString, &orig_setString);
    HOOK_IF(pb, @selector(setURL:), new_setURL, &orig_setURL);
    HOOK_IF(pb, @selector(setStrings:), new_setStrings, &orig_setStrings);
    HOOK_IF(pb, @selector(setURLs:), new_setURLs, &orig_setURLs);
    HOOK_IF(pb, @selector(setItems:), new_setItems, &orig_setItems);
    HOOK_IF(pb, @selector(setItems:options:), new_setItemsOpts, &orig_setItemsOpts);
    HOOK_IF(pb, @selector(addItems:), new_addItems, &orig_addItems);
    HOOK_IF(pb, NSSelectorFromString(@"setValue:forPasteboardType:"), new_setValueForType, &orig_setValueForType);
    HOOK_IF(pb, NSSelectorFromString(@"setData:forPasteboardType:"), new_setDataForType, &orig_setDataForType);
    HOOK_IF(pb, NSSelectorFromString(@"setObjects:"), new_setObjects, &orig_setObjects);
    HOOK_IF(pb, NSSelectorFromString(@"setObjects:options:"), new_setObjectsOpts, &orig_setObjectsOpts);
    HOOK_IF(pb, NSSelectorFromString(@"setObjects:localOnly:expirationDate:"), new_setObjectsLO, &orig_setObjectsLO);
    HOOK_IF(pb, NSSelectorFromString(@"_setItemsAndSave:options:"), new_setItemsAndSave, &orig_setItemsAndSave);
    HOOK_IF(pb, NSSelectorFromString(@"_setItemsAndSave:options:coerceStringsToURLs:"), new_setItemsAndSaveCoerce, &orig_setItemsAndSaveCoerce);
    HOOK_IF(pb, NSSelectorFromString(@"_setItemsAndSave:options:coerceStringsToURLs:dataOwner:"), new_setItemsAndSaveCoerceOwner, &orig_setItemsAndSaveCoerceOwner);

    HOOK_IF([UIActivityViewController class], @selector(initWithActivityItems:applicationActivities:), new_avcInit, &orig_avcInit);

    Class provider = NSClassFromString(@"IGActivityItemProvider");
    if (provider) HOOK_IF(provider, NSSelectorFromString(@"setLoadedURL:"), new_setLoadedURL, &orig_setLoadedURL);

    Class gtv = NSClassFromString(@"IGGrowingTextView");
    if (gtv) {
        HOOK_IF(gtv, @selector(setText:), new_gtvSetText, &orig_gtvSetText);
        HOOK_IF(gtv, @selector(setAttributedText:), new_gtvSetAttrText, &orig_gtvSetAttrText);
    }
}

#undef HOOK_IF
