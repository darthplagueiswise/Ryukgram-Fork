#import "StoryMenuItems.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation SCIStoryMenuEntry
+ (instancetype)entryWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler {
    SCIStoryMenuEntry *e = [self new];
    e.title = title;
    e.symbol = symbol;
    e.handler = handler;
    return e;
}
@end

NSArray<SCIStoryMenuEntry *> *sciStoryMenuEntries(void) {
    NSMutableArray<SCIStoryMenuEntry *> *entries = [NSMutableArray array];
    SCIStoryMenuEntry *e;
    if ((e = sciStoryExcludeMenuEntry())) [entries addObject:e];
    if ((e = sciStoryAudioMenuEntry())) [entries addObject:e];
    if ((e = sciStoryMentionsMenuEntry())) [entries addObject:e];
    return entries;
}

// ---- old IGDSMenu (3-dot dropdown) glue ----
// IGDSMenu is generic; only inject when the items look like the story 3-dot menu.
BOOL sciItemsLookLikeStoryMenu(NSArray *items) {
    for (id item in items) {
        @try {
            id image = [item valueForKey:@"image"];
            NSString *imageName = [image respondsToSelector:@selector(name)] ? [image performSelector:@selector(name)] : nil;
            NSString *title = [NSString stringWithFormat:@"%@", [item valueForKey:@"title"] ?: @""];
            if ([imageName isEqualToString:@"report_pano_outline_24"] ||
                [imageName isEqualToString:@"mute_24"] ||
                [imageName isEqualToString:@"hide_pano_outline_24"] ||
                [imageName isEqualToString:@"following_24"] ||
                [imageName isEqualToString:@"plus_pano_outline_24"] ||
                [title isEqualToString:@"Report"] || [title isEqualToString:@"Mute"] ||
                [title isEqualToString:@"Unfollow"] || [title isEqualToString:@"Follow"] ||
                [title isEqualToString:@"Hide"]) return YES;
        } @catch (__unused id e) {}
    }
    return NO;
}

NSArray *sciAppendStoryEntriesToIGDSMenu(NSArray *items) {
    if (!sciItemsLookLikeStoryMenu(items)) return items;
    Class menuItemCls = NSClassFromString(@"IGDSMenuItem");
    if (!menuItemCls) return items;
    NSMutableArray *out = items.mutableCopy ?: [NSMutableArray array];
    for (SCIStoryMenuEntry *entry in sciStoryMenuEntries()) {
        void (^handler)(void) = entry.handler;
        id item = nil;
        @try {
            item = ((id (*)(id, SEL, id, id, id))objc_msgSend)(
                [menuItemCls alloc], @selector(initWithTitle:image:handler:), entry.title, nil, handler);
        } @catch (__unused id e) {}
        if (item) [out addObject:item];
    }
    return out.copy;
}
