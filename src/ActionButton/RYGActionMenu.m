#import "RYGActionMenu.h"
#import "../UI/RYGIcon.h"
#import "RYGActionMenuConfig.h"
#import "RYGActionCatalog.h"

#pragma mark - RYGAction

@interface RYGAction ()
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite, nullable) NSString *subtitle;
@property (nonatomic, copy, readwrite, nullable) NSString *systemIconName;
@property (nonatomic, copy, readwrite, nullable) void (^handler)(void);
@property (nonatomic, copy, readwrite, nullable) NSArray<RYGAction *> *children;
@property (nonatomic, assign, readwrite) BOOL destructive;
@property (nonatomic, assign, readwrite) BOOL isSeparator;
@property (nonatomic, assign, readwrite) BOOL disabled;
@end

@implementation RYGAction

+ (instancetype)actionWithTitle:(NSString *)title
                           icon:(NSString *)icon
                        handler:(void(^)(void))handler {
    return [self actionWithTitle:title subtitle:nil icon:icon destructive:NO handler:handler];
}

+ (instancetype)actionWithTitle:(NSString *)title
                       subtitle:(NSString *)subtitle
                           icon:(NSString *)icon
                    destructive:(BOOL)destructive
                        handler:(void(^)(void))handler {
    RYGAction *a = [RYGAction new];
    a.title = title ?: @"";
    a.subtitle = subtitle;
    a.systemIconName = icon;
    a.handler = handler;
    a.destructive = destructive;
    return a;
}

+ (instancetype)actionWithTitle:(NSString *)title
                           icon:(NSString *)icon
                       children:(NSArray<RYGAction *> *)children {
    RYGAction *a = [RYGAction new];
    a.title = title ?: @"";
    a.systemIconName = icon;
    a.children = [children copy];
    return a;
}

+ (instancetype)separator {
    RYGAction *a = [RYGAction new];
    a.isSeparator = YES;
    return a;
}

+ (instancetype)headerWithTitle:(NSString *)title {
    RYGAction *a = [RYGAction new];
    a.title = title ?: @"";
    a.disabled = YES;
    return a;
}

+ (instancetype)infoRowWithTitle:(NSString *)title icon:(NSString *)icon {
    RYGAction *a = [RYGAction new];
    a.title = title ?: @"";
    a.systemIconName = icon;
    a.disabled = YES;
    return a;
}

@end


#pragma mark - RYGActionMenu

@implementation RYGActionMenu

+ (UIImage *)imageForIcon:(NSString *)name {
    return [RYGIcon menuImageNamed:name pointSize:18];
}

+ (UIMenuElement *)elementForAction:(RYGAction *)action {
    if (action.children.count) {
        NSMutableArray<UIMenuElement *> *kids = [NSMutableArray arrayWithCapacity:action.children.count];
        for (RYGAction *child in action.children) {
            UIMenuElement *el = [self elementForAction:child];
            if (el) [kids addObject:el];
        }
        return [UIMenu menuWithTitle:action.title
                               image:[self imageForIcon:action.systemIconName]
                          identifier:nil
                             options:0
                            children:kids];
    }

    UIAction *ua = [UIAction actionWithTitle:action.title
                                       image:[self imageForIcon:action.systemIconName]
                                  identifier:nil
                                     handler:^(__kindof UIAction * _Nonnull a) {
        if (action.handler) action.handler();
    }];

    if (@available(iOS 15.0, *)) {
        if (action.subtitle.length) ua.subtitle = action.subtitle;
    }
    if (action.destructive) ua.attributes = UIMenuElementAttributesDestructive;
    if (action.disabled) {
        if (@available(iOS 15.0, *)) {
            ua.attributes |= UIMenuElementAttributesDisabled;
        } else {
            ua.attributes = UIMenuElementAttributesDisabled;
        }
    }
    return ua;
}

+ (UIMenu *)buildMenuWithActions:(NSArray<RYGAction *> *)actions {
    return [self buildMenuWithActions:actions title:nil];
}

+ (NSArray<RYGAction *> *)actionsForConfig:(RYGActionMenuConfig *)config
                                  dateHeader:(NSString *)dateHeader
                                    resolver:(RYGAction * _Nullable (^)(NSString *))resolver {
    return [self actionsForConfig:config dateHeader:dateHeader resolver:resolver includeDisabled:NO];
}

+ (NSArray<RYGAction *> *)actionsForConfig:(RYGActionMenuConfig *)config
                                  dateHeader:(NSString *)dateHeader
                                    resolver:(RYGAction * _Nullable (^)(NSString *))resolver
                             includeDisabled:(BOOL)includeDisabled {
    NSMutableArray<RYGAction *> *out = [NSMutableArray array];
    if (!config || !resolver) return out;

    if (dateHeader.length) {
        [out addObject:[RYGAction headerWithTitle:dateHeader]];
    }

    BOOL anyEmitted = (out.count > 0);
    for (RYGActionConfigSection *section in config.sections) {
        // Resolve first, emit separator after — empty sections shouldn't leave a stray divider.
        NSMutableArray<RYGAction *> *resolved = [NSMutableArray arrayWithCapacity:section.actionIDs.count];
        for (NSString *aid in section.actionIDs) {
            if (!includeDisabled && [config isActionDisabled:aid]) continue;
            RYGAction *action = resolver(aid);
            if (action) {
                if (!action.actionID.length) action.actionID = aid;
                [resolved addObject:action];
            }
        }
        if (resolved.count == 0) continue;

        if (section.collapsible) {
            if (anyEmitted) [out addObject:[RYGAction separator]];
            NSString *icon = section.iconSF.length ? section.iconSF : @"folder";
            NSString *title = section.title.length ? section.title : @"";
            [out addObject:[RYGAction actionWithTitle:title icon:icon children:resolved]];
            anyEmitted = YES;
        } else {
            if (anyEmitted) [out addObject:[RYGAction separator]];
            [out addObjectsFromArray:resolved];
            anyEmitted = YES;
        }
    }

    return out;
}

+ (UIMenu *)buildMenuWithActions:(NSArray<RYGAction *> *)actions title:(NSString *)title {
    // First action is a header marker (disabled, no handler, not a separator) —
    // hoist its title onto the first inline group so it shows as a grey caption.
    NSString *headerTitle = nil;
    NSArray<RYGAction *> *items = actions;
    if (actions.count > 0) {
        RYGAction *first = actions.firstObject;
        if (first.disabled && !first.handler && !first.isSeparator) {
            headerTitle = first.title;
            NSUInteger start = 1;
            if (start < actions.count && actions[start].isSeparator) start++;
            items = [actions subarrayWithRange:NSMakeRange(start, actions.count - start)];
        }
    }

    NSMutableArray<UIMenuElement *> *top = [NSMutableArray array];
    NSMutableArray<UIMenuElement *> *currentGroup = [NSMutableArray array];
    __block BOOL isFirstFlush = YES;

    void (^flush)(void) = ^{
        if (currentGroup.count == 0) return;
        NSString *t = (isFirstFlush && headerTitle.length) ? headerTitle : @"";
        UIMenu *group = [UIMenu menuWithTitle:t
                                        image:nil
                                   identifier:nil
                                      options:UIMenuOptionsDisplayInline
                                     children:[currentGroup copy]];
        [top addObject:group];
        [currentGroup removeAllObjects];
        isFirstFlush = NO;
    };

    for (RYGAction *a in items) {
        if (a.isSeparator) {
            flush();
            continue;
        }
        UIMenuElement *el = [self elementForAction:a];
        if (el) [currentGroup addObject:el];
    }
    flush();

    return [UIMenu menuWithTitle:title ?: @""
                           image:nil
                      identifier:nil
                         options:0
                        children:[top copy]];
}

@end
