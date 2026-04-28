#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "../Features/ExpFlags/SCIExpFlags.h"
#import "../Features/ExpFlags/SCIMobileConfigMapping.h"

@interface SCIExpFlagsViewController : UIViewController
- (NSArray *)filteredRows;
- (void)refresh;
@end

@implementation SCIExpFlagsViewController (MCMappedUI)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = self;
        Method a = class_getInstanceMethod(cls, @selector(tableView:cellForRowAtIndexPath:));
        Method b = class_getInstanceMethod(cls, @selector(sci_mc_tableView:cellForRowAtIndexPath:));
        if (a && b) method_exchangeImplementations(a, b);
        Method c = class_getInstanceMethod(cls, @selector(tableView:didSelectRowAtIndexPath:));
        Method d = class_getInstanceMethod(cls, @selector(sci_mc_tableView:didSelectRowAtIndexPath:));
        if (c && d) method_exchangeImplementations(c, d);
    });
}

- (id)sci_mc_rowAtIndexPath:(NSIndexPath *)ip {
    if (![self respondsToSelector:@selector(filteredRows)]) return nil;
    NSArray *rows = ((NSArray *(*)(id, SEL))objc_msgSend)(self, @selector(filteredRows));
    return ip.row < rows.count ? rows[ip.row] : nil;
}

- (NSString *)sci_mc_typeName:(SCIExpMCType)t {
    switch (t) {
        case SCIExpMCTypeBool: return @"bool";
        case SCIExpMCTypeInt: return @"int64";
        case SCIExpMCTypeDouble: return @"double";
        case SCIExpMCTypeString: return @"string";
    }
}

- (UITableViewCell *)sci_mc_tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [self sci_mc_tableView:tv cellForRowAtIndexPath:ip];
    id row = [self sci_mc_rowAtIndexPath:ip];
    if (![row isKindOfClass:[SCIExpMCObservation class]]) return cell;

    SCIExpMCObservation *o = row;
    NSString *name = o.resolvedName.length ? o.resolvedName : ([SCIMobileConfigMapping resolvedNameForParamID:o.paramID] ?: @"?");
    NSString *src = o.source.length ? o.source : ([SCIMobileConfigMapping sourceForParamID:o.paramID] ?: @"unmapped");
    NSString *type = [self sci_mc_typeName:o.type];
    id forced = [SCIMobileConfigMapping overrideObjectForParamID:o.paramID typeName:type];

    cell.textLabel.text = [NSString stringWithFormat:@"%@  %llu", name, o.paramID];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:type];
    if (o.contextClass.length) [parts addObject:o.contextClass];
    if (o.selectorName.length) [parts addObject:o.selectorName];
    if (o.lastOriginalValue.length) [parts addObject:[@"orig=" stringByAppendingString:o.lastOriginalValue]];
    else if (o.lastDefault.length) [parts addObject:[@"value=" stringByAppendingString:o.lastDefault]];
    [parts addObject:[NSString stringWithFormat:@"×%lu", (unsigned long)o.hitCount]];
    [parts addObject:src];
    if (forced) [parts addObject:[@"OVERRIDE=" stringByAppendingString:[forced description]]];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)sci_mc_tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    id row = [self sci_mc_rowAtIndexPath:ip];
    if (![row isKindOfClass:[SCIExpMCObservation class]]) {
        [self sci_mc_tableView:tv didSelectRowAtIndexPath:ip];
        return;
    }
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCIExpMCObservation *o = row;
    NSString *name = o.resolvedName.length ? o.resolvedName : ([SCIMobileConfigMapping resolvedNameForParamID:o.paramID] ?: @"?");
    NSString *type = [self sci_mc_typeName:o.type];
    NSString *title = [NSString stringWithFormat:@"%@\n%llu", name, o.paramID];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:[SCIMobileConfigMapping mappingStatusLine] preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy ID" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%llu", o.paramID];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIPasteboard.generalPasteboard.string = name;
    }]];
    if (o.type == SCIExpMCTypeBool) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force TRUE" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [SCIMobileConfigMapping setOverrideObject:@YES forParamID:o.paramID typeName:type name:name];
            [self refresh];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force FALSE" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [SCIMobileConfigMapping setOverrideObject:@NO forParamID:o.paramID typeName:type name:name];
            [self refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove override" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [SCIMobileConfigMapping removeOverrideForParamID:o.paramID];
        [self refresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = cell ?: self.view;
        sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
