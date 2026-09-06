#import "RYGCompleteRuntimeSurfaceBrowserViewController.h"
#import "RYGRuntimeSurface.h"
#import "RYGRuntimeValueStore.h"
#import "RYGRuntimeMachOBrowserViewController.h"
#import "RYGRuntimeInventoryViewController.h"

@interface RYGRuntimeSurfaceBrowserViewController (RYGCompletePrivate)
- (NSString *)currentForEntry:(RYGRuntimeEntry *)entry raw:(id _Nullable * _Nullable)raw;
@end

@interface RYGCompleteRuntimeSurfaceBrowserViewController ()
@property(nonatomic, strong) RYGRuntimeSurfaceSpec *ryg_completeSpec;
@end

@implementation RYGCompleteRuntimeSurfaceBrowserViewController

- (instancetype)initWithSpec:(RYGRuntimeSurfaceSpec *)spec initialQuery:(NSString *)initialQuery {
    if ((self=[super initWithSpec:spec initialQuery:initialQuery])) _ryg_completeSpec=spec;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!self.ryg_completeSpec.runtimeImagePath.length) return;
    __weak typeof(self) weakSelf=self;
    UIAction *mach=[UIAction actionWithTitle:@"C / Mach-O"
                                      image:[UIImage systemImageNamed:@"terminal"]
                                 identifier:nil
                                    handler:^(__unused UIAction *action){ [weakSelf openMachO]; }];
    UIAction *inventory=[UIAction actionWithTitle:@"Runtime Inventory"
                                           image:[UIImage systemImageNamed:@"list.bullet.rectangle"]
                                      identifier:nil
                                         handler:^(__unused UIAction *action){ [weakSelf openInventory]; }];
    UIBarButtonItem *inspect=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                              menu:[UIMenu menuWithTitle:@"Selected image" children:@[mach,inventory]]];
    NSMutableArray *items=[self.navigationItem.rightBarButtonItems mutableCopy]?:[NSMutableArray array];
    [items addObject:inspect]; self.navigationItem.rightBarButtonItems=items;
}

- (void)openMachO {
    RYGRuntimeSurfaceSpec *spec=self.ryg_completeSpec; if(!spec.runtimeImagePath.length)return;
    RYGRuntimeMachOBrowserViewController *vc=[[RYGRuntimeMachOBrowserViewController alloc] initWithImagePath:spec.runtimeImagePath title:spec.title?:@"Image"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openInventory {
    RYGRuntimeSurfaceSpec *spec=self.ryg_completeSpec; if(!spec.runtimeImagePath.length)return;
    RYGRuntimeInventoryViewController *vc=[[RYGRuntimeInventoryViewController alloc] initWithImagePath:spec.runtimeImagePath title:spec.title?:@"Image"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSString *)currentForEntry:(RYGRuntimeEntry *)entry raw:(id *)raw {
    // BOOL(id)/BOOL(q|Q) entries cannot be invoked safely by the browser because
    // an argument would have to be fabricated. RYGRuntimeValueRead arms the
    // pass-through observer/hook and returns the last real Instagram invocation.
    if ([entry.selectorName containsString:@":"]) {
        return RYGRuntimeValueRead(entry.className,entry.selectorName,entry.classMethod,nil,raw);
    }
    return [super currentForEntry:entry raw:raw];
}

@end
