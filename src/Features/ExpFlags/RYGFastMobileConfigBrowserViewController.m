#import "RYGFastMobileConfigBrowserViewController.h"
#import "RYGMobileConfig.h"
#import "RYGMobileConfigJSONIO.h"
#import "../../UI/RYGLiquidGlass.h"
#import "../../UI/RYGPopupChrome.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <math.h>

static NSString *const kRYGFastMCSeparator = @": : ";
static const void *kRYGFastMCParamKey = &kRYGFastMCParamKey;

typedef NS_ENUM(NSInteger, RYGFastMCScope) { RYGFastMCScopeAll = 0, RYGFastMCScopeSeen, RYGFastMCScopeNotSeen, RYGFastMCScopeOverridden };
typedef NS_ENUM(NSInteger, RYGFastMCValueType) { RYGFastMCValueTypeUnknown = 0, RYGFastMCValueTypeBool, RYGFastMCValueTypeInt, RYGFastMCValueTypeDouble, RYGFastMCValueTypeString };

static NSString *RYGFastMCNormalize(NSString *value) {
    if (!value.length) return @"";
    NSString *lower = value.lowercaseString;
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    BOOL space = YES;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar c = [lower characterAtIndex:index];
        BOOL alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
        if (alnum) { [out appendFormat:@"%C", c]; space = NO; }
        else if (!space) { [out appendString:@" "]; space = YES; }
    }
    return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static NSArray<NSString *> *RYGFastMCTokens(NSString *query) {
    NSString *normalized = RYGFastMCNormalize(query);
    if (!normalized.length) return @[];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *token in [normalized componentsSeparatedByString:@" "]) if (token.length) [tokens addObject:token];
    return tokens.copy;
}

static BOOL RYGFastMCBlobMatches(NSString *blob, NSArray<NSString *> *tokens) {
    if (!tokens.count) return YES;
    NSString *text = blob ?: @"";
    NSString *compact = [text stringByReplacingOccurrencesOfString:@" " withString:@""];
    for (NSString *token in tokens) {
        NSString *compactToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([text rangeOfString:token].location == NSNotFound && [compact rangeOfString:compactToken].location == NSNotFound) return NO;
    }
    return YES;
}

static BOOL RYGFastMCParseLine(NSString *line, unsigned int *paramIndex, NSString **valueText) {
    if (![line isKindOfClass:NSString.class]) return NO;
    NSRange separator = [line rangeOfString:kRYGFastMCSeparator];
    if (separator.location == NSNotFound) return NO;
    NSString *indexText = [[line substringToIndex:separator.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    const char *raw = indexText.UTF8String;
    if (!raw || !*raw || *raw == '-') return NO;
    char *end = NULL;
    unsigned long long numeric = strtoull(raw, &end, 10);
    if (end == raw || *end != '\0' || numeric > UINT32_MAX) return NO;
    if (paramIndex) *paramIndex = (unsigned int)numeric;
    if (valueText) *valueText = [line substringFromIndex:NSMaxRange(separator)];
    return YES;
}

static NSString *RYGFastMCConfigKey(unsigned int configNumber) { return [NSString stringWithFormat:@"%u:", configNumber]; }

static id RYGFastMCParsedRuntimeValue(RYGMCParam *param, NSString *text) {
    if (!param || !text) return nil;
    NSString *trim = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    switch (param.type) {
        case RYGMCTypeBool: {
            NSString *lower = trim.lowercaseString;
            if ([lower isEqualToString:@"true"]) return @YES;
            if ([lower isEqualToString:@"false"]) return @NO;
            return nil;
        }
        case RYGMCTypeInt: {
            const char *raw = trim.UTF8String; if (!raw || !*raw) return nil;
            char *end = NULL; long long value = strtoll(raw, &end, 10);
            return end != raw && *end == '\0' ? @(value) : nil;
        }
        case RYGMCTypeDouble: {
            const char *raw = trim.UTF8String; if (!raw || !*raw) return nil;
            char *end = NULL; double value = strtod(raw, &end);
            return end != raw && *end == '\0' && isfinite(value) ? @(value) : nil;
        }
        case RYGMCTypeString: return text ?: @"";
        default: return nil;
    }
}

@interface RYGFastMCDocumentStore : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *root;
- (void)load;
- (nullable NSString *)valueTextForParam:(RYGMCParam *)param;
- (BOOL)configIsOverridden:(RYGMCConfig *)config;
- (NSSet<NSNumber *> *)overriddenConfigNumbers;
- (BOOL)setValueText:(nullable NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error;
@end

@implementation RYGFastMCDocumentStore
- (instancetype)init { if ((self = [super init])) _root = [NSMutableDictionary dictionary]; return self; }
- (void)load {
    NSError *error = nil; NSData *data = [RYGMobileConfig.shared ryg_exportOverridesData:&error];
    if (!data.length) { self.root = [NSMutableDictionary dictionary]; return; }
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    self.root = [object isKindOfClass:NSMutableDictionary.class] ? object : ([object isKindOfClass:NSDictionary.class] ? [(NSDictionary *)object mutableCopy] : [NSMutableDictionary dictionary]);
}
- (NSString *)valueTextForParam:(RYGMCParam *)param {
    if (!param) return nil; NSArray *lines = [self.root[RYGFastMCConfigKey(param.configNumber)] isKindOfClass:NSArray.class] ? self.root[RYGFastMCConfigKey(param.configNumber)] : @[];
    for (id raw in lines) { unsigned int index = 0; NSString *value = nil; if (RYGFastMCParseLine(raw, &index, &value) && index == param.paramIndex) return value; }
    return nil;
}
- (BOOL)configIsOverridden:(RYGMCConfig *)config { NSArray *lines = [self.root[RYGFastMCConfigKey(config.number)] isKindOfClass:NSArray.class] ? self.root[RYGFastMCConfigKey(config.number)] : nil; return lines.count > 0; }
- (NSSet<NSNumber *> *)overriddenConfigNumbers {
    NSMutableSet *numbers = [NSMutableSet set];
    [self.root enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) { (void)stop; if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSArray.class] || ![(NSArray *)value count]) return; NSString *digits = [key hasSuffix:@":"] ? [key substringToIndex:key.length - 1] : key; const char *raw = digits.UTF8String; if (!raw || !*raw) return; char *end = NULL; unsigned long long number = strtoull(raw, &end, 10); if (end != raw && *end == '\0' && number <= UINT32_MAX) [numbers addObject:@((unsigned int)number)]; }];
    return numbers.copy;
}
- (BOOL)setValueText:(NSString *)valueText forParam:(RYGMCParam *)param error:(NSError **)error {
    if (!param) return NO;
    NSMutableDictionary *next = [self.root mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = RYGFastMCConfigKey(param.configNumber);
    NSArray *existing = [next[key] isKindOfClass:NSArray.class] ? next[key] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (id raw in existing) { if (![raw isKindOfClass:NSString.class]) continue; unsigned int index = 0; if (RYGFastMCParseLine(raw, &index, NULL) && index == param.paramIndex) continue; [lines addObject:raw]; }
    if (valueText) [lines addObject:[NSString stringWithFormat:@"%u%@%@", param.paramIndex, kRYGFastMCSeparator, valueText]];
    [lines sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) { unsigned int li = UINT32_MAX, ri = UINT32_MAX; RYGFastMCParseLine(left, &li, NULL); RYGFastMCParseLine(right, &ri, NULL); if (li < ri) return NSOrderedAscending; if (li > ri) return NSOrderedDescending; return [left compare:right]; }];
    if (lines.count) next[key] = lines.copy; else [next removeObjectForKey:key];

    NSData *canonical = [NSJSONSerialization dataWithJSONObject:next options:0 error:error];
    if (!canonical) return NO;
    RYGMobileConfig *engine = RYGMobileConfig.shared;
    if (param.isRuntimeBacked && RYGMCTypeIsRuntimeValue(param.type)) {
        if (valueText) {
            id runtimeValue = RYGFastMCParsedRuntimeValue(param, valueText);
            if (!runtimeValue || ![engine setOverride:runtimeValue for:param]) {
                if (error && !*error) *error = [NSError errorWithDomain:@"com.ryukgram.mobileconfig.fast" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not apply this runtime override."}];
                return NO;
            }
        } else {
            [engine clearOverrideFor:param];
        }
    }

    NSString *nativePath = [engine ryg_nativeOverridesJSONPath];
    if (nativePath.length && ![canonical writeToFile:nativePath options:NSDataWritingAtomic error:error]) return NO;
    self.root = next;
    [engine ryg_syncPersistedJSONToNativeDataDirectory];
    return YES;
}
@end

static RYGFastMCValueType RYGFastMCTypeForParam(RYGMCParam *param, NSString *documentText) {
    if (param.isRuntimeBacked) {
        switch (param.type) { case RYGMCTypeBool:return RYGFastMCValueTypeBool; case RYGMCTypeInt:return RYGFastMCValueTypeInt; case RYGMCTypeDouble:return RYGFastMCValueTypeDouble; case RYGMCTypeString:return RYGFastMCValueTypeString; default:break; }
    }
    NSString *trim = [documentText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; NSString *lower = trim.lowercaseString;
    if ([lower isEqualToString:@"true"] || [lower isEqualToString:@"false"]) return RYGFastMCValueTypeBool;
    if (trim.length) { const char *raw = trim.UTF8String; char *end = NULL; (void)strtoll(raw, &end, 10); if (end != raw && *end == '\0') return RYGFastMCValueTypeInt; end = NULL; double d = strtod(raw, &end); if (end != raw && *end == '\0' && isfinite(d)) return RYGFastMCValueTypeDouble; return RYGFastMCValueTypeString; }
    NSString *name = RYGFastMCNormalize(param.name); for (NSString *prefix in @[@"is ",@"has ",@"can ",@"should ",@"use ",@"show ",@"hide ",@"enable ",@"enabled ",@"allow ",@"supports "]) if ([name hasPrefix:prefix]) return RYGFastMCValueTypeBool;
    if ([name hasSuffix:@" enabled"] || [name hasSuffix:@" disabled"]) return RYGFastMCValueTypeBool; return RYGFastMCValueTypeUnknown;
}

@interface RYGFastMCConfigDetailViewController : UITableViewController <UISearchResultsUpdating>
@property(nonatomic,strong) RYGMCConfig *config; @property(nonatomic,strong) RYGFastMCDocumentStore *documentStore; @property(nonatomic,copy) NSArray<RYGMCParam *> *visibleParams; @property(nonatomic,strong) UISearchController *searchController; @property(nonatomic,copy) void(^documentDidChange)(void); @property(nonatomic,copy) NSDictionary<NSNumber *,NSString *> *seenByParamIndex; @property(nonatomic,copy) NSDictionary<NSNumber *,id> *nativeByParamIndex;
@end

@interface RYGFastMobileConfigBrowserViewController () <UISearchResultsUpdating>
@property(nonatomic,copy) NSArray<RYGMCConfig *> *allConfigs; @property(nonatomic,copy) NSArray<RYGMCConfig *> *visibleConfigs; @property(nonatomic,copy) NSDictionary<NSNumber *,NSString *> *searchBlobs; @property(nonatomic,copy) NSSet<NSNumber *> *seenConfigs; @property(nonatomic,strong) RYGFastMCDocumentStore *documentStore; @property(nonatomic,strong) UISearchController *searchController; @property(nonatomic,assign) RYGFastMCScope scope; @property(nonatomic,assign) NSUInteger loadGeneration; @property(nonatomic,assign) BOOL loading;
@end

@implementation RYGFastMobileConfigBrowserViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"MobileConfig"; self.scope=RYGFastMCScopeAll; self.view.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=56.0;
    self.searchController=[UISearchController new]; self.searchController.searchResultsUpdater=self; self.searchController.obscuresBackgroundDuringPresentation=NO; self.searchController.searchBar.placeholder=@"Config, parameter or ID"; self.navigationItem.searchController=self.searchController; self.navigationItem.hidesSearchBarWhenScrolling=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] menu:[self scopeMenu]]; self.tableView.refreshControl=[UIRefreshControl new]; [self.tableView.refreshControl addTarget:self action:@selector(forceReload) forControlEvents:UIControlEventValueChanged]; RYGLiquidGlassApplyToViewController(self); dispatch_async(dispatch_get_main_queue(), ^{ [self loadModel:NO]; });
}
- (UIMenu *)scopeMenu {
    NSArray *titles=@[@"All",@"Seen at runtime",@"Not seen",@"Overridden"]; NSMutableArray *actions=[NSMutableArray array]; __weak typeof(self) weakSelf=self;
    for (NSInteger index=0; index<(NSInteger)titles.count; index++) { UIAction *action=[UIAction actionWithTitle:titles[(NSUInteger)index] image:nil identifier:nil handler:^(__unused UIAction *item){ weakSelf.scope=(RYGFastMCScope)index; weakSelf.navigationItem.rightBarButtonItem.menu=[weakSelf scopeMenu]; [weakSelf applyFilter]; }]; action.state=self.scope==index?UIMenuElementStateOn:UIMenuElementStateOff; [actions addObject:action]; }
    return [UIMenu menuWithTitle:@"Filter" image:nil identifier:nil options:UIMenuOptionsSingleSelection children:actions];
}
- (void)forceReload { [self loadModel:YES]; }
- (void)loadModel:(BOOL)force {
    if (self.loading && !force) return; NSUInteger generation=++self.loadGeneration; self.loading=YES; UIActivityIndicatorView *spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; [spinner startAnimating]; self.tableView.backgroundView=spinner; __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0), ^{ RYGMobileConfig *engine=RYGMobileConfig.shared; if(force)[engine reloadFromRuntime]; else [engine prepare]; NSArray<RYGMCConfig *> *configs=engine.allConfigs ?: @[]; RYGFastMCDocumentStore *store=[RYGFastMCDocumentStore new]; [store load]; NSMutableDictionary *blobs=[NSMutableDictionary dictionaryWithCapacity:configs.count]; NSMutableSet *seen=[NSMutableSet set]; for(RYGMCConfig *config in configs){ @autoreleasepool { NSMutableString *blob=[NSMutableString stringWithFormat:@"%@ %u ",RYGFastMCNormalize(config.name),config.number]; BOOL configSeen=NO; for(RYGMCParam *param in config.params){ [blob appendFormat:@"%@ %u %llu ",RYGFastMCNormalize(param.name),param.paramIndex,param.paramID]; if(!configSeen&&param.isRuntimeBacked&&[engine callSiteFor:param].length)configSeen=YES; } blobs[@(config.number)]=blob.copy; if(configSeen)[seen addObject:@(config.number)]; } } dispatch_async(dispatch_get_main_queue(), ^{ __strong typeof(weakSelf) self=weakSelf; if(!self||generation!=self.loadGeneration)return; self.allConfigs=configs; self.searchBlobs=blobs.copy; self.seenConfigs=seen.copy; self.documentStore=store; self.loading=NO; [self.tableView.refreshControl endRefreshing]; [self applyFilter]; }); });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { (void)searchController; [self applyFilter]; }
- (void)applyFilter {
    if(self.loading)return; NSArray *tokens=RYGFastMCTokens(self.searchController.searchBar.text ?: @""); NSSet *overridden=[self.documentStore overriddenConfigNumbers]; NSMutableArray *visible=[NSMutableArray array]; for(RYGMCConfig *config in self.allConfigs ?: @[]){ NSNumber *number=@(config.number); BOOL seen=[self.seenConfigs containsObject:number], over=[overridden containsObject:number]; if(self.scope==RYGFastMCScopeSeen&&!seen)continue; if(self.scope==RYGFastMCScopeNotSeen&&seen)continue; if(self.scope==RYGFastMCScopeOverridden&&!over)continue; if(!RYGFastMCBlobMatches(self.searchBlobs[number],tokens))continue; [visible addObject:config]; } self.visibleConfigs=visible.copy; [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;(void)section; return self.visibleConfigs.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"RYGFastMCConfig"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastMCConfig"]; RYGMCConfig *config=self.visibleConfigs[(NSUInteger)indexPath.row]; cell.textLabel.text=config.displayName; BOOL seen=[self.seenConfigs containsObject:@(config.number)], over=[self.documentStore configIsOverridden:config]; cell.detailTextLabel.text=[NSString stringWithFormat:@"#%u · %lu params · %@%@",config.number,(unsigned long)config.params.count,seen?@"seen":@"not seen",over?@" · overridden":@""]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYGFastMCConfigDetailViewController *detail=[[RYGFastMCConfigDetailViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]; detail.config=self.visibleConfigs[(NSUInteger)indexPath.row]; detail.documentStore=self.documentStore; __weak typeof(self) weakSelf=self; detail.documentDidChange=^{[weakSelf applyFilter];}; [self.navigationController pushViewController:detail animated:YES]; }
@end

@implementation RYGFastMCConfigDetailViewController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=self.config.name.length?self.config.name:[NSString stringWithFormat:@"Config %u",self.config.number]; self.navigationItem.titleView=RYGLiquidGlassNavigationTitleView(self.title); self.view.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=56.0; self.searchController=[UISearchController new]; self.searchController.searchResultsUpdater=self; self.searchController.obscuresBackgroundDuringPresentation=NO; self.searchController.searchBar.placeholder=@"Parameter or ID"; self.navigationItem.searchController=self.searchController; self.navigationItem.hidesSearchBarWhenScrolling=NO; self.visibleParams=self.config.params ?: @[];
    NSMutableDictionary *seen=[NSMutableDictionary dictionary], *native=[NSMutableDictionary dictionary]; RYGMobileConfig *engine=RYGMobileConfig.shared; for(RYGMCParam *param in self.config.params ?: @[]){ NSString *callSite=param.isRuntimeBacked?[engine callSiteFor:param]:nil; if(callSite.length)seen[@(param.paramIndex)]=callSite; if(param.isRuntimeBacked){ id value=[engine liveValueFor:param]; if(value)native[@(param.paramIndex)]=value; } } self.seenByParamIndex=seen.copy; self.nativeByParamIndex=native.copy; RYGLiquidGlassApplyToViewController(self);
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { NSArray *tokens=RYGFastMCTokens(searchController.searchBar.text ?: @""); if(!tokens.count)self.visibleParams=self.config.params ?: @[]; else self.visibleParams=[self.config.params filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RYGMCParam *param,NSDictionary *bindings){(void)bindings;return RYGFastMCBlobMatches([NSString stringWithFormat:@"%@ %u %llu",RYGFastMCNormalize(param.name),param.paramIndex,param.paramID],tokens);}]]; [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;(void)section; return self.visibleParams.count; }
- (BOOL)setText:(NSString *)text forParam:(RYGMCParam *)param { NSError *error=nil; BOOL ok=[self.documentStore setValueText:text forParam:param error:&error]; if(!ok)[RYGUtils showErrorHUDWithDescription:error.localizedDescription ?: @"Could not update mc_overrides.json"]; else { if(self.documentDidChange)self.documentDidChange(); [self.tableView reloadData]; } return ok; }
- (void)boolChanged:(UISwitch *)toggle { RYGMCParam *param=objc_getAssociatedObject(toggle,kRYGFastMCParamKey); if(!param)return; if(![self setText:toggle.isOn?@"true":@"false" forParam:param])toggle.on=!toggle.isOn; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"RYGFastMCParam"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGFastMCParam"]; cell.accessoryView=nil;cell.accessoryType=UITableViewCellAccessoryNone; RYGMCParam *param=self.visibleParams[(NSUInteger)indexPath.row]; NSString *documentText=[self.documentStore valueTextForParam:param]; RYGFastMCValueType type=RYGFastMCTypeForParam(param,documentText); cell.textLabel.text=param.name.length?param.name:[NSString stringWithFormat:@"Parameter %u",param.paramIndex]; NSString *seen=self.seenByParamIndex[@(param.paramIndex)]?@"seen":@"not seen"; cell.detailTextLabel.text=documentText?[NSString stringWithFormat:@"#%u · %@ · override %@",param.paramIndex,seen,documentText]:[NSString stringWithFormat:@"#%u · %@ · %@",param.paramIndex,seen,param.typeName ?: @"mapping"]; if(type==RYGFastMCValueTypeBool){ UISwitch *toggle=[UISwitch new]; if(documentText)toggle.on=[documentText.lowercaseString isEqualToString:@"true"]; else { id native=self.nativeByParamIndex[@(param.paramIndex)]; toggle.on=[native isKindOfClass:NSNumber.class]?[native boolValue]:NO; } objc_setAssociatedObject(toggle,kRYGFastMCParamKey,param,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [toggle addTarget:self action:@selector(boolChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle; cell.selectionStyle=UITableViewCellSelectionStyleNone; } else { cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; cell.selectionStyle=UITableViewCellSelectionStyleDefault; } return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView cellForRowAtIndexPath:indexPath]; [tableView deselectRowAtIndexPath:indexPath animated:YES]; RYGMCParam *param=self.visibleParams[(NSUInteger)indexPath.row]; NSString *text=[self.documentStore valueTextForParam:param]; RYGFastMCValueType type=RYGFastMCTypeForParam(param,text); if(type==RYGFastMCValueTypeBool)return; UIAlertController *alert=[UIAlertController alertControllerWithTitle:param.name.length?param.name:@"MobileConfig value" message:nil preferredStyle:UIAlertControllerStyleAlert]; [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=text ?: @"";field.keyboardType=(type==RYGFastMCValueTypeInt||type==RYGFastMCValueTypeDouble)?UIKeyboardTypeNumbersAndPunctuation:UIKeyboardTypeDefault;}]; [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; if(text.length)[alert addAction:[UIAlertAction actionWithTitle:@"Use native / remove" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){[self setText:nil forParam:param];}]]; [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){[self setText:alert.textFields.firstObject.text ?: @"" forParam:param];}]]; if(UIDevice.currentDevice.userInterfaceIdiom==UIUserInterfaceIdiomPad){alert.popoverPresentationController.sourceView=cell;alert.popoverPresentationController.sourceRect=cell.bounds;} [self presentViewController:alert animated:YES completion:nil]; }
@end
