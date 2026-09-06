#import "RYGRuntimeValueEditor.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#include <stdlib.h>

static BOOL RYGEditorPersistAndInstall(NSString *className, NSString *selectorName, BOOL meta,
                                       NSString *typeCode, id value, dispatch_block_t completion) {
    RYGRuntimeValueSetOverride(className, selectorName, meta, typeCode, value);
    BOOL installed = RYGRuntimeValueHasOverride(className, selectorName, meta) &&
                     RYGRuntimeValueInstallHook(className, selectorName, meta, typeCode);
    if (completion) completion();
    return installed;
}

static void RYGEditorApply(NSString *className, NSString *selectorName, BOOL meta,
                           NSString *typeCode, id value, dispatch_block_t completion) {
    (void)RYGEditorPersistAndInstall(className, selectorName, meta, typeCode, value, completion);
}

static void RYGEditorError(UIViewController *presenter, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Runtime Editor"
                                                                   message:message ?: @"Could not convert the value."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

static NSNumber *RYGDecimalNumber(NSString *text, NSString **errorText) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:trimmed
                                                                 locale:@{ NSLocaleDecimalSeparator: @"." }];
    if (!trimmed.length || [number isEqualToNumber:NSDecimalNumber.notANumber]) {
        if (errorText) *errorText = @"Invalid number.";
        return nil;
    }
    return number;
}

static id RYGParseJSON(NSString *text, NSString **errorText) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    id object = data ? [NSJSONSerialization JSONObjectWithData:data
                                                       options:NSJSONReadingFragmentsAllowed
                                                         error:&error] : nil;
    if (!object || error) {
        if (errorText) *errorText = error.localizedDescription ?: @"Invalid JSON.";
        return nil;
    }
    return object;
}

static NSString *RYGPrettyJSON(id object) {
    if (!object || object == NSNull.null || ![NSJSONSerialization isValidJSONObject:object]) return nil;
    NSJSONWritingOptions options = NSJSONWritingPrettyPrinted;
    if (@available(iOS 11.0, *)) options |= NSJSONWritingSortedKeys;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:options error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

static BOOL RYGLooksLikeJSON(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed hasPrefix:@"{"] || [trimmed hasPrefix:@"["];
}

// Port of dogfood2 WAGRRuntimeCanonicalJSONStringUI: remove only insignificant
// JSON whitespace outside quoted strings. This preserves key order, escapes and
// numeric lexical forms instead of parse/re-serialize changing the wire string.
static NSString *RYGCompactJSONLexically(NSString *text) {
    if (![text isKindOfClass:NSString.class] || !text.length) return text ?: @"";
    NSMutableString *output = [NSMutableString stringWithCapacity:text.length];
    BOOL inString = NO;
    BOOL escaped = NO;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar ch = [text characterAtIndex:index];
        if (inString) {
            [output appendFormat:@"%C", ch];
            if (escaped) escaped = NO;
            else if (ch == '\\') escaped = YES;
            else if (ch == '"') inString = NO;
            continue;
        }
        if (ch == '"') {
            inString = YES;
            escaped = NO;
            [output appendFormat:@"%C", ch];
            continue;
        }
        if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') continue;
        [output appendFormat:@"%C", ch];
    }
    return output;
}

static NSString *RYGObjectText(id value) {
    if (!value || value == NSNull.null) return @"";
    if ([value isKindOfClass:NSString.class]) {
        NSString *string = value;
        if (RYGLooksLikeJSON(string)) {
            id parsed = RYGParseJSON(string, nil);
            NSString *pretty = RYGPrettyJSON(parsed);
            if (pretty.length) return pretty;
        }
        return string;
    }
    if ([value isKindOfClass:NSNumber.class]) return [value description] ?: @"";
    if ([value isKindOfClass:NSURL.class]) return [(NSURL *)value absoluteString] ?: @"";
    if ([value isKindOfClass:NSData.class]) return [(NSData *)value base64EncodedStringWithOptions:0] ?: @"";
    if ([value isKindOfClass:NSDate.class]) return [NSString stringWithFormat:@"%.6f", [(NSDate *)value timeIntervalSince1970]];
    id json = [value isKindOfClass:NSSet.class] ? [(NSSet *)value allObjects] : value;
    NSString *pretty = RYGPrettyJSON(json);
    return pretty.length ? pretty : ([value description] ?: @"");
}

static id RYGParseObjectText(NSString *text, id currentRaw, NSString **errorText) {
    if (errorText) *errorText = nil;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *lower = trimmed.lowercaseString;

    if ([lower isEqualToString:@"nil"] || [lower isEqualToString:@"null"]) return NSNull.null;
    if ([lower hasPrefix:@"string:"]) return [trimmed substringFromIndex:7];
    if ([lower hasPrefix:@"number:"]) return RYGDecimalNumber([trimmed substringFromIndex:7], errorText);
    if ([lower hasPrefix:@"url:"]) {
        NSURL *url = [NSURL URLWithString:[trimmed substringFromIndex:4]];
        if (!url && errorText) *errorText = @"Invalid URL.";
        return url;
    }
    if ([lower hasPrefix:@"data:"]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:[trimmed substringFromIndex:5] options:0];
        if (!data && errorText) *errorText = @"Invalid Base64.";
        return data;
    }
    if ([lower hasPrefix:@"date:"]) {
        NSNumber *number = RYGDecimalNumber([trimmed substringFromIndex:5], errorText);
        return number ? [NSDate dateWithTimeIntervalSince1970:number.doubleValue] : nil;
    }
    if ([lower hasPrefix:@"json:"]) return RYGParseJSON([trimmed substringFromIndex:5], errorText);
    if ([lower hasPrefix:@"set:"]) {
        id object = RYGParseJSON([trimmed substringFromIndex:4], errorText);
        if (![object isKindOfClass:NSArray.class]) {
            if (errorText && !*errorText) *errorText = @"set: requires a JSON array.";
            return nil;
        }
        return [NSSet setWithArray:object];
    }

    if ([currentRaw isKindOfClass:NSString.class]) return text ?: @"";
    if ([currentRaw isKindOfClass:NSNumber.class]) return RYGDecimalNumber(trimmed, errorText);
    if ([currentRaw isKindOfClass:NSURL.class]) {
        NSURL *url = [NSURL URLWithString:trimmed];
        if (!url && errorText) *errorText = @"Invalid URL.";
        return url;
    }
    if ([currentRaw isKindOfClass:NSData.class]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:trimmed options:0];
        if (!data && errorText) *errorText = @"Invalid Base64.";
        return data;
    }
    if ([currentRaw isKindOfClass:NSDate.class]) {
        NSNumber *number = RYGDecimalNumber(trimmed, errorText);
        return number ? [NSDate dateWithTimeIntervalSince1970:number.doubleValue] : nil;
    }
    if ([currentRaw isKindOfClass:NSSet.class]) {
        id object = RYGParseJSON(trimmed, errorText);
        if (![object isKindOfClass:NSArray.class]) {
            if (errorText && !*errorText) *errorText = @"NSSet requires a JSON array.";
            return nil;
        }
        return [NSSet setWithArray:object];
    }
    if ([currentRaw isKindOfClass:NSArray.class] || [currentRaw isKindOfClass:NSDictionary.class] ||
        [trimmed hasPrefix:@"["] || [trimmed hasPrefix:@"{"]) {
        return RYGParseJSON(trimmed, errorText);
    }
    return text ?: @"";
}

@interface RYGRuntimeFullValueEditorViewController : UIViewController <UITextViewDelegate>
@property(nonatomic, copy) NSString *targetClassName;
@property(nonatomic, copy) NSString *targetSelectorName;
@property(nonatomic, copy) NSString *targetTypeCode;
@property(nonatomic, assign) BOOL targetMeta;
@property(nonatomic, strong) id sourceValue;
@property(nonatomic, assign) BOOL preserveString;
@property(nonatomic, assign) BOOL validateJSON;
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, copy) dispatch_block_t completion;
@end

@implementation RYGRuntimeFullValueEditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.targetSelectorName.length ? self.targetSelectorName : @"Runtime Object";
    self.navigationItem.titleView = RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor = [RYGPopupChrome backgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                           target:self
                                                                                           action:@selector(cancelPressed)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(applyPressed)];

    UILabel *status = [UILabel new];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightRegular];
    status.textColor = UIColor.secondaryLabelColor;
    status.numberOfLines = 4;
    status.text = [NSString stringWithFormat:@"%@ · %@ method · %@\nOriginal object: %@\nOuter Objective-C ABI stays object (@).%@",
                   self.targetClassName ?: @"Runtime",
                   self.targetMeta ? @"class" : @"instance",
                   RYGRuntimeValueTypeName(self.targetTypeCode) ?: self.targetTypeCode ?: @"object",
                   self.sourceValue ? NSStringFromClass([self.sourceValue class]) : @"nil",
                   self.preserveString ? @" JSON may be formatted here, but Apply keeps it NSString and compacts only insignificant whitespace." : @""];
    [self.view addSubview:status];
    self.statusLabel = status;

    UIButton *format = [UIButton buttonWithType:UIButtonTypeSystem];
    format.translatesAutoresizingMaskIntoConstraints = NO;
    [format setTitle:@"Format JSON" forState:UIControlStateNormal];
    [format addTarget:self action:@selector(formatPressed) forControlEvents:UIControlEventTouchUpInside];
    RYGMarkOwnedView(format); RYGLiquidGlassConfigureButton(format, NO);

    UIButton *validate = [UIButton buttonWithType:UIButtonTypeSystem];
    validate.translatesAutoresizingMaskIntoConstraints = NO;
    [validate setTitle:@"Validate JSON" forState:UIControlStateNormal];
    [validate addTarget:self action:@selector(validatePressed) forControlEvents:UIControlEventTouchUpInside];
    RYGMarkOwnedView(validate); RYGLiquidGlassConfigureButton(validate, NO);

    UIButton *original = [UIButton buttonWithType:UIButtonTypeSystem];
    original.translatesAutoresizingMaskIntoConstraints = NO;
    [original setTitle:@"Use Original" forState:UIControlStateNormal];
    [original addTarget:self action:@selector(originalPressed) forControlEvents:UIControlEventTouchUpInside];
    RYGMarkOwnedView(original); RYGLiquidGlassConfigureButton(original, NO);

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[format, validate, original]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.distribution = UIStackViewDistributionFillEqually;
    buttons.spacing = 8.0;
    [self.view addSubview:buttons];

    UITextView *text = [UITextView new];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.alwaysBounceVertical = YES;
    text.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    text.autocorrectionType = UITextAutocorrectionTypeNo;
    text.autocapitalizationType = UITextAutocapitalizationTypeNone;
    text.smartQuotesType = UITextSmartQuotesTypeNo;
    text.smartDashesType = UITextSmartDashesTypeNo;
    text.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    text.textContainerInset = UIEdgeInsetsMake(12, 10, 18, 10);
    text.layer.cornerRadius = 14.0;
    text.backgroundColor = UIColor.secondarySystemBackgroundColor;
    text.text = RYGObjectText(self.sourceValue);
    text.delegate = self;
    [self.view addSubview:text];
    self.textView = text;

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [status.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [status.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [status.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [buttons.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [buttons.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [buttons.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:8],
        [buttons.heightAnchor constraintEqualToConstant:38],
        [text.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8],
        [text.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8],
        [text.topAnchor constraintEqualToAnchor:buttons.bottomAnchor constant:6],
        [text.bottomAnchor constraintEqualToAnchor:self.view.keyboardLayoutGuide.topAnchor],
    ]];
    RYGLiquidGlassApplyToViewController(self);
}

- (void)closeEditor {
    if (self.navigationController && self.navigationController.viewControllers.firstObject != self) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)cancelPressed { [self closeEditor]; }

- (void)formatPressed {
    NSString *error = nil;
    id object = RYGParseJSON(self.textView.text ?: @"", &error);
    NSString *pretty = RYGPrettyJSON(object);
    if (!pretty.length) { RYGEditorError(self, error ?: @"Text is not valid JSON."); return; }
    self.textView.text = pretty;
    self.validateJSON = YES;
}

- (void)validatePressed {
    NSString *error = nil;
    id object = RYGParseJSON(self.textView.text ?: @"", &error);
    if (!object) { RYGEditorError(self, error ?: @"Invalid JSON."); return; }
    self.validateJSON = YES;
    self.statusLabel.textColor = UIColor.systemGreenColor;
    self.statusLabel.text = [NSString stringWithFormat:@"Valid JSON · %@\nOuter object remains %@.",
                             NSStringFromClass([object class]) ?: @"object",
                             self.preserveString ? @"NSString" : (self.sourceValue ? NSStringFromClass([self.sourceValue class]) : @"Foundation object")];
}

- (void)originalPressed {
    RYGRuntimeValueClearOverride(self.targetClassName, self.targetSelectorName, self.targetMeta);
    if (self.completion) self.completion();
    [self closeEditor];
}

- (void)applyPressed {
    NSString *text = self.textView.text ?: @"";
    id value = nil;
    NSString *error = nil;

    if (self.preserveString) {
        if (self.validateJSON || RYGLooksLikeJSON(text)) {
            id parsed = RYGParseJSON(text, &error);
            if (!parsed) { RYGEditorError(self, error ?: @"Invalid JSON."); return; }
            text = RYGCompactJSONLexically(text);
        }
        value = text;
    } else {
        value = RYGParseObjectText(text, self.sourceValue, &error);
        if (!value) { RYGEditorError(self, error ?: @"Could not parse object."); return; }
    }

    BOOL installed = RYGEditorPersistAndInstall(self.targetClassName, self.targetSelectorName,
                                                 self.targetMeta, self.targetTypeCode,
                                                 value, self.completion);
    if (!installed) {
        RYGEditorError(self, @"The typed override was persisted, but its exact hook is still pending. Use Apply after the target image/receiver is available.");
        return;
    }
    [self closeEditor];
}
@end

static void RYGEditorPrompt(UIViewController *presenter, NSString *title, NSString *message,
                            NSString *initial, UIKeyboardType keyboard,
                            void (^parseAndApply)(NSString *text)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = initial ?: @"";
        field.keyboardType = keyboard;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Apply" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        if (parseAndApply) parseAndApply(alert.textFields.firstObject.text ?: @"");
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

void RYGPresentRuntimeValueEditor(UIViewController *presenter, UIView *sourceView,
                                  NSString *className, NSString *selectorName, BOOL meta,
                                  NSString *typeCode, NSString *currentDescription,
                                  id currentRawValue, dispatch_block_t completion) {
    if (!presenter || !className.length || !selectorName.length || !typeCode.length) return;

    BOOL overridden = RYGRuntimeValueHasOverride(className, selectorName, meta);
    id forced = RYGRuntimeValueOverride(className, selectorName, meta);
    NSString *typeName = RYGRuntimeValueTypeName(typeCode) ?: typeCode;
    NSString *message = [NSString stringWithFormat:@"%@\n%@ method · %@\nCurrent: %@%@",
                         className, meta ? @"class" : @"instance", typeName,
                         currentDescription ?: @"?",
                         overridden ? [NSString stringWithFormat:@"\nOverride: %@", forced ?: @"nil"] : @""];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:selectorName
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = sourceView ?: presenter.view;
    sheet.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : presenter.view.bounds;

    if (RYGRuntimeValueTypeIsBoolean(typeCode)) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force YES" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            RYGEditorApply(className, selectorName, meta, typeCode, @YES, completion);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force NO" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            RYGEditorApply(className, selectorName, meta, typeCode, @NO, completion);
        }]];
    } else if (RYGRuntimeValueTypeIsSignedInteger(typeCode)) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Set signed integer…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *initial = overridden ? [forced description] : [currentRawValue description];
            RYGEditorPrompt(presenter, selectorName, @"Signed decimal integer.", initial, UIKeyboardTypeNumbersAndPunctuation, ^(NSString *text) {
                NSScanner *scanner = [NSScanner scannerWithString:text]; long long value = 0;
                if (![scanner scanLongLong:&value] || !scanner.isAtEnd) { RYGEditorError(presenter, @"Invalid decimal integer."); return; }
                RYGEditorApply(className, selectorName, meta, typeCode, @(value), completion);
            });
        }]];
    } else if (RYGRuntimeValueTypeIsUnsignedInteger(typeCode)) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Set unsigned integer…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *initial = overridden ? [forced description] : [currentRawValue description];
            RYGEditorPrompt(presenter, selectorName, @"Unsigned decimal integer.", initial, UIKeyboardTypeNumberPad, ^(NSString *text) {
                if (!text.length || [text hasPrefix:@"-"]) { RYGEditorError(presenter, @"Invalid unsigned integer."); return; }
                char *end = NULL; const char *start = text.UTF8String ?: ""; unsigned long long value = strtoull(start, &end, 10);
                if (!end || end == start || *end != '\0') { RYGEditorError(presenter, @"Invalid decimal integer."); return; }
                RYGEditorApply(className, selectorName, meta, typeCode, @(value), completion);
            });
        }]];
    } else if (RYGRuntimeValueTypeIsFloatingPoint(typeCode)) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Set decimal…" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            NSString *initial = overridden ? [forced description] : [currentRawValue description];
            RYGEditorPrompt(presenter, selectorName, @"Decimal using a dot.", initial, UIKeyboardTypeDecimalPad, ^(NSString *text) {
                NSScanner *scanner = [NSScanner scannerWithString:text]; double value = 0.0;
                if (![scanner scanDouble:&value] || !scanner.isAtEnd) { RYGEditorError(presenter, @"Invalid decimal."); return; }
                RYGEditorApply(className, selectorName, meta, typeCode, @(value), completion);
            });
        }]];
    } else if (RYGRuntimeValueTypeIsObject(typeCode)) {
        id effective = overridden ? forced : currentRawValue;
        BOOL longString = [effective isKindOfClass:NSString.class] && [(NSString *)effective length] > 96;
        BOOL jsonString = [effective isKindOfClass:NSString.class] && RYGLooksLikeJSON(effective);
        BOOL complex = [effective isKindOfClass:NSArray.class] || [effective isKindOfClass:NSDictionary.class] ||
                       [effective isKindOfClass:NSSet.class] || [effective isKindOfClass:NSData.class] ||
                       longString || jsonString;
        [sheet addAction:[UIAlertAction actionWithTitle:complex ? @"Open full-screen editor…" : @"Set Foundation object…"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
            if (complex) {
                RYGRuntimeFullValueEditorViewController *editor = [RYGRuntimeFullValueEditorViewController new];
                editor.targetClassName = className;
                editor.targetSelectorName = selectorName;
                editor.targetTypeCode = typeCode;
                editor.targetMeta = meta;
                editor.sourceValue = effective;
                editor.preserveString = [effective isKindOfClass:NSString.class];
                editor.validateJSON = jsonString;
                editor.completion = completion;
                if (presenter.navigationController) {
                    [presenter.navigationController pushViewController:editor animated:YES];
                } else {
                    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
                    nav.modalPresentationStyle = UIModalPresentationPageSheet;
                    [presenter presentViewController:nav animated:YES completion:nil];
                }
                return;
            }
            NSString *help = [NSString stringWithFormat:@"Current object: %@. Preserve the current type or use string:, number:, url:, data:<base64>, date:<timestamp>, json:<JSON>, set:<array JSON>.", effective ? NSStringFromClass([effective class]) : @"nil"];
            RYGEditorPrompt(presenter, selectorName, help, RYGObjectText(effective), UIKeyboardTypeDefault, ^(NSString *text) {
                NSString *error = nil; id value = RYGParseObjectText(text, currentRawValue, &error);
                if (!value) { RYGEditorError(presenter, error); return; }
                RYGEditorApply(className, selectorName, meta, typeCode, value, completion);
            });
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Force nil" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            RYGEditorApply(className, selectorName, meta, typeCode, NSNull.null, completion);
        }]];
    }

    if (overridden) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use original" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            RYGRuntimeValueClearOverride(className, selectorName, meta);
            if (completion) completion();
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy name + value" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"%@ %@ %@ (%@) = %@",
            meta ? @"+" : @"-", className, selectorName, typeName, currentDescription ?: @"?"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:sheet animated:YES completion:nil];
}
