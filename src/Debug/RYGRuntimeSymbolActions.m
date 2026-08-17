#import "RYGDeveloperRuntimeBrowserViewController.h"
#import "RYGRuntimeBrowserEngine.h"
#import "../Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

typedef NS_ENUM(NSInteger, RYGCompatRuntimeMode) {
    RYGCompatRuntimeModeBool = 0,
    RYGCompatRuntimeModeSymbols = 1,
};

static const char *RYGSymbolSkipQualifiers(const char *type) {
    while (type && strchr("rnNoORV", *type)) type++;
    return type;
}

static RYGRuntimeArgumentKind RYGSymbolArgumentKind(Method method) {
    if (!method) return -1;
    unsigned int count = method_getNumberOfArguments(method);
    if (count == 2) return RYGRuntimeArgumentNone;
    if (count != 3) return -1;
    char encoded[32] = {0};
    method_getArgumentType(method, 2, encoded, sizeof(encoded));
    const char *arg = RYGSymbolSkipQualifiers(encoded);
    if (!arg || !*arg) return -1;
    if (*arg == '@' || *arg == '#' || *arg == ':') return RYGRuntimeArgumentObject;
    if (strchr("BcCsSiIlLqQ^*", *arg)) return RYGRuntimeArgumentInteger;
    return -1;
}

static BOOL RYGSymbolSupportedBool(Method method) {
    if (!method) return NO;
    char encoded[16] = {0};
    method_getReturnType(method, encoded, sizeof(encoded));
    const char *ret = RYGSymbolSkipQualifiers(encoded);
    return ret && (*ret == 'B' || *ret == 'c' || *ret == 'C') && RYGSymbolArgumentKind(method) >= 0;
}

static BOOL RYGParseObjCMethodSymbol(NSString *raw, NSString **className, NSString **selectorName, BOOL *classMethod) {
    NSString *name = raw ?: @"";
    if ([name hasPrefix:@"_"]) name = [name substringFromIndex:1];
    if (name.length < 5) return NO;

    unichar sign = [name characterAtIndex:0];
    if (sign != '+' && sign != '-') return NO;
    unichar opener = [name characterAtIndex:1];
    unichar closer = opener == '<' ? '>' : (opener == '[' ? ']' : 0);
    if (!closer) return NO;
    NSRange close = [name rangeOfString:[NSString stringWithFormat:@"%C", closer] options:NSBackwardsSearch];
    if (close.location == NSNotFound || close.location <= 2) return NO;

    NSString *body = [name substringWithRange:NSMakeRange(2, close.location - 2)];
    NSRange space = [body rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
    if (space.location == NSNotFound || space.location == 0 || NSMaxRange(space) >= body.length) return NO;
    NSString *cls = [body substringToIndex:space.location];
    NSString *sel = [[body substringFromIndex:NSMaxRange(space)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!cls.length || !sel.length) return NO;
    if (className) *className = cls;
    if (selectorName) *selectorName = sel;
    if (classMethod) *classMethod = sign == '+';
    return YES;
}

static Method RYGDeclaredMethod(Class owner, SEL selector) {
    for (Class cursor = owner; cursor; cursor = class_getSuperclass(cursor)) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cursor, &count);
        Method found = NULL;
        for (unsigned int index = 0; index < count; index++) {
            if (method_getName(methods[index]) == selector) { found = methods[index]; break; }
        }
        if (methods) free(methods);
        if (found) return found;
    }
    return NULL;
}

static RYGRuntimeBoolMethod *RYGBoolMethodFromSymbol(RYGMachOSymbol *symbol, NSString *imagePath) {
    if (!symbol || ![symbol.kind isEqualToString:@"Function"]) return nil;
    NSString *className = nil;
    NSString *selectorName = nil;
    BOOL classMethod = NO;
    if (!RYGParseObjCMethodSymbol(symbol.name, &className, &selectorName, &classMethod)) return nil;
    if ([RYGRuntimeBrowserEngine isStructuralNoiseSelectorName:selectorName]) return nil;

    Class cls = objc_lookUpClass(className.UTF8String);
    SEL selector = sel_registerName(selectorName.UTF8String);
    Class owner = classMethod ? object_getClass(cls) : cls;
    Method method = owner ? RYGDeclaredMethod(owner, selector) : NULL;
    if (!cls || !owner || !method || !RYGSymbolSupportedBool(method)) return nil;

    RYGRuntimeBoolMethod *row = [RYGRuntimeBoolMethod new];
    row.imagePath = imagePath ?: @"";
    row.className = className;
    row.selectorName = selectorName;
    row.classMethod = classMethod;
    row.argumentKind = RYGSymbolArgumentKind(method);
    row.typeEncoding = [NSString stringWithUTF8String:method_getTypeEncoding(method) ?: ""];
    return row;
}

static NSString *RYGRelatedBoolQuery(NSString *symbolName) {
    NSString *lower = symbolName.lowercaseString ?: @"";
    NSArray<NSArray<NSString *> *> *pairs = @[
        @[@"employee", @"employee"], @[@"internal", @"internal"], @[@"dogfood", @"dogfood"],
        @[@"prism", @"prism"], @[@"liquidglass", @"glass"], @[@"glass", @"glass"],
        @[@"wordmark", @"wordmark"], @[@"experiment", @"experiment"], @[@"feature", @"feature"],
        @[@"debug", @"debug"], @[@"launcher", @"launcher"],
    ];
    for (NSArray *pair in pairs) if ([lower containsString:pair[0]]) return pair[1];
    return @"";
}

@implementation RYGDeveloperRuntimeBrowserViewController (RYGRuntimeSymbolActions)

- (void)ryg_symbolActions_tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UISegmentedControl *mode = nil;
    NSArray *visibleRows = nil;
    NSString *imagePath = nil;
    @try {
        mode = [self valueForKey:@"modeControl"];
        visibleRows = [self valueForKey:@"visibleRows"];
        imagePath = [self valueForKey:@"selectedImagePath"];
    } @catch (__unused id exception) {}

    if (!mode || mode.selectedSegmentIndex != RYGCompatRuntimeModeSymbols) {
        [self ryg_symbolActions_tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)visibleRows.count) return;
    RYGMachOSymbol *symbol = [visibleRows[indexPath.row] isKindOfClass:RYGMachOSymbol.class] ? visibleRows[indexPath.row] : nil;
    if (!symbol) return;

    RYGRuntimeBoolMethod *method = RYGBoolMethodFromSymbol(symbol, imagePath);
    if (method) {
        NSString *message = [NSString stringWithFormat:@"%@\n%@\nABI %@\nThis Mach-O function resolves to a supported Objective-C BOOL method.",
                             method.className, method.selectorName, method.typeEncoding];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Overrideable BOOL symbol"
                                                                        message:message
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force true" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:@YES forMethod:method];
            [RYGUtils showToastForDuration:1.3 title:@"Runtime override" subtitle:@"Forced true"];
            ((void (*)(id, SEL))objc_msgSend)(weakSelf, NSSelectorFromString(@"applySearchFilter"));
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force false" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [RYGRuntimeBrowserEngine setOverride:@NO forMethod:method];
            [RYGUtils showToastForDuration:1.3 title:@"Runtime override" subtitle:@"Forced false"];
            ((void (*)(id, SEL))objc_msgSend)(weakSelf, NSSelectorFromString(@"applySearchFilter"));
        }]];
        if (method.overrideValue) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"Use native value" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
                [RYGRuntimeBrowserEngine setOverride:nil forMethod:method];
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = symbol.name;
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:sheet animated:YES completion:nil];
        return;
    }

    NSString *address = symbol.address ? [NSString stringWithFormat:@"0x%llx", symbol.address] : @"unresolved";
    NSString *reason = [symbol.kind isEqualToString:@"Data"]
        ? @"This is a DATA symbol, not a callable BOOL getter. Writing true/false into it would corrupt unrelated storage."
        : @"Mach-O nlist does not encode a callable function signature. An arbitrary force is disabled until a supported ABI can be resolved.";
    NSString *message = [NSString stringWithFormat:@"%@ · %@\n%@\n\n%@", symbol.kind, symbol.external ? @"external" : @"local", address, reason];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:symbol.name message:message preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *query = RYGRelatedBoolQuery(symbol.name);
    if (query.length) {
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Search overrideable BOOL gates: %@", query]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UISegmentedControl *strongMode = nil;
            UISearchController *search = nil;
            @try {
                strongMode = [weakSelf valueForKey:@"modeControl"];
                search = [weakSelf valueForKey:@"searchController"];
            } @catch (__unused id exception) {}
            strongMode.selectedSegmentIndex = RYGCompatRuntimeModeBool;
            search.searchBar.text = query;
            [strongMode sendActionsForControlEvents:UIControlEventValueChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy symbol" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = symbol.name;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy live address" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = address;
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

__attribute__((constructor(130))) static void RYGInstallRuntimeSymbolActions(void) {
    Class cls = RYGDeveloperRuntimeBrowserViewController.class;
    SEL originalSelector = @selector(tableView:didSelectRowAtIndexPath:);
    SEL replacementSelector = @selector(ryg_symbolActions_tableView:didSelectRowAtIndexPath:);
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original && replacement) method_exchangeImplementations(original, replacement);
}
