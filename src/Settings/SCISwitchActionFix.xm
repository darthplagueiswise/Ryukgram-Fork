#import "SCISetting.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static UITableViewCell *SCICellForView(UIView *view) {
    UIView *cur = view;
    while (cur && ![cur isKindOfClass:UITableViewCell.class]) cur = cur.superview;
    return (UITableViewCell *)cur;
}

static UITableView *SCITableForView(UIView *view) {
    UIView *cur = view;
    while (cur && ![cur isKindOfClass:UITableView.class]) cur = cur.superview;
    return (UITableView *)cur;
}

%hook SCISettingsViewController
- (void)switchChanged:(UISwitch *)sender {
    %orig;

    UITableViewCell *cell = SCICellForView(sender);
    UITableView *table = SCITableForView(sender);
    if (!cell || !table) return;

    NSIndexPath *indexPath = [table indexPathForCell:cell];
    if (!indexPath) return;

    SEL sel = NSSelectorFromString(@"settingForIndexPath:breadcrumbOut:");
    if (![self respondsToSelector:sel]) return;

    SCISetting *(*msg)(id, SEL, NSIndexPath *, NSString **) = (SCISetting *(*)(id, SEL, NSIndexPath *, NSString **))objc_msgSend;
    SCISetting *row = msg(self, sel, indexPath, NULL);
    if (![row isKindOfClass:SCISetting.class] || !row.action) return;

    row.action();
}
%end
