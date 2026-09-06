#import "RYGRuntimeInventoryViewController.h"
#import "RYGRuntimeInventory.h"
#import "RYGRuntimeMachOInspector.h"
#import "RYGRuntimeValueStore.h"
#import "../UI/RYGLiquidGlass.h"
#import "../UI/RYGPopupChrome.h"
#import <objc/runtime.h>

@interface RYGRuntimeInventoryViewController ()
@property(nonatomic, copy) NSString *imagePath;
@property(nonatomic, copy) NSString *imageTitle;
@property(nonatomic, copy) NSArray<NSDictionary *> *rows;
@end

@implementation RYGRuntimeInventoryViewController

- (instancetype)initWithImagePath:(NSString *)imagePath title:(NSString *)title {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_imagePath=[imagePath copy]?:@"";_imageTitle=[title copy]?:@"Inventory";_rows=@[];}
    return self;
}

static NSString *RYGInventoryCanonical(NSString *path){NSString *s=path.stringByStandardizingPath;NSString *r=s.stringByResolvingSymlinksInPath;return r.length?r.stringByStandardizingPath:s;}
static BOOL RYGInventoryPathMatches(NSString *a,NSString *b){return a.length&&b.length&&[RYGInventoryCanonical(a) isEqualToString:RYGInventoryCanonical(b)];}

- (BOOL)objcCandidateIsLive:(NSDictionary *)candidate detail:(NSString **)detail {
    NSString *selectorName=candidate[@"selector"]; if(!selectorName.length)return NO; SEL selector=NSSelectorFromString(selectorName);
    unsigned int count=0; Class __unsafe_unretained *classes=objc_copyClassList(&count); BOOL found=NO; NSString *foundDetail=nil;
    for(unsigned int i=0;classes&&i<count&&!found;i++){
        Class cls=classes[i]; const char *raw=cls?class_getImageName(cls):NULL; NSString *path=raw?[NSString stringWithUTF8String:raw]:@"";
        if(!RYGInventoryPathMatches(path,self.imagePath))continue;
        for(NSUInteger meta=0;meta<=1&&!found;meta++){
            Class owner=meta?object_getClass(cls):cls; unsigned int mc=0; Method *methods=owner?class_copyMethodList(owner,&mc):NULL;
            for(unsigned int j=0;methods&&j<mc;j++) if(method_getName(methods[j])==selector){NSString *type=nil;RYGRuntimeValueArgumentKind arg=RYGRuntimeValueArgumentUnsupported;BOOL supported=RYGRuntimeValueClassifyMethod(methods[j],&type,&arg);found=YES;foundDetail=[NSString stringWithFormat:@"%@%@ · %@",meta?@"+":@"-",NSStringFromClass(cls),supported?(type?:@"ABI valid"):@"present · unsupported ABI"];break;}
            if(methods)free(methods);
        }
    }
    if(classes)free(classes); if(detail)*detail=foundDetail; return found;
}

- (void)viewDidLoad {
    [super viewDidLoad]; self.title=[NSString stringWithFormat:@"%@ · Inventory",self.imageTitle]; self.navigationItem.titleView=RYGLiquidGlassNavigationTitleView(self.title);
    self.view.backgroundColor=[RYGPopupChrome backgroundColor]; self.tableView.backgroundColor=[RYGPopupChrome backgroundColor]; RYGLiquidGlassApplyToViewController(self);
    [self reloadInventory];
}

- (void)reloadInventory {
    NSArray *candidates=[RYGRuntimeInventory candidatesForImagePath:self.imagePath]?:@[]; NSMutableArray *rows=[NSMutableArray array];
    NSArray *mach=RYGRuntimeMachOEntries(self.imagePath)?:@[]; NSMutableSet *symbols=[NSMutableSet set]; for(RYGRuntimeMachOEntry *e in mach) if(e.name.length)[symbols addObject:e.name];
    for(NSDictionary *candidate in candidates){NSMutableDictionary *row=[candidate mutableCopy];NSString *kind=candidate[@"kind"];BOOL live=NO;NSString *detail=nil;
        if([kind isEqualToString:@"objc"])live=[self objcCandidateIsLive:candidate detail:&detail];
        else if([kind isEqualToString:@"c"]){NSString *symbol=candidate[@"symbol"];live=[symbols containsObject:symbol]||([symbol hasPrefix:@"_"]&&[symbols containsObject:[symbol substringFromIndex:1]]);detail=live?@"symbol present in selected image":@"not resolved in live symbol table";}
        row[@"live"]=@(live);row[@"detail"]=detail?:@"not resolved";[rows addObject:row];}
    self.rows=rows.copy; [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{(void)tableView;(void)section;return self.rows.count;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{(void)tableView;(void)section;return [NSString stringWithFormat:@"%lu static candidates",(unsigned long)self.rows.count];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{(void)tableView;(void)section;return @"WAT-style static inventory is only a candidate layer. Runtime ABI/symbol validation decides whether a candidate is actually present; the inventory never suppresses additional live discoveries.";}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"RYGInventory"];if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RYGInventory"];NSDictionary *row=self.rows[(NSUInteger)indexPath.row];BOOL live=[row[@"live"] boolValue];NSString *name=[row[@"kind"] isEqualToString:@"objc"]?row[@"selector"]:row[@"symbol"];cell.textLabel.text=name?:@"candidate";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@ · %@",row[@"kind"]?:@"?",row[@"family"]?:@"runtime",row[@"detail"]?:@""];cell.detailTextLabel.numberOfLines=2;cell.imageView.image=[UIImage systemImageNamed:live?@"checkmark.circle.fill":@"circle.dashed"];cell.imageView.tintColor=live?UIColor.systemGreenColor:UIColor.secondaryLabelColor;return cell;}
@end
