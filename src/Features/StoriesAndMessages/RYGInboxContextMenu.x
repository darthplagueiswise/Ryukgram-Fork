// Central DM inbox row menu hook — only one hook owns the selector, so
// every contributor funnels here. Contributors gate themselves.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "RYGExcludeChatMenu.h"
#import "../../Lock/RYGLockChatMenu.h"
#import "../HiddenChats/RYGHiddenChatsMenu.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static id ryg_ictx_safeKey(id obj, NSString *k) {
    @try { return [obj valueForKey:k]; } @catch (__unused id e) { return nil; }
}

static NSDictionary *ryg_ictx_entryFromVM(id vm) {
    if (!vm) return nil;
    NSString *tid  = ryg_ictx_safeKey(vm, @"threadId");
    NSString *name = ryg_ictx_safeKey(vm, @"threadName");
    NSNumber *grp  = ryg_ictx_safeKey(vm, @"isGroupThread");
    if (tid.length == 0) return nil;

    NSMutableArray *users = [NSMutableArray array];
    id active = ryg_ictx_safeKey(vm, @"recentlyActiveUsers");
    if ([active isKindOfClass:[NSArray class]]) {
        for (id u in (NSArray *)active) {
            id pk = ryg_ictx_safeKey(u, @"pk");
            id un = ryg_ictx_safeKey(u, @"username");
            id fn = ryg_ictx_safeKey(u, @"fullName");
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            if (pk) d[@"pk"]       = [NSString stringWithFormat:@"%@", pk];
            if (un) d[@"username"] = [NSString stringWithFormat:@"%@", un];
            if (fn) d[@"fullName"] = [NSString stringWithFormat:@"%@", fn];
            if (d.count) [users addObject:d];
        }
    }
    return @{
        @"threadId":   tid,
        @"threadName": name ?: @"",
        @"isGroup":    @([grp boolValue]),
        @"users":      users,
    };
}

static id (*orig_ctxMenuCfg)(id, SEL, id);
static id new_ctxMenuCfg(id self, SEL _cmd, id indexPath) {
    id cfg = orig_ctxMenuCfg(self, _cmd, indexPath);
    if (![cfg isKindOfClass:[UIContextMenuConfiguration class]]) return cfg;

    id adapter = ryg_ictx_safeKey(self, @"listAdapter");
    if (!adapter || ![indexPath respondsToSelector:@selector(section)]) return cfg;
    NSInteger section = [(NSIndexPath *)indexPath section];
    SEL secSel = NSSelectorFromString(@"sectionControllerForSection:");
    if (![adapter respondsToSelector:secSel]) return cfg;
    id secCtrl = ((id(*)(id,SEL,NSInteger))objc_msgSend)(adapter, secSel, section);
    id vm = ryg_ictx_safeKey(secCtrl, @"viewModel");
    if (!vm) vm = ryg_ictx_safeKey(secCtrl, @"item");
    NSDictionary *entry = ryg_ictx_entryFromVM(vm);
    if (!entry) return cfg;

    UIContextMenuConfiguration *orig = (UIContextMenuConfiguration *)cfg;
    UIContextMenuActionProvider origProvider = ryg_ictx_safeKey(orig, @"actionProvider");
    id<NSCopying> origIdent = ryg_ictx_safeKey(orig, @"identifier");
    UIContextMenuContentPreviewProvider origPreview = ryg_ictx_safeKey(orig, @"previewProvider");

    UIContextMenuActionProvider wrapped = ^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        UIMenu *base = origProvider ? origProvider(suggested) : [UIMenu menuWithChildren:suggested];
        NSMutableArray *kids = [base.children mutableCopy] ?: [NSMutableArray array];

        UIAction *exclude = [RYGExcludeChatMenu actionForEntry:entry];
        if (exclude) [kids addObject:exclude];
        for (UIAction *a in [RYGLockChatMenu actionsForEntry:entry])    [kids addObject:a];
        for (UIAction *a in [RYGHiddenChatsMenu actionsForEntry:entry]) [kids addObject:a];

        return [base menuByReplacingChildren:kids];
    };

    return [UIContextMenuConfiguration configurationWithIdentifier:origIdent
                                                   previewProvider:origPreview
                                                    actionProvider:wrapped];
}

%ctor {
    Class cls = NSClassFromString(@"IGDirectInboxViewController");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"networkingCoordinator_contextMenuConfigurationForThreadCellAtIndexPath:");
    if (class_getInstanceMethod(cls, sel))
        MSHookMessageEx(cls, sel, (IMP)new_ctxMenuCfg, (IMP *)&orig_ctxMenuCfg);
}
