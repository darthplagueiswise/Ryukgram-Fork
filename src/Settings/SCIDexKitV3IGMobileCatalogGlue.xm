#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "../Features/ExpFlags/SCIMobileConfigIdNameMappingExporter.h"
#import "../Features/ExpFlags/SCIIgMobileDeprecatedConfigCatalog.h"

static NSString *SCIIgDexString(id value) {
    return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

static NSString *SCIIgDexJoin(NSArray *values, NSUInteger limit) {
    if (![values isKindOfClass:NSArray.class] || !values.count) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger n = MIN(values.count, limit);
    for (NSUInteger i = 0; i < n; i++) {
        NSString *s = SCIIgDexString(values[i]);
        if (s.length) [parts addObject:s];
    }
    if (values.count > limit) [parts addObject:[NSString stringWithFormat:@"... +%lu", (unsigned long)(values.count - limit)]];
    return [parts componentsJoinedByString:@"\n"];
}

static NSString *SCIIgDexExportMessage(NSDictionary *result) {
    if (![result isKindOfClass:NSDictionary.class]) return @"Resultado inválido.";
    NSString *status = SCIIgDexString(result[@"status"]);
    NSArray *outputs = [result[@"outputs"] isKindOfClass:NSArray.class] ? result[@"outputs"] : @[];
    NSArray *errors = [result[@"errors"] isKindOfClass:NSArray.class] ? result[@"errors"] : @[];
    NSNumber *values = [result[@"configValuesCount"] respondsToSelector:@selector(unsignedLongLongValue)] ? result[@"configValuesCount"] : @0;
    NSNumber *overrides = [result[@"configValuesOverrideCount"] respondsToSelector:@selector(unsignedLongLongValue)] ? result[@"configValuesOverrideCount"] : @0;
    NSDictionary *catalog = [result[@"catalogImport"] isKindOfClass:NSDictionary.class] ? result[@"catalogImport"] : @{};
    NSNumber *catalogKeys = [catalog[@"count"] respondsToSelector:@selector(unsignedLongLongValue)] ? catalog[@"count"] : @0;

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"%@\n\n", status.length ? status : @"IGMobile deprecated JSON export finished"];
    [msg appendFormat:@"values: %@\noverrides: %@\noutputs: %lu\ncatalog keys: %@\n", values, overrides, (unsigned long)outputs.count, catalogKeys];

    NSString *outText = SCIIgDexJoin(outputs, 8);
    if (outText.length) [msg appendFormat:@"\noutputs:\n%@\n", outText];
    NSString *errText = SCIIgDexJoin(errors, 6);
    if (errText.length) [msg appendFormat:@"\nerrors:\n%@\n", errText];
    return msg;
}

static id SCIIgDexDescriptorForIndexPath(id self, NSIndexPath *indexPath) {
    SEL sel = NSSelectorFromString(@"desc:");
    if (![self respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, NSIndexPath *))objc_msgSend)(self, sel, indexPath);
}

static NSString *SCIIgDexValueForKey(id obj, NSString *key) {
    if (!obj || !key.length) return @"";
    @try {
        id value = [obj valueForKey:key];
        return SCIIgDexString(value);
    } @catch (__unused id ex) {
        return @"";
    }
}

static NSString *SCIIgDexOwnerGroupKey(id obj) {
    if (!obj) return @"";
    SEL sel = NSSelectorFromString(@"ownerGroupKey");
    if (![obj respondsToSelector:sel]) return @"";
    return SCIIgDexString(((id (*)(id, SEL))objc_msgSend)(obj, sel));
}

static UILabel *SCIIgDexCellLabel(UITableViewCell *cell, NSString *key) {
    @try {
        id label = [cell valueForKey:key];
        return [label isKindOfClass:UILabel.class] ? (UILabel *)label : nil;
    } @catch (__unused id ex) {
        return nil;
    }
}

%hook SCIDexKitViewController

- (void)viewDidLoad {
    %orig;

    NSMutableArray<UIBarButtonItem *> *items = [[self.navigationItem.rightBarButtonItems ?: @[] mutableCopy] ?: [NSMutableArray array] mutableCopy];
    BOOL found = NO;
    for (UIBarButtonItem *item in items) {
        if ([item.title isEqualToString:@"ID Map"] || [item.title isEqualToString:@"Tools"] || [item.title isEqualToString:@"IGMobile JSON"]) {
            item.title = @"IGMobile JSON";
            item.target = self;
            item.action = @selector(exportIGMobileDeprecatedJSON);
            found = YES;
        }
    }
    if (!found) {
        UIBarButtonItem *json = [[UIBarButtonItem alloc] initWithTitle:@"IGMobile JSON" style:UIBarButtonItemStylePlain target:self action:@selector(exportIGMobileDeprecatedJSON)];
        [items insertObject:json atIndex:0];
    }
    self.navigationItem.rightBarButtonItems = items;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SCIIgMobileDeprecatedConfigCatalogDidUpdateNotification object:nil];
}

- (void)exportIGMobileDeprecatedJSON {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"IGMobile JSON"
                                                                  message:@"Exportando FBMobileConfigStartupConfigsDeprecated e importando catálogo interno..."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:wait animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *result = [SCIMobileConfigIdNameMappingExporter exportIGMobileDeprecatedJSONNow];
            NSString *message = SCIIgDexExportMessage(result);
            dispatch_async(dispatch_get_main_queue(), ^{
                [wait dismissViewControllerAnimated:YES completion:^{
                    BOOL ok = [result[@"ok"] boolValue];
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(ok ? @"IGMobile JSON exportado" : @"IGMobile JSON não exportado")
                                                                                   message:message
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
                    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar relatório" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                        UIPasteboard.generalPasteboard.string = message;
                    }]];
                    NSArray *outputs = [result[@"outputs"] isKindOfClass:NSArray.class] ? result[@"outputs"] : @[];
                    NSString *paths = SCIIgDexJoin(outputs, 99);
                    if (paths.length) {
                        [alert addAction:[UIAlertAction actionWithTitle:@"Copiar output paths" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                            UIPasteboard.generalPasteboard.string = paths;
                        }]];
                    }
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                    if (alert.popoverPresentationController) alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
                    [self presentViewController:alert animated:YES completion:nil];
                    if ([self respondsToSelector:@selector(reload)]) [self performSelector:@selector(reload)];
                }];
            });
        });
    }];
}

- (void)exportIDNameMapping {
    [self exportIGMobileDeprecatedJSON];
}

- (void)reload {
    %orig;
    UILabel *footer = nil;
    @try { footer = [self valueForKey:@"footer"]; } @catch (__unused id ex) {}
    if (![footer isKindOfClass:UILabel.class]) return;

    NSString *summary = [SCIIgMobileDeprecatedConfigCatalog summaryLine] ?: @"igmobile deprecated catalog not imported";
    NSString *old = footer.text ?: @"";
    NSRange marker = [old rangeOfString:@"\nIGMobile catalog: "];
    if (marker.location != NSNotFound) old = [old substringToIndex:marker.location];
    footer.text = [old stringByAppendingFormat:@"\nIGMobile catalog: %@", summary];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig;
    id d = SCIIgDexDescriptorForIndexPath(self, indexPath);
    if (!d) return cell;

    NSString *className = SCIIgDexValueForKey(d, @"className");
    NSString *selectorName = SCIIgDexValueForKey(d, @"selectorName");
    NSString *familyKey = SCIIgDexValueForKey(d, @"familyKey");
    NSString *semanticCategory = SCIIgDexValueForKey(d, @"semanticCategory");
    NSString *ownerGroup = SCIIgDexOwnerGroupKey(d);

    SCIIgMobileDeprecatedConfigMatch *match = [SCIIgMobileDeprecatedConfigCatalog bestMatchForClassName:className
                                                                                           selectorName:selectorName
                                                                                             ownerGroup:ownerGroup
                                                                                              familyKey:familyKey
                                                                                       semanticCategory:semanticCategory];
    if (!match.name.length) return cell;

    UILabel *title = SCIIgDexCellLabel(cell, @"title");
    UILabel *detail = SCIIgDexCellLabel(cell, @"detail");
    if (title) {
        title.numberOfLines = MAX(title.numberOfLines, 2);
        title.text = [NSString stringWithFormat:@"%@\n%@", match.name, selectorName.length ? selectorName : (title.text ?: @"")];
    }
    if (detail) {
        NSString *old = detail.text ?: @"";
        if (![old containsString:@"igmobile-deprecated catalog"]) detail.text = [old stringByAppendingFormat:@" · %@", match.evidence ?: @""];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    id d = SCIIgDexDescriptorForIndexPath(self, indexPath);
    NSString *className = SCIIgDexValueForKey(d, @"className");
    NSString *selectorName = SCIIgDexValueForKey(d, @"selectorName");
    NSString *familyKey = SCIIgDexValueForKey(d, @"familyKey");
    NSString *semanticCategory = SCIIgDexValueForKey(d, @"semanticCategory");
    NSString *ownerGroup = SCIIgDexOwnerGroupKey(d);
    NSArray<SCIIgMobileDeprecatedConfigMatch *> *matches = [SCIIgMobileDeprecatedConfigCatalog matchesForClassName:className selectorName:selectorName ownerGroup:ownerGroup familyKey:familyKey semanticCategory:semanticCategory limit:5];

    if (matches.count) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (SCIIgMobileDeprecatedConfigMatch *m in matches) [lines addObject:[NSString stringWithFormat:@"%@ — %@", m.name ?: @"", m.evidence ?: @""]];
        UIPasteboard.generalPasteboard.string = [lines componentsJoinedByString:@"\n"];
    }
    %orig;
}

%end
