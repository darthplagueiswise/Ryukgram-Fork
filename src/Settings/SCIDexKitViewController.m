#import "SCIDexKitViewController.h"
#import "../Features/ExpFlags/SCIDexKitNameResolver.h"
#import "../Features/ExpFlags/SCIDexKitScanner.h"
#import "../Features/ExpFlags/SCIDexKitStore.h"
#import "../Features/ExpFlags/SCIDexKitBoolRouter.h"
#import "../Features/ExpFlags/SCIDexKitSelectorRules.h"
#import "../Features/ExpFlags/SCIMobileConfigIdNameMappingExporter.h"

typedef NS_ENUM(NSInteger, SCIDexKitUIFilter) {
    SCIDexKitUIFilterRecommended,
    SCIDexKitUIFilterAll,
    SCIDexKitUIFilterObserved,
    SCIDexKitUIFilterForced,
    SCIDexKitUIFilterHidden
};
static NSString *const kSCIDexKitHiddenKeywordsKey = @"sci_dexkit_hidden_keywords";

static NSString *SCIIdMapUIString(id value) { return [value isKindOfClass:NSString.class] ? (NSString *)value : @""; }
static NSString *SCIIdMapUIJoin(NSArray *values, NSUInteger limit) {
    if (![values isKindOfClass:NSArray.class] || !values.count) return @"";
    NSMutableArray<NSString *> *parts=[NSMutableArray array];
    NSUInteger n=MIN(values.count,limit);
    for(NSUInteger i=0;i<n;i++){
        NSString *s=SCIIdMapUIString(values[i]);
        if(s.length)[parts addObject:s];
    }
    if(values.count>limit)[parts addObject:[NSString stringWithFormat:@"... +%lu",(unsigned long)(values.count-limit)]];
    return [parts componentsJoinedByString:@"\n"];
}
static NSString *SCIIdMapUIResultMessage(NSDictionary *result) {
    if(![result isKindOfClass:NSDictionary.class]) return @"Resultado inválido.";
    BOOL ok=[result[@"ok"] boolValue];
    NSString *status=SCIIdMapUIString(result[@"status"]);
    NSString *source=SCIIdMapUIString(result[@"source"]);
    NSArray *outputs=[result[@"outputs"] isKindOfClass:NSArray.class]?result[@"outputs"]:@[];
    NSArray *errors=[result[@"errors"] isKindOfClass:NSArray.class]?result[@"errors"]:@[];
    NSNumber *count=[result[@"count"] respondsToSelector:@selector(unsignedLongLongValue)]?result[@"count"]:@0;
    NSNumber *checked=[result[@"checked"] respondsToSelector:@selector(unsignedLongLongValue)]?result[@"checked"]:@0;
    NSMutableString *msg=[NSMutableString string];
    [msg appendFormat:@"%@\n\n", status.length?status:(ok?@"id_name_mapping exported":@"id_name_mapping not found")];
    [msg appendFormat:@"entries: %@\nchecked paths: %@\n",count,checked];
    if(source.length)[msg appendFormat:@"\nsource:\n%@\n",source];
    NSString *outText=SCIIdMapUIJoin(outputs,8); if(outText.length)[msg appendFormat:@"\noutputs:\n%@\n",outText];
    NSString *errText=SCIIdMapUIJoin(errors,6); if(errText.length)[msg appendFormat:@"\nerrors:\n%@\n",errText];
    return msg;
}

@interface SCIDexKitCell : UITableViewCell
@property UILabel *title;
@property UILabel *detail;
@property UISegmentedControl *state;
@property (copy) void (^stateChanged)(NSInteger);
@end

@implementation SCIDexKitCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self=[super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if(!self)return nil;
    self.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    self.contentView.backgroundColor=self.backgroundColor;
    _title=[UILabel new];
    _title.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _title.numberOfLines=2;
    _title.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:_title];
    _detail=[UILabel new];
    _detail.font=[UIFont systemFontOfSize:11];
    _detail.textColor=UIColor.secondaryLabelColor;
    _detail.numberOfLines=3;
    _detail.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:_detail];
    _state=[[UISegmentedControl alloc] initWithItems:@[@"System",@"OFF",@"ON"]];
    _state.translatesAutoresizingMaskIntoConstraints=NO;
    [_state addTarget:self action:@selector(stateDidChange) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_state];
    [NSLayoutConstraint activateConstraints:@[
        [_state.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [_state.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [_state.widthAnchor constraintEqualToConstant:176],
        [_title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9],
        [_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_title.trailingAnchor constraintEqualToAnchor:_state.leadingAnchor constant:-8],
        [_detail.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],
        [_detail.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
        [_detail.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
        [_detail.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-9]
    ]];
    return self;
}
- (void)stateDidChange { if(_stateChanged)_stateChanged(_state.selectedSegmentIndex); }
@end

@interface SCIDexKitHeader : UITableViewHeaderFooterView
@property UILabel *title;
@property UILabel *detail;
@property UIButton *observeButton;
@property UIButton *clearButton;
@property UIButton *actionsButton;
@property (copy) void (^observePressed)(void);
@property (copy) void (^clearPressed)(void);
@property (copy) void (^actionsPressed)(void);
@end

@implementation SCIDexKitHeader
- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self=[super initWithReuseIdentifier:reuseIdentifier];
    if(!self)return nil;
    self.contentView.backgroundColor=UIColor.systemGroupedBackgroundColor;
    _title=[UILabel new];
    _title.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _title.numberOfLines=2;
    _title.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:_title];
    _detail=[UILabel new];
    _detail.font=[UIFont systemFontOfSize:10];
    _detail.textColor=UIColor.secondaryLabelColor;
    _detail.numberOfLines=2;
    _detail.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:_detail];
    _observeButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [_observeButton setTitle:@"Observe" forState:UIControlStateNormal];
    _observeButton.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [_observeButton addTarget:self action:@selector(observe) forControlEvents:UIControlEventTouchUpInside];
    _clearButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [_clearButton setTitle:@"Clear" forState:UIControlStateNormal];
    _clearButton.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [_clearButton addTarget:self action:@selector(clear) forControlEvents:UIControlEventTouchUpInside];
    _actionsButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [_actionsButton setTitle:@"Actions" forState:UIControlStateNormal];
    _actionsButton.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    [_actionsButton addTarget:self action:@selector(actions) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[_observeButton,_clearButton,_actionsButton]];
    stack.axis=UILayoutConstraintAxisHorizontal;
    stack.alignment=UIStackViewAlignmentCenter;
    stack.spacing=6;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
        [_title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8],
        [_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
        [_title.trailingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:-8],
        [_detail.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:3],
        [_detail.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
        [_detail.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
        [_detail.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-8]
    ]];
    return self;
}
- (void)observe { if(_observePressed)_observePressed(); }
- (void)clear { if(_clearPressed)_clearPressed(); }
- (void)actions { if(_actionsPressed)_actionsPressed(); }
@end

@interface SCIDexKitViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property UISegmentedControl *filter;
@property UISearchBar *search;
@property UITableView *table;
@property UILabel *footer;
@property NSArray<SCIDexKitDescriptor *> *rows;
@property NSArray<NSString *> *sections;
@property NSDictionary<NSString *,NSArray<SCIDexKitDescriptor *> *> *groups;
@property SCIDexKitScannerMode scanMode;
@property NSString *query;
@end

@implementation SCIDexKitViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"SCI DexKit 2.0";
    self.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    _scanMode=SCIDexKitScannerModeCurated;
    _filter=[[UISegmentedControl alloc] initWithItems:@[@"Recommended",@"All",@"Observed",@"Forced",@"Hidden"]];
    _filter.selectedSegmentIndex=0;
    [_filter addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    _filter.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_filter];
    _search=[UISearchBar new];
    _search.searchBarStyle=UISearchBarStyleMinimal;
    _search.placeholder=@"Search owner/function/source";
    _search.delegate=self;
    _search.autocapitalizationType=UITextAutocapitalizationTypeNone;
    _search.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_search];
    _footer=[UILabel new];
    _footer.font=[UIFont systemFontOfSize:11];
    _footer.textColor=UIColor.secondaryLabelColor;
    _footer.numberOfLines=0;
    _footer.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_footer];
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _table.dataSource=self;
    _table.delegate=self;
    _table.rowHeight=UITableViewAutomaticDimension;
    _table.estimatedRowHeight=64;
    _table.backgroundColor=UIColor.systemGroupedBackgroundColor;
    [_table registerClass:SCIDexKitCell.class forCellReuseIdentifier:@"cell"];
    [_table registerClass:SCIDexKitHeader.class forHeaderFooterViewReuseIdentifier:@"header"];
    _table.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:_table];
    self.navigationItem.rightBarButtonItems=@[
        [[UIBarButtonItem alloc] initWithTitle:@"ID Map" style:UIBarButtonItemStylePlain target:self action:@selector(exportIDNameMapping)],
        [[UIBarButtonItem alloc] initWithTitle:@"Refresh" style:UIBarButtonItemStylePlain target:self action:@selector(reload)],
        [[UIBarButtonItem alloc] initWithTitle:@"Observe" style:UIBarButtonItemStylePlain target:self action:@selector(observeVisible)]
    ];
    UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_filter.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [_filter.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:12],
        [_filter.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-12],
        [_search.topAnchor constraintEqualToAnchor:_filter.bottomAnchor constant:4],
        [_search.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [_search.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [_footer.topAnchor constraintEqualToAnchor:_search.bottomAnchor constant:2],
        [_footer.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:14],
        [_footer.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-14],
        [_table.topAnchor constraintEqualToAnchor:_footer.bottomAnchor constant:4],
        [_table.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:g.bottomAnchor]
    ]];
    [self reload];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SCIDexKitNameResolverDidUpdateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:SCIMobileConfigIdNameMappingExporterDidUpdateNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSString *)riskText:(NSInteger)risk { switch(risk){ case 0: return @"none"; case 1: return @"low"; case 2: return @"medium"; case 3: return @"high"; case 4: return @"blocked"; default: return [NSString stringWithFormat:@"%ld",(long)risk]; } }
- (NSString *)conflictFamilyForDescriptor:(SCIDexKitDescriptor *)d { return [SCIDexKitSelectorRules conflictFamilyLabelForFamilyKey:d.familyKey ?: @""] ?: @""; }
- (BOOL)isConflictDescriptor:(SCIDexKitDescriptor *)d { return [self conflictFamilyForDescriptor:d].length > 0; }
- (NSString *)policyText:(SCIDexKitDescriptor *)d {
    NSString *conflict=[self conflictFamilyForDescriptor:d];
    if(conflict.length) return [NSString stringWithFormat:@"conflict %@ · observe first", conflict];
    if(d.forceRecommended) return d.batchForceAllowed?@"force-ok":@"force manual";
    if(d.observeRecommended) return @"observe first";
    return @"hidden/noisy";
}
- (NSString *)stateText:(SCIDexKitKnownBoolState)st { return st==SCIDexKitKnownBoolStateOn?@"ON":(st==SCIDexKitKnownBoolStateOff?@"OFF":@"unknown"); }
- (BOOL)isHiddenNoise:(SCIDexKitDescriptor *)d {
    NSString *cat=d.semanticCategory.lowercaseString ?: @"";
    NSString *hay=[[NSString stringWithFormat:@"%@ %@ %@ %@ %@", d.className ?: @"", d.selectorName ?: @"", d.semanticCategory ?: @"", d.classificationReason ?: @"", d.familyKey ?: @""] lowercaseString];
    NSArray *custom = [[NSUserDefaults standardUserDefaults] arrayForKey:kSCIDexKitHiddenKeywordsKey];
    if ([custom isKindOfClass:NSArray.class]) {
        for (id item in custom) {
            NSString *kw = [[item isKindOfClass:NSString.class] ? item : @"" lowercaseString];
            if (kw.length && [hay containsString:kw]) return YES;
        }
    }
    if(d.riskLevel>=4) return YES;
    if(!d.observeRecommended) return YES;
    if([cat isEqualToString:@"ui-state"] || [cat isEqualToString:@"lifecycle-state"] || [cat isEqualToString:@"loading-state"] || [cat isEqualToString:@"selection-state"]) return YES;
    return NO;
}
- (BOOL)isRecommended:(SCIDexKitDescriptor *)d {
    if([self isHiddenNoise:d]) return NO;
    NSString *cat=d.semanticCategory.lowercaseString ?: @"";
    if(d.forceRecommended || d.batchForceAllowed) return YES;
    if([cat isEqualToString:@"feature-gate"] || [cat isEqualToString:@"experiment-gate"] || [cat isEqualToString:@"eligibility-gate"]) return YES;
    if([cat isEqualToString:@"config-option"] || [cat isEqualToString:@"variant-option"] || [cat isEqualToString:@"debug-internal"]) return YES;
    return d.riskLevel<=2;
}
- (NSString *)filterName {
    switch((SCIDexKitUIFilter)_filter.selectedSegmentIndex){
        case SCIDexKitUIFilterRecommended: return @"Recommended";
        case SCIDexKitUIFilterAll: return @"All";
        case SCIDexKitUIFilterObserved: return @"Observed";
        case SCIDexKitUIFilterForced: return @"Forced";
        case SCIDexKitUIFilterHidden: return @"Hidden";
    }
    return @"?";
}

- (BOOL)descriptorNeedsExplicitOverrideConfirmation:(SCIDexKitDescriptor *)d {
    (void)d;
    return NO;
}
- (void)setOverrideValue:(NSNumber *)value descriptor:(SCIDexKitDescriptor *)d {
    [SCIDexKitStore setOverrideValue:value forKey:d.overrideKey];
    if(value) SCIDexKitInstallHookForDescriptor(d,SCIDexKitInstallReasonUserOverride,nil);
    [self reload];
}
- (void)confirmAndForceDescriptor:(SCIDexKitDescriptor *)d value:(BOOL)value {
    NSString *conflict=[self conflictFamilyForDescriptor:d];
    NSMutableArray<NSString *> *reasons=[NSMutableArray array];
    if(conflict.length)[reasons addObject:[NSString stringWithFormat:@"Conflict family: %@. Batch force is blocked; override is explicit per-row only.", conflict]];
    if(!d.observedKnown)[reasons addObject:@"This method has not been observed in runtime yet."];
    if(!d.forceRecommended)[reasons addObject:@"Classifier does not mark it as forceRecommended."];
    if(d.riskLevel>=3)[reasons addObject:[NSString stringWithFormat:@"Risk: %@.",[self riskText:d.riskLevel]]];
    NSString *message=[NSString stringWithFormat:@"Discovery -> Observation -> Override\n\n%@\n\n%@", d.selectorName ?: @"", [reasons componentsJoinedByString:@"\n"] ?: @""];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:value?@"Confirm Force ON":@"Confirm Force OFF" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *x){ [self reload]; }]];
    [a addAction:[UIAlertAction actionWithTitle:value?@"Force ON":@"Force OFF" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *x){ [self setOverrideValue:@(value) descriptor:d]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)forceDescriptor:(SCIDexKitDescriptor *)d value:(BOOL)value {
    [self setOverrideValue:@(value) descriptor:d];
}
- (void)applySegment:(NSInteger)idx descriptor:(SCIDexKitDescriptor *)d {
    if(idx==0){ [self setOverrideValue:nil descriptor:d]; return; }
    [self forceDescriptor:d value:(idx==2)];
}
- (void)clearOverridesInRows:(NSArray<SCIDexKitDescriptor *> *)rows { for(SCIDexKitDescriptor *d in rows){ if(d.overrideValue)[SCIDexKitStore setOverrideValue:nil forKey:d.overrideKey]; } [self reload]; }
- (NSArray<SCIDexKitDescriptor *> *)batchAllowedRows:(NSArray<SCIDexKitDescriptor *> *)rows { NSMutableArray *out=[NSMutableArray array]; for(SCIDexKitDescriptor *d in rows){ if(d.batchForceAllowed && d.forceRecommended && !d.unavailable && ![self isConflictDescriptor:d])[out addObject:d]; } return out; }
- (void)observeRows:(NSArray<SCIDexKitDescriptor *> *)rows { SCIDexKitEnableSessionObservationForDescriptors(rows ?: @[]); [self reload]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self reload];}); }
- (void)forceBatchRows:(NSArray<SCIDexKitDescriptor *> *)rows value:(BOOL)value { for(SCIDexKitDescriptor *d in rows){ if([self isConflictDescriptor:d]) continue; [SCIDexKitStore setOverrideValue:@(value) forKey:d.overrideKey]; SCIDexKitInstallHookForDescriptor(d,SCIDexKitInstallReasonUserOverride,nil); } [self reload]; }
- (void)forceClassRows:(NSArray<SCIDexKitDescriptor *> *)rows value:(BOOL)value {
    for (SCIDexKitDescriptor *d in rows) {
        if (!d.overrideKey.length || d.unavailable) continue;
        [SCIDexKitStore setOverrideValue:@(value) forKey:d.overrideKey];
        SCIDexKitInstallHookForDescriptor(d, SCIDexKitInstallReasonUserOverride, nil);
    }
    [self reload];
}
- (void)showGroupActionsForRows:(NSArray<SCIDexKitDescriptor *> *)rows sourceView:(UIView *)sourceView {
    if(!rows.count)return;
    SCIDexKitDescriptor *first=rows.firstObject;
    NSArray *safe=[self batchAllowedRows:rows];
    NSUInteger conflicts=0;
    NSMutableSet<NSString *> *families=[NSMutableSet set];
    for(SCIDexKitDescriptor *d in rows){ NSString *f=[self conflictFamilyForDescriptor:d]; if(f.length){ conflicts++; [families addObject:f]; } }
    NSString *familyText=families.count ? [NSString stringWithFormat:@"\nConflict families: %@\nThese are Discovery + Observation + explicit per-row Override only.", [[families allObjects] componentsJoinedByString:@", "]] : @"";
    UIAlertController *a=[UIAlertController alertControllerWithTitle:first.ownerDisplayName message:[NSString stringWithFormat:@"Group actions are observe-first. Batch force applies only to %lu safe methods, never to conflict families.\nMethods: %lu · conflicts: %lu%@",(unsigned long)safe.count,(unsigned long)rows.count,(unsigned long)conflicts,familyText] preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Observe group" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self observeRows:rows];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Clear forced in group" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self clearOverridesInRows:rows];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force class ON (all methods)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self forceClassRows:rows value:YES];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force class OFF (all methods)" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self forceClassRows:rows value:NO];}]];
    if(safe.count){
        [a addAction:[UIAlertAction actionWithTitle:@"Force safe recommended ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self forceBatchRows:safe value:YES];}]];
        [a addAction:[UIAlertAction actionWithTitle:@"Force safe recommended OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){[self forceBatchRows:safe value:NO];}]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Copy group keys" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){ NSMutableArray *keys=[NSMutableArray array]; for(SCIDexKitDescriptor*d in rows){ if(d.overrideKey.length)[keys addObject:d.overrideKey]; } UIPasteboard.generalPasteboard.string=[keys componentsJoinedByString:@"\n"]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if(a.popoverPresentationController){ a.popoverPresentationController.sourceView=sourceView ?: self.view; a.popoverPresentationController.sourceRect=(sourceView ?: self.view).bounds; }
    [self presentViewController:a animated:YES completion:nil];
}

- (void)exportIDNameMapping {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"ID Map"
                                                                  message:@"Procurando e exportando id_name_mapping.json..."
                                                           preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:wait animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSDictionary *result = [SCIMobileConfigIdNameMappingExporter exportIDNameMappingNow];
            NSString *message = SCIIdMapUIResultMessage(result);

            dispatch_async(dispatch_get_main_queue(), ^{
                [wait dismissViewControllerAnimated:YES completion:^{
                    BOOL ok = [result[@"ok"] boolValue];
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(ok ? @"ID Map exportado" : @"ID Map não encontrado")
                                                                                   message:message
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];

                    [alert addAction:[UIAlertAction actionWithTitle:@"Copiar relatório"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
                        UIPasteboard.generalPasteboard.string = message;
                    }]];

                    NSString *source = SCIIdMapUIString(result[@"source"]);
                    if (source.length) {
                        [alert addAction:[UIAlertAction actionWithTitle:@"Copiar source path"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(__unused UIAlertAction *action) {
                            UIPasteboard.generalPasteboard.string = source;
                        }]];
                    }

                    NSArray *outputs = [result[@"outputs"] isKindOfClass:NSArray.class] ? result[@"outputs"] : @[];
                    NSString *outputText = SCIIdMapUIJoin(outputs, 99);
                    if (outputText.length) {
                        [alert addAction:[UIAlertAction actionWithTitle:@"Copiar output paths"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(__unused UIAlertAction *action) {
                            UIPasteboard.generalPasteboard.string = outputText;
                        }]];
                    }

                    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                              style:UIAlertActionStyleCancel
                                                            handler:nil]];

                    if (alert.popoverPresentationController) {
                        alert.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
                    }

                    [self presentViewController:alert animated:YES completion:nil];
                    [self reload];
                }];
            });
        });
    }];
}
- (void)observeVisible { [self observeRows:self.rows ?: @[]]; }
- (SCIDexKitKnownBoolState)effective:(SCIDexKitDescriptor *)d { return [SCIDexKitStore effectiveStateForOverrideKey:d.overrideKey observedKey:d.observedKey]; }
- (void)reload {
    NSArray *all=[SCIDexKitScanner scanDescriptorsWithMode:_scanMode query:_query];
    NSMutableArray *filtered=[NSMutableArray array];
    NSUInteger hiddenTotal=0;
    NSUInteger recommendedTotal=0;
    NSUInteger conflictTotal=0;
    for(SCIDexKitDescriptor *d in all){
        BOOL hidden=[self isHiddenNoise:d];
        BOOL recommended=[self isRecommended:d];
        BOOL conflict=[self isConflictDescriptor:d];
        if(hidden)hiddenTotal++;
        if(recommended)recommendedTotal++;
        if(conflict)conflictTotal++;
        NSInteger f=_filter.selectedSegmentIndex;
        if(f==SCIDexKitUIFilterRecommended && !recommended)continue;
        if(f==SCIDexKitUIFilterAll && hidden)continue;
        if(f==SCIDexKitUIFilterObserved && (!d.observedKnown || hidden))continue;
        if(f==SCIDexKitUIFilterForced && (!d.overrideValue || hidden))continue;
        if(f==SCIDexKitUIFilterHidden && !hidden)continue;
        [filtered addObject:d];
    }
    _rows=filtered;
    NSMutableDictionary *g=[NSMutableDictionary dictionary];
    for(SCIDexKitDescriptor *d in _rows){ NSString *k=d.ownerGroupKey; if(!g[k])g[k]=[NSMutableArray array]; [(NSMutableArray *)g[k] addObject:d]; }
    _sections=[[g allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    _groups=g;
    NSString *idMapStatus=[SCIMobileConfigIdNameMappingExporter lastStatusLine] ?: @"idmap idle";
    _footer.text=[NSString stringWithFormat:@"Curated %@ · filter %@ · rows=%lu · groups=%lu · recommended=%lu · hidden=%lu · conflicts=%lu · hooks=%lu\n%@", _scanMode==SCIDexKitScannerModeCurated?@"B-only":@"Raw",[self filterName],(unsigned long)_rows.count,(unsigned long)_sections.count,(unsigned long)recommendedTotal,(unsigned long)hiddenTotal,(unsigned long)conflictTotal,(unsigned long)SCIDexKitInstalledHookCount(),idMapStatus];
    [_table reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [_groups[_sections[section]] count]; }
- (NSArray *)rowsInSection:(NSInteger)section { return _groups[_sections[section]] ?: @[]; }
- (SCIDexKitDescriptor *)desc:(NSIndexPath *)ip { return [self rowsInSection:ip.section][ip.row]; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    SCIDexKitHeader *h=[tableView dequeueReusableHeaderFooterViewWithIdentifier:@"header"];
    NSArray<SCIDexKitDescriptor *> *r=[self rowsInSection:section];
    SCIDexKitDescriptor *first=r.firstObject;
    NSUInteger forced=0, seen=0, safe=0, blocked=0, conflicts=0;
    NSMutableSet<NSString *> *families=[NSMutableSet set];
    for(SCIDexKitDescriptor *d in r){
        if(d.overrideValue)forced++;
        if(d.observedKnown)seen++;
        if(d.batchForceAllowed&&d.forceRecommended&&![self isConflictDescriptor:d])safe++;
        if(d.riskLevel>=4)blocked++;
        NSString *f=[self conflictFamilyForDescriptor:d]; if(f.length){ conflicts++; [families addObject:f]; }
    }
    NSString *conflictText=conflicts?[NSString stringWithFormat:@" · conflicts %lu/%@",(unsigned long)conflicts,[[families allObjects] componentsJoinedByString:@","]]:@"";
    h.title.text=first.ownerDisplayName;
    h.detail.text=[NSString stringWithFormat:@"%@ · funcs %lu · seen %lu · forced %lu · safe-batch %lu · blocked %lu%@", first.imageBasename,(unsigned long)r.count,(unsigned long)seen,(unsigned long)forced,(unsigned long)safe,(unsigned long)blocked,conflictText];
    h.clearButton.enabled=forced>0;
    h.clearButton.alpha=forced>0?1:.35;
    __weak typeof(self) ws=self;
    __weak SCIDexKitHeader *wh=h;
    h.observePressed=^{ [ws observeRows:r]; };
    h.clearPressed=^{ [ws clearOverridesInRows:r]; };
    h.actionsPressed=^{ [ws showGroupActionsForRows:r sourceView:wh]; };
    return h;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)ip {
    SCIDexKitCell *c=[tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:ip];
    SCIDexKitDescriptor *d=[self desc:ip];
    c.title.text=d.selectorName;
    NSString *sys=d.observedKnown?(d.observedValue?@"ON":@"OFF"):@"unknown";
    NSString *forced=d.overrideValue?(d.overrideValue.boolValue?@"FORCE ON":@"FORCE OFF"):@"SYSTEM";
    NSString *eff=[self stateText:[self effective:d]];
    NSString *cat=d.semanticCategory.length?d.semanticCategory:@"unknown-bool";
    NSString *conflict=[self conflictFamilyForDescriptor:d];
    NSString *conflictPart=conflict.length?[NSString stringWithFormat:@" · conflict %@",conflict]:@"";
    c.detail.text=[NSString stringWithFormat:@"%@ · risk %@ · %@%@ · effective %@ · system %@ · %@ · %@",cat,[self riskText:d.riskLevel],[self policyText:d],conflictPart,eff,sys,forced,SCIDexKitIsHookInstalled(d.overrideKey)?@"live":@"off"];
    if(d.overrideValue){ c.state.selectedSegmentIndex=d.overrideValue.boolValue?2:1; } else { c.state.selectedSegmentIndex=0; }
    c.state.enabled=!d.unavailable;
    c.state.alpha=d.unavailable?.45:1;
    __weak typeof(self) ws=self;
    c.stateChanged=^(NSInteger idx){ [ws applySegment:idx descriptor:d]; };
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    SCIDexKitDescriptor *d=[self desc:ip];
    NSString *conflict=[self conflictFamilyForDescriptor:d];
    NSString *msg=[NSString stringWithFormat:@"Owner:\n%@\n\nSelector:\n%@\n\nImage: %@\nType: %@\nCategory: %@\nRisk: %@\nPolicy: %@\nConflict family: %@\nReason: %@\nFamily: %@\nIMP: 0x%llx %@\n\nFlow:\n1. Discovery: listed by classifier.\n2. Observation: observe-only learns real runtime use.\n3. Override: force only safe gates or explicit per-row confirmation.\n\nOverride: %@\nObserved: %@\nHook: %@\n\n%@",d.className,d.selectorName,d.imageBasename,d.typeEncoding,d.semanticCategory.length?d.semanticCategory:@"unknown-bool",[self riskText:d.riskLevel],[self policyText:d],conflict.length?conflict:@"none",d.classificationReason.length?d.classificationReason:@"",d.familyKey.length?d.familyKey:@"",(unsigned long long)d.impAddress,d.impSymbol.length?d.impSymbol:@"",d.overrideValue?d.overrideValue.stringValue:@"System",d.observedKnown?(d.observedValue?@"ON":@"OFF"):@"unknown",SCIDexKitIsHookInstalled(d.overrideKey)?@"installed":@"not installed",d.overrideKey];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:d.selectorName message:msg preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Observe only" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self observeRows:@[d]];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force ON" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self forceDescriptor:d value:YES];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Force OFF" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self forceDescriptor:d value:NO];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"System" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){[self setOverrideValue:nil descriptor:d];}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy key" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){UIPasteboard.generalPasteboard.string=d.overrideKey;}]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell=[tv cellForRowAtIndexPath:ip];
    if(a.popoverPresentationController){a.popoverPresentationController.sourceView=cell; a.popoverPresentationController.sourceRect=cell.bounds;}
    [self presentViewController:a animated:YES completion:nil];
}
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView { return nil; }
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text { _query=text; [self reload]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar { [searchBar resignFirstResponder]; }
@end
